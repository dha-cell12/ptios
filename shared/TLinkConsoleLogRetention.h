#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace TLinkConsoleLogRetention {
static const std::size_t KeepCompleted=50,ScanLimit=4096;
// Only generated UUID run logs, never latest, arbitrary names or nested paths.
inline bool RunName(const std::string &name){
    if(name.size()!=40&&name.size()!=47)return false;
    for(std::size_t n=0;n<36;++n){
        const char c=name[n];
        if(n==8||n==13||n==18||n==23){if(c!='-')return false;}
        else if(!((c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F')))return false;
    }
    return name.compare(36,std::string::npos,name.size()==40?".log":"-helper.log")==0;
}
struct Identity {
    uint64_t device=0,inode=0,size=0;
    int64_t modified=0,modifiedNanos=0,changed=0,changedNanos=0;
};
inline bool Same(const Identity &a,const Identity &b){
    return a.device==b.device&&a.inode==b.inode&&a.size==b.size&&a.modified==b.modified&&
        a.modifiedNanos==b.modifiedNanos&&a.changed==b.changed&&a.changedNanos==b.changedNanos;
}
struct Candidate {std::string name;Identity identity;};
inline std::array<uint8_t,24> Proof(const Identity &identity){
    std::array<uint8_t,24> bytes{};std::memcpy(bytes.data(),"TLCLOG1",8);
    for(unsigned n=0;n<8;++n){bytes[8+n]=uint8_t(identity.device>>(56-8*n));bytes[16+n]=uint8_t(identity.inode>>(56-8*n));}return bytes;
}
inline void NewestFirst(std::vector<Candidate> &rows){
    std::sort(rows.begin(),rows.end(),[](const Candidate &a,const Candidate &b){
        if(a.identity.modified!=b.identity.modified)return a.identity.modified>b.identity.modified;
        if(a.identity.modifiedNanos!=b.identity.modifiedNanos)return a.identity.modifiedNanos>b.identity.modifiedNanos;
        return a.name<b.name;
    });
}
struct Result {bool marked=false,incomplete=false;std::size_t scanned=0,eligible=0,removed=0,busy=0,refused=0,errors=0;};
}

#if defined(__APPLE__)
#include <cerrno>
#include <dirent.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <unistd.h>

namespace TLinkConsoleLogRetention {
namespace Detail {
static const char MarkerName[]="com.tlinkauto.console.completed.v1";
class FD {
    int value_;
public:
    explicit FD(int value):value_(value){}
    ~FD(){if(value_>=0)::close(value_);}
    FD(const FD &)=delete;FD &operator=(const FD &)=delete;
    int get()const{return value_;}
};
inline bool Owned(const struct stat &s){return S_ISREG(s.st_mode)&&s.st_nlink==1&&s.st_size>=0&&s.st_uid==::geteuid()&&(s.st_mode&022)==0;}
inline Identity Identify(const struct stat &s){
    Identity result;result.device=s.st_dev;result.inode=s.st_ino;result.size=(uint64_t)s.st_size;
    result.modified=s.st_mtimespec.tv_sec;result.modifiedNanos=s.st_mtimespec.tv_nsec;
    result.changed=s.st_ctimespec.tv_sec;result.changedNanos=s.st_ctimespec.tv_nsec;return result;
}
inline bool Marked(int fd,const struct stat &info){
    const auto expected=Proof(Identify(info));uint8_t bytes[25]={};
    const ssize_t length=::fgetxattr(fd,MarkerName,bytes,sizeof(bytes),0,0);
    return length==(ssize_t)expected.size()&&std::memcmp(bytes,expected.data(),expected.size())==0;
}
inline bool AtPath(int directory,const std::string &name,const struct stat &descriptor){
    struct stat path;
    return ::fstatat(directory,name.c_str(),&path,AT_SYMLINK_NOFOLLOW)==0&&Owned(path)&&Same(Identify(path),Identify(descriptor));
}
// The exclusive lock coordinates cooperating cleaners. The path check refuses
// replacements already observed; arbitrary mutations after it are not atomic.
inline void Retire(int directory,const Candidate &candidate,Result &result){
    FD file(::openat(directory,candidate.name.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));
    if(file.get()<0){++result.refused;return;}
    if(::flock(file.get(),LOCK_EX|LOCK_NB)!=0){++result.busy;return;}
    struct stat info;
    if(::fstat(file.get(),&info)!=0||!Owned(info)||!Same(candidate.identity,Identify(info))||
        !Marked(file.get(),info)||!AtPath(directory,candidate.name,info)){++result.refused;return;}
    if(::unlinkat(directory,candidate.name.c_str(),0)==0)++result.removed;else ++result.errors;
}
}
inline Result Sweep(int directory,std::size_t keep=KeepCompleted,std::size_t scanLimit=ScanLimit){
    Result result;struct stat root;
    if(::fstat(directory,&root)!=0||!S_ISDIR(root.st_mode)){++result.errors;return result;}
    // A fresh open description gives each sweep its own enumeration offset.
    Detail::FD scan(::openat(directory,".",O_RDONLY|O_DIRECTORY|O_CLOEXEC));
    if(scan.get()<0){++result.errors;return result;}
    const int iteratorFD=::dup(scan.get());if(iteratorFD<0){++result.errors;return result;}
    DIR *raw=::fdopendir(iteratorFD);if(!raw){::close(iteratorFD);++result.errors;return result;}
    struct Directory {DIR *value;~Directory(){::closedir(value);}} iterator{raw};
    std::vector<Candidate> candidates;candidates.reserve(std::min(scanLimit,std::size_t(128)));
    for(;;){
        errno=0;const struct dirent *entry=::readdir(raw);
        if(!entry){if(errno){result.incomplete=true;++result.errors;}break;}
        if(!std::strcmp(entry->d_name,".")||!std::strcmp(entry->d_name,".."))continue;
        if(result.scanned==scanLimit){result.incomplete=true;break;}
        ++result.scanned;std::string name(entry->d_name);if(!RunName(name))continue;
        Detail::FD file(::openat(directory,name.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));
        if(file.get()<0)continue;
        struct stat info;if(::fstat(file.get(),&info)!=0||!Detail::Owned(info)||!Detail::Marked(file.get(),info)||!Detail::AtPath(directory,name,info))continue;
        Candidate candidate;candidate.name=std::move(name);candidate.identity=Detail::Identify(info);candidates.push_back(std::move(candidate));
    }
    result.eligible=candidates.size();
    // Incomplete discovery never chooses victims from a partial ordering.
    if(result.incomplete)return result;
    NewestFirst(candidates);
    for(std::size_t n=std::min(keep,candidates.size());n<candidates.size();++n)Detail::Retire(directory,candidates[n],result);
    return result;
}
// Call only after every accepted log write is drained. Active logs carry no
// completion marker; legacy/unproven logs are deliberately never collected.
inline Result Complete(const char *path) noexcept {
    Result result;
    try {
        if(!path)return result;
        const std::string full(path);const auto slash=full.find_last_of('/');
        if(slash==std::string::npos||!RunName(full.substr(slash+1)))return result;
        const std::string parent=full.substr(0,slash),name=full.substr(slash+1);
        if(parent.size()<6||parent.compare(parent.size()-6,6,"/_logs")!=0)return result;
        Detail::FD directory(::open(parent.c_str(),O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC));
        if(directory.get()<0){++result.errors;return result;}
        {
            Detail::FD file(::openat(directory.get(),name.c_str(),O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC));
            if(file.get()<0){++result.errors;return result;}
            if(::flock(file.get(),LOCK_EX|LOCK_NB)!=0){++result.busy;return result;}
            struct stat info;
            if(::fstat(file.get(),&info)!=0||!Detail::Owned(info)||!Detail::AtPath(directory.get(),name,info)){++result.refused;return result;}
            const auto proof=Proof(Detail::Identify(info));
            if(::fsetxattr(file.get(),Detail::MarkerName,proof.data(),proof.size(),0,0)!=0){++result.errors;return result;}
            result.marked=true;
        }
        Result swept=Sweep(directory.get());swept.marked=result.marked;return swept;
    } catch(...) {++result.errors;return result;}
}
class Completion {
    std::string path_;
public:
    explicit Completion(const char *path) noexcept {try {if(path)path_=path;}catch(...) {}}
    ~Completion() noexcept {Complete(path_.c_str());}
    Completion(const Completion &)=delete;Completion &operator=(const Completion &)=delete;
};
}
#endif
