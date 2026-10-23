#ifndef TLINK_CAPTURE_CLEANUP_H
#define TLINK_CAPTURE_CLEANUP_H
#include "TLinkCaptureLeasePOSIX.h"
#include <dirent.h>
struct TLinkCaptureDirectoryClose {void operator()(DIR *value)const{if(value)closedir(value);}};
struct TLinkCaptureSweepFD {int value;explicit TLinkCaptureSweepFD(int fd):value(fd){}~TLinkCaptureSweepFD(){if(value>=0)::close(value);}
    TLinkCaptureSweepFD(const TLinkCaptureSweepFD &)=delete;TLinkCaptureSweepFD &operator=(const TLinkCaptureSweepFD &)=delete;};
struct TLinkCaptureSweepResult {size_t entries=0,candidates=0,removed=0,busy=0,retained=0;bool directoryError=false;};
// Internal directory argument supports an isolated test directory. Production
// passes only /tmp. No recursion, waiting lock, image payload read or directory sort.
inline TLinkCaptureSweepResult TLinkCaptureSweepDirectory(const char *directory,uint64_t (*clockNow)()=TLinkNativeNowNs){
    TLinkCaptureSweepResult result;TLinkCaptureSweepBudget budget(clockNow());
    std::unique_ptr<DIR,TLinkCaptureDirectoryClose> dir(opendir(directory));if(!dir){result.directoryError=true;return result;}
    const int root=dirfd(dir.get());struct dirent *entry;
    while(budget.entry(clockNow())&&(entry=readdir(dir.get()))!=nullptr){
        std::string output;
        if(!TLinkCaptureSweepName(entry->d_name,output))continue;
        if(!budget.candidate())break;
        const std::string marker=output+".lease";
        struct stat st;
        if(fstatat(root,entry->d_name,&st,AT_SYMLINK_NOFOLLOW)!=0||!TLinkCapturePOSIX::secure(st,true)||st.st_uid!=geteuid()) {++result.retained;continue;}
        const int fd=openat(root,entry->d_name,O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC);
        if(fd<0){++result.retained;continue;}
        TLinkCaptureSweepFD held(fd);
        struct stat opened,current;
        if(fstat(fd,&opened)!=0||!TLinkCaptureSameID(TLinkCapturePOSIX::identity(st),TLinkCapturePOSIX::identity(opened))||flock(fd,LOCK_EX|LOCK_NB)!=0){++result.busy;continue;}
        bool removed=false;TLinkCaptureFileID recorded;
        if(TLinkCapturePOSIX::readProof(fd,recorded))removed=TLinkCapturePOSIX::retireAt(root,output.c_str(),marker.c_str(),entry->d_name,fd,recorded);
        else if(opened.st_size==0){
            // Interrupted before marker publication: only an otherwise empty
            // reservation can be retired without a complete identity proof.
            struct stat extra;
            const bool noMarker=fstatat(root,marker.c_str(),&extra,AT_SYMLINK_NOFOLLOW)<0&&errno==ENOENT;
            const bool noOutput=fstatat(root,output.c_str(),&extra,AT_SYMLINK_NOFOLLOW)<0&&errno==ENOENT;
            if(noMarker&&noOutput&&fstatat(root,entry->d_name,&current,AT_SYMLINK_NOFOLLOW)==0&&
                TLinkCaptureSameID(TLinkCapturePOSIX::identity(opened),TLinkCapturePOSIX::identity(current)))removed=unlinkat(root,entry->d_name,0)==0;
        }
        if(removed)++result.removed;else ++result.retained;
    }
    result.entries=budget.entries;result.candidates=budget.candidates;return result;
}
#endif
