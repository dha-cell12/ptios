#ifndef TLINK_HELPER_CONFIG_SNAPSHOT_H
#define TLINK_HELPER_CONFIG_SNAPSHOT_H
#include <cstdint>
#include <cstddef>
#include <mutex>
struct TLinkHelperConfigIdentity {
    uint64_t device=0,inode=0,size=0;
    int64_t modifiedSeconds=0,modifiedNanos=0,changedSeconds=0,changedNanos=0;
    uint32_t mode=0,uid=0,gid=0;
    bool operator==(const TLinkHelperConfigIdentity &r)const{
        return device==r.device&&inode==r.inode&&size==r.size&&modifiedSeconds==r.modifiedSeconds&&modifiedNanos==r.modifiedNanos&&changedSeconds==r.changedSeconds&&changedNanos==r.changedNanos&&mode==r.mode&&uid==r.uid&&gid==r.gid;
    }
};
class TLinkHelperConfigMemo {
    bool valid_=false;TLinkHelperConfigIdentity identity_;
public:
    bool matches(const TLinkHelperConfigIdentity &identity)const{return valid_&&identity_==identity;}
    void publish(const TLinkHelperConfigIdentity &identity){identity_=identity;valid_=true;}
    void invalidate(){valid_=false;}
};
static const size_t TLinkHelperConfigMaxBytes=1024*1024;
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
static inline int TLinkHelperConfigOpen(const char *path){return ::open(path,O_RDONLY|O_CLOEXEC|O_NONBLOCK);}
struct TLinkHelperConfigOps {
    int (*statPath)(const char *,struct stat *)=::stat;
    int (*openFile)(const char *)=TLinkHelperConfigOpen;
    int (*statFile)(int,struct stat *)=::fstat;
    ssize_t (*readFile)(int,void *,size_t)=::read;
    int (*closeFile)(int)=::close;
};
static inline TLinkHelperConfigIdentity TLinkHelperConfigFileIdentity(const struct stat &s){
    TLinkHelperConfigIdentity out;out.device=uint64_t(s.st_dev);out.inode=uint64_t(s.st_ino);out.size=uint64_t(s.st_size);
#if defined(__APPLE__)
    out.modifiedSeconds=s.st_mtimespec.tv_sec;out.modifiedNanos=s.st_mtimespec.tv_nsec;
    out.changedSeconds=s.st_ctimespec.tv_sec;out.changedNanos=s.st_ctimespec.tv_nsec;
#else
    out.modifiedSeconds=s.st_mtim.tv_sec;out.modifiedNanos=s.st_mtim.tv_nsec;
    out.changedSeconds=s.st_ctim.tv_sec;out.changedNanos=s.st_ctim.tv_nsec;
#endif
    out.mode=uint32_t(s.st_mode);out.uid=uint32_t(s.st_uid);out.gid=uint32_t(s.st_gid);return out;
}
struct TLinkHelperConfigStats {uint64_t checks=0,hits=0,reloads=0,parses=0,failures=0;};
class TLinkHelperConfigSnapshot {
    class File {
        int fd_;int (*close_)(int);
    public:
        File(int fd,int (*closer)(int)):fd_(fd),close_(closer){}
        ~File(){if(fd_>=0)close_(fd_);}
        int close(){int fd=fd_;fd_=-1;return close_(fd);}
        File(const File &)=delete;File &operator=(const File &)=delete;
    };
    std::mutex mutex_;NSString *path_=nil;NSDictionary *snapshot_=nil;TLinkHelperConfigMemo memo_;TLinkHelperConfigStats stats_;TLinkHelperConfigOps ops_;
    NSDictionary *denied(NSString *error){
        return @{@"configPath":path_?:@"",@"configValid":@(false),@"enabled":@(false),@"runtimeDefault":@(false),@"allowAdminRPC":@(false),@"error":error?:@""};
    }
    NSDictionary *failure(NSString *error){
        memo_.invalidate();++stats_.failures;snapshot_=denied(error);return snapshot_;
    }
    NSDictionary *decode(NSData *data){
        if(!data.length)return denied(@"missing_or_empty_config");
        ++stats_.parses;NSError *error=nil;id object=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if(![object isKindOfClass:[NSDictionary class]])return denied(error.localizedDescription?:@"config_parse_failed");
        NSDictionary *dict=(NSDictionary *)object;
        id enabled=dict[@"javascript_helper_runtime_enabled"]?:dict[@"enable_js_helper_execution"];
        id runtimeDefault=dict[@"javascript_helper_runtime_default"],allowAdmin=dict[@"javascript_helper_allow_admin_rpc"];
        return @{@"configPath":path_?:@"",@"configValid":@(true),
            @"enabled":@([enabled respondsToSelector:@selector(boolValue)]&&[enabled boolValue]),
            @"runtimeDefault":@([runtimeDefault respondsToSelector:@selector(boolValue)]&&[runtimeDefault boolValue]),
            @"allowAdminRPC":@([allowAdmin respondsToSelector:@selector(boolValue)]&&[allowAdmin boolValue]),@"error":@""};
    }
    NSDictionary *load(){
        ++stats_.checks;const char *path=[path_ fileSystemRepresentation];struct stat before;
        if(!path||ops_.statPath(path,&before)!=0)return failure(@"missing_or_empty_config");
        if(!S_ISREG(before.st_mode)||before.st_size<0)return failure(@"config_not_regular");
        const auto identity=TLinkHelperConfigFileIdentity(before);
        if(memo_.matches(identity)){++stats_.hits;return snapshot_;}
        if(identity.size>TLinkHelperConfigMaxBytes)return failure(@"config_size_limit");
        ++stats_.reloads;const int fd=ops_.openFile(path);if(fd<0)return failure(@"missing_or_empty_config");File file(fd,ops_.closeFile);
        struct stat opened;
        if(ops_.statFile(fd,&opened)!=0||!(identity==TLinkHelperConfigFileIdentity(opened)))return failure(@"config_changed_during_read");
        NSMutableData *data=[NSMutableData data];uint8_t buffer[4096];unsigned interruptions=0;
        while(true){
            const size_t room=TLinkHelperConfigMaxBytes+1-data.length;
            const ssize_t count=ops_.readFile(fd,buffer,room<sizeof(buffer)?room:sizeof(buffer));
            if(count<0){if(errno==EINTR&&++interruptions<=32)continue;return failure(@"config_read_failed");}
            if(!count)break;
            if(size_t(count)>room||size_t(count)>sizeof(buffer))return failure(@"config_read_failed");
            [data appendBytes:buffer length:size_t(count)];if(data.length>TLinkHelperConfigMaxBytes)return failure(@"config_size_limit");
        }
        struct stat after,current;
        if(ops_.statFile(fd,&after)!=0||ops_.statPath(path,&current)!=0||!(identity==TLinkHelperConfigFileIdentity(after))||!(identity==TLinkHelperConfigFileIdentity(current)))return failure(@"config_changed_during_read");
        if(file.close()!=0)return failure(@"config_read_failed");
        snapshot_=decode(data);if(![snapshot_[@"configValid"] boolValue])++stats_.failures;
        memo_.publish(identity);return snapshot_;
    }
public:
    explicit TLinkHelperConfigSnapshot(NSString *path,TLinkHelperConfigOps ops={}):ops_(ops){path_=[path copy]?:@"";snapshot_=denied(@"");}
    TLinkHelperConfigSnapshot(const TLinkHelperConfigSnapshot &)=delete;TLinkHelperConfigSnapshot &operator=(const TLinkHelperConfigSnapshot &)=delete;
    NSDictionary *read(){
        std::lock_guard<std::mutex> guard(mutex_);
        NSDictionary *result=nil;
        @autoreleasepool{
            @try{try{result=load();}catch(...){result=failure(@"config_read_failed");}}
            @catch(__unused NSException *exception){result=failure(@"config_read_failed");}
        }
        return result;
    }
    TLinkHelperConfigStats stats(){std::lock_guard<std::mutex> guard(mutex_);return stats_;}
};
#endif
#endif
