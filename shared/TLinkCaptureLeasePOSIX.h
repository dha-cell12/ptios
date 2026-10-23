#ifndef TLINK_CAPTURE_LEASE_POSIX_H
#define TLINK_CAPTURE_LEASE_POSIX_H
#include "TLinkCaptureLease.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/xattr.h>
#include <unistd.h>
#include <cerrno>
struct TLinkCapturePOSIX {
    static TLinkCaptureFileID identity(const struct stat &st){TLinkCaptureFileID id;id.device=uint64_t(st.st_dev);id.inode=uint64_t(st.st_ino);return id;}
    static const char *tagName(){return "com.tlinkauto.capture-owner.v1";}
    static std::string ownerPath(const std::string &marker){return marker+".owner.v1";}
    static void proof(uint8_t *bytes,TLinkCaptureFileID id){
        std::memcpy(bytes,"TLCP0001",8);
        for(unsigned i=0;i<8;++i){bytes[8+i]=uint8_t(id.device>>(56-8*i));bytes[16+i]=uint8_t(id.inode>>(56-8*i));}
    }
    static bool decodeProof(const uint8_t *bytes,TLinkCaptureFileID &id){
        if(std::memcmp(bytes,"TLCP0001",8))return false;id=TLinkCaptureFileID();
        for(unsigned i=0;i<8;++i){id.device=(id.device<<8)|bytes[8+i];id.inode=(id.inode<<8)|bytes[16+i];}return true;
    }
    static bool secure(const struct stat &st,bool owner){
        return S_ISREG(st.st_mode)&&st.st_nlink==1&&(st.st_mode&(owner?022:077))==0&&
            (st.st_uid==0||st.st_uid==geteuid());
    }
    static bool absent(const std::string &path){struct stat st;return lstat(path.c_str(),&st)<0&&errno==ENOENT;}
    static bool marker(const std::string &path,TLinkCaptureFileID &id){
        struct stat st;if(lstat(path.c_str(),&st)!=0||!secure(st,false)||st.st_size!=0)return false;id=identity(st);return true;
    }
    static bool sameMarker(const std::string &path,TLinkCaptureFileID id){TLinkCaptureFileID current;return marker(path,current)&&TLinkCaptureSameID(id,current);}
    static bool samePath(int fd,const std::string &path){
        struct stat a,b;return fstat(fd,&a)==0&&lstat(path.c_str(),&b)==0&&TLinkCaptureSameID(identity(a),identity(b))&&a.st_nlink==1;
    }
    static bool readProof(int fd,TLinkCaptureFileID &id){
        struct stat st;if(fstat(fd,&st)!=0||!secure(st,true)||st.st_size!=24)return false;
        uint8_t bytes[24];ssize_t n;do{n=pread(fd,bytes,sizeof(bytes),0);}while(n<0&&errno==EINTR);
        return n==ssize_t(sizeof(bytes))&&decodeProof(bytes,id);
    }
    static bool tagged(int fd,TLinkCaptureFileID id){
        uint8_t bytes[24],expected[24];proof(expected,id);
        return fgetxattr(fd,tagName(),bytes,sizeof(bytes),0,0)==ssize_t(sizeof(bytes))&&std::memcmp(bytes,expected,sizeof(bytes))==0;
    }
    static bool removeTaggedAt(int directory,const char *name,TLinkCaptureFileID id){
        struct stat preflight;
        if(fstatat(directory,name,&preflight,AT_SYMLINK_NOFOLLOW)!=0)return errno==ENOENT;
        if(!S_ISREG(preflight.st_mode)||preflight.st_nlink!=1||(preflight.st_mode&077)!=0||preflight.st_size<0||uint64_t(preflight.st_size)>32*1024*1024)return false;
        const int fd=openat(directory,name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return errno==ENOENT;
        struct stat st,current;const bool safe=fstat(fd,&st)==0&&TLinkCaptureSameID(identity(preflight),identity(st))&&S_ISREG(st.st_mode)&&st.st_nlink==1&&
            (st.st_mode&077)==0&&st.st_size>=0&&uint64_t(st.st_size)<=32*1024*1024&&tagged(fd,id)&&
            fstatat(directory,name,&current,AT_SYMLINK_NOFOLLOW)==0&&TLinkCaptureSameID(identity(st),identity(current));
        const bool removed=safe&&unlinkat(directory,name,0)==0;::close(fd);return removed;
    }
    static bool ownsOutput(const std::string &path,TLinkCaptureFileID id){
        const int fd=open(path.c_str(),O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return false;
        struct stat st;const bool owned=fstat(fd,&st)==0&&S_ISREG(st.st_mode)&&st.st_nlink==1&&(st.st_mode&077)==0&&
            st.st_size>=0&&uint64_t(st.st_size)<=32*1024*1024&&tagged(fd,id)&&samePath(fd,path);
        ::close(fd);return owned;
    }
    static void removeOutput(const std::string &path,TLinkCaptureFileID id){
        struct stat st;if(lstat(path.c_str(),&st)==0&&S_ISREG(st.st_mode)&&TLinkCaptureSameID(identity(st),id))unlink(path.c_str());
    }
    static void removeMarker(const std::string &path,TLinkCaptureFileID id){if(sameMarker(path,id))unlink(path.c_str());}
    static void removePrivateOutput(const std::string &path,TLinkCaptureFileID id){if(TLinkCaptureLeasePath(path))removeTaggedAt(AT_FDCWD,path.c_str(),id);}
    // Caller holds EX lock on owner fd. Marker goes first, proof/owner goes last;
    // a cleanup-process crash therefore leaves evidence for a subsequent sweep.
    static bool retireAt(int directory,const char *output,const char *markerName,const char *ownerName,int fd,TLinkCaptureFileID id){
        struct stat owner,current;if(fstat(fd,&owner)!=0||!secure(owner,true)||
            fstatat(directory,ownerName,&current,AT_SYMLINK_NOFOLLOW)!=0||!TLinkCaptureSameID(identity(owner),identity(current)))return false;
        struct stat markerStat;
        if(fstatat(directory,markerName,&markerStat,AT_SYMLINK_NOFOLLOW)==0){
            if(!secure(markerStat,false)||markerStat.st_size!=0||!TLinkCaptureSameID(identity(markerStat),id)||unlinkat(directory,markerName,0)!=0)return false;
        }else if(errno!=ENOENT)return false;
        if(!removeTaggedAt(directory,output,id))return false;
        if(fstatat(directory,ownerName,&current,AT_SYMLINK_NOFOLLOW)!=0||!TLinkCaptureSameID(identity(owner),identity(current)))return false;
        return unlinkat(directory,ownerName,0)==0;
    }
    static void releaseMarker(int fd,const std::string &output,TLinkCaptureFileID id){
        if(fd<0)return;const std::string markerName=output+".lease",ownerName=ownerPath(markerName);
        // Work is finished before releaseMarker. Drop our SH explicitly: Darwin
        // can retain it after a failed EX/NB upgrade, so two concurrent finishers
        // could otherwise both fail the upgrade before either closes its fd.
        // A sweeper may win in this gap; retireAt still revalidates the owner inode.
        if(flock(fd,LOCK_UN)==0&&flock(fd,LOCK_EX|LOCK_NB)==0){TLinkCaptureFileID recorded;
            if(readProof(fd,recorded)&&TLinkCaptureSameID(recorded,id))retireAt(AT_FDCWD,output.c_str(),markerName.c_str(),ownerName.c_str(),fd,id);
        }::close(fd);
    }
    static int createMarker(const std::string &path,TLinkCaptureFileID &id){
        const std::string owner=ownerPath(path);
        const int lease=open(owner.c_str(),O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0644);if(lease<0)return -1;
        struct stat ownerStat;const bool ownerOK=fstat(lease,&ownerStat)==0;
        if(!ownerOK||fchmod(lease,0644)!=0||flock(lease,LOCK_SH|LOCK_NB)!=0||!samePath(lease,owner)){if(ownerOK&&samePath(lease,owner))unlink(owner.c_str());::close(lease);return -1;}
        const int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if(fd<0){if(samePath(lease,owner))unlink(owner.c_str());::close(lease);return -1;}
        struct stat st;const bool statOK=fstat(fd,&st)==0;bool ok=statOK;if(ok)id=identity(st);const bool closed=::close(fd)==0;
        uint8_t bytes[24];proof(bytes,id);size_t offset=0;
        while(ok&&closed&&offset<sizeof(bytes)){
            const ssize_t n=::write(lease,bytes+offset,sizeof(bytes)-offset);
            if(n<0&&errno==EINTR)continue;if(n<=0){ok=false;break;}offset+=size_t(n);
        }
        if(ok&&closed&&offset==sizeof(bytes)&&samePath(lease,owner)&&sameMarker(path,id))return lease;
        if(statOK)removeMarker(path,id);if(samePath(lease,owner))unlink(owner.c_str());::close(lease);return -1;
    }
    static int acquireMarker(const std::string &path,TLinkCaptureFileID &id){
        if(!marker(path,id))return -1;const std::string owner=ownerPath(path);
        const int fd=open(owner.c_str(),O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
        if(fd<0)return errno==ENOENT?-2:-1; // Legacy unguarded marker: never swept.
        TLinkCaptureFileID recorded;
        if(flock(fd,LOCK_SH|LOCK_NB)==0&&readProof(fd,recorded)&&TLinkCaptureSameID(recorded,id)&&samePath(fd,owner)&&sameMarker(path,id))return fd;
        ::close(fd);return -1;
    }
    static int createOutput(const std::string &path,TLinkCaptureFileID &id,TLinkCaptureFileID markerID){
        const int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(fd<0)return -1;
        struct stat st;if(fstat(fd,&st)!=0){::close(fd);unlink(path.c_str());return -1;}id=identity(st);
        uint8_t bytes[24];proof(bytes,markerID);
        if(fsetxattr(fd,tagName(),bytes,sizeof(bytes),0,XATTR_CREATE)!=0){::close(fd);removeOutput(path,id);return -1;}return fd;
    }
    static int64_t write(int fd,const uint8_t *bytes,size_t length){return int64_t(::write(fd,bytes,length));}
    static bool interrupted(){return errno==EINTR;}
    static bool close(int fd){return ::close(fd)==0;}
};
using TLinkCaptureClientLease=TLinkCaptureClient<TLinkCapturePOSIX>;
using TLinkCaptureReceiverLease=TLinkCaptureReceiver<TLinkCapturePOSIX>;
inline TLinkCaptureReceiverLease *&TLinkCaptureReceiverSlot(){static thread_local TLinkCaptureReceiverLease *value=nullptr;return value;}
class TLinkCaptureReceiverScope {
    TLinkCaptureReceiverLease *previous_;
public:
    explicit TLinkCaptureReceiverScope(TLinkCaptureReceiverLease *value):previous_(TLinkCaptureReceiverSlot()){TLinkCaptureReceiverSlot()=value;}
    ~TLinkCaptureReceiverScope(){TLinkCaptureReceiverSlot()=previous_;}
    TLinkCaptureReceiverScope(const TLinkCaptureReceiverScope &)=delete;TLinkCaptureReceiverScope &operator=(const TLinkCaptureReceiverScope &)=delete;
};
#endif
