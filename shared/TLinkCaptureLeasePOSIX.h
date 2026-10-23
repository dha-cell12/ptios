#ifndef TLINK_CAPTURE_LEASE_POSIX_H
#define TLINK_CAPTURE_LEASE_POSIX_H
#include "TLinkCaptureLease.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
struct TLinkCapturePOSIX {
    static TLinkCaptureFileID identity(const struct stat &st){TLinkCaptureFileID id;id.device=uint64_t(st.st_dev);id.inode=uint64_t(st.st_ino);return id;}
    static bool absent(const std::string &path){struct stat st;return lstat(path.c_str(),&st)<0&&errno==ENOENT;}
    static bool marker(const std::string &path,TLinkCaptureFileID &id){
        struct stat st;if(lstat(path.c_str(),&st)!=0||!S_ISREG(st.st_mode)||st.st_nlink!=1||(st.st_mode&077)!=0||st.st_size!=0||
            (st.st_uid!=0&&st.st_uid!=geteuid()))return false;
        id=identity(st);return true;
    }
    static bool sameMarker(const std::string &path,TLinkCaptureFileID id){TLinkCaptureFileID current;return marker(path,current)&&TLinkCaptureSameID(id,current);}
    static void removeOutput(const std::string &path,TLinkCaptureFileID id){
        struct stat st;if(lstat(path.c_str(),&st)==0&&S_ISREG(st.st_mode)&&TLinkCaptureSameID(identity(st),id))unlink(path.c_str());
    }
    static void removeMarker(const std::string &path,TLinkCaptureFileID id){if(sameMarker(path,id))unlink(path.c_str());}
    static void removePrivateOutput(const std::string &path){if(TLinkCaptureLeasePath(path))unlink(path.c_str());}
    static bool createMarker(const std::string &path,TLinkCaptureFileID &id){
        const int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(fd<0)return false;
        struct stat st;const bool ok=fstat(fd,&st)==0;
        if(ok)id=identity(st);const bool closed=::close(fd)==0;
        if(!ok){unlink(path.c_str());return false;}
        if(!closed){removeMarker(path,id);return false;}return true;
    }
    static int createOutput(const std::string &path,TLinkCaptureFileID &id){
        const int fd=open(path.c_str(),O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);if(fd<0)return -1;
        struct stat st;if(fstat(fd,&st)!=0){::close(fd);unlink(path.c_str());return -1;}id=identity(st);return fd;
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
