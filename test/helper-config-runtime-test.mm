#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include "../shared/TLinkHelperConfigSnapshot.h"
#import "../pccontrol/jsruntime/TLinkJSNativeRequest.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <set>
#include <thread>
#include <vector>
#include <stdexcept>
static NSString *kTLinkautoJSHelperConfigPath;
#include "HelperConfigRuntimeUnderTest.inc"
#include "fixtures/helper-config-legacy-v1.inc"
static std::mutex fdMutex;static std::set<int> liveFDs;
static bool failStat=false,failOpen=false,failFstat=false,failRead=false,failClose=false;
static int readThrows=0,interruptions=0;static size_t chunkBytes=4096;
static bool replaceOnRead=false,changeOnRead=false;
static std::atomic<unsigned> opens{0},reads{0},closes{0};
static NSData *replacement;
static int fixtureStat(const char *path,struct stat *value){if(failStat){errno=ENOENT;return -1;}return ::stat(path,value);}
static int fixtureOpen(const char *path){++opens;if(failOpen){errno=EACCES;return -1;}const int fd=TLinkHelperConfigOpen(path);if(fd>=0){std::lock_guard<std::mutex> guard(fdMutex);assert(liveFDs.insert(fd).second);}return fd;}
static int fixtureFstat(int fd,struct stat *value){if(failFstat){errno=EIO;return -1;}return ::fstat(fd,value);}
static ssize_t fixtureRead(int fd,void *bytes,size_t length){
    ++reads;if(readThrows==1)[NSException raise:@"FixtureConfig" format:@"read"];
    if(readThrows==2)throw std::runtime_error("read");
    if(interruptions>0){--interruptions;errno=EINTR;return -1;}
    if(failRead){errno=EIO;return -1;}
    if(replaceOnRead||changeOnRead){bool atomic=replaceOnRead;replaceOnRead=false;changeOnRead=false;assert([replacement writeToFile:kTLinkautoJSHelperConfigPath atomically:atomic]);}
    return ::read(fd,bytes,length<chunkBytes?length:chunkBytes);
}
static int fixtureClose(int fd){++closes;{std::lock_guard<std::mutex> guard(fdMutex);assert(liveFDs.erase(fd)==1);}int rc=::close(fd);if(failClose){errno=EIO;return -1;}return rc;}
static TLinkHelperConfigOps ops(){TLinkHelperConfigOps io;io.statPath=fixtureStat;io.openFile=fixtureOpen;io.statFile=fixtureFstat;io.readFile=fixtureRead;io.closeFile=fixtureClose;return io;}
static void resetFaults(){failStat=failOpen=failFstat=failRead=failClose=false;readThrows=interruptions=0;chunkBytes=4096;replaceOnRead=changeOnRead=false;}
static NSData *bytes(NSString *text){return [text dataUsingEncoding:NSUTF8StringEncoding];}
static void writeConfig(NSData *data,bool atomic=true){assert([data writeToFile:kTLinkautoJSHelperConfigPath atomically:atomic]);}
static NSData *flags(unsigned value){return bytes([NSString stringWithFormat:@"{\"javascript_helper_runtime_enabled\":%u,\"javascript_helper_runtime_default\":%u,\"javascript_helper_allow_admin_rpc\":%u}",value,value,value]);}
static void denied(NSDictionary *value){assert(![value[@"enabled"] boolValue]&&![value[@"runtimeDefault"] boolValue]&&![value[@"allowAdminRPC"] boolValue]&&![value[@"configValid"] boolValue]);}
static void noFDs(){std::lock_guard<std::mutex> guard(fdMutex);assert(liveFDs.empty());}
static void normalizerCases(){
    NSArray *values=@[@0,@1,@(false),@(true),@"",@"yes",@"false",@"1",[NSNull null],@[],@{}];
    TLinkHelperConfigSnapshot config(kTLinkautoJSHelperConfigPath,ops());
    for(unsigned n=0;n<121;++n){
        @autoreleasepool{
            NSDictionary *object=@{@"javascript_helper_runtime_enabled":values[n%11],@"enable_js_helper_execution":@(true),@"javascript_helper_runtime_default":values[(n/11)%11],@"javascript_helper_allow_admin_rpc":values[(n/3)%11]};
            NSData *data=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];assert(data);writeConfig(data);
            NSDictionary *expected=legacyHelperConfigSnapshot(kTLinkautoJSHelperConfigPath),*actual=config.read();assert([actual isEqual:expected]);
            assert(![actual isKindOfClass:[NSMutableDictionary class]]);
            NSDictionary *policy=TLinkautoJSHelperRPCPolicy(TLinkJSNativeMethodRunShell,@[],actual);assert([policy[@"allowed"] boolValue]==[actual[@"allowAdminRPC"] boolValue]);
            assert([TLinkautoJSHelperRPCPolicy(TLinkJSNativeMethodTap,@[],actual)[@"allowed"] boolValue]);
        }
    }
    for(NSData *data in @[bytes(@"{}"),bytes(@"{\"enable_js_helper_execution\":true}"),bytes(@"[]"),bytes(@"invalid"),[NSData data]]){
        writeConfig(data);assert([config.read() isEqual:legacyHelperConfigSnapshot(kTLinkautoJSHelperConfigPath)]);
        auto before=config.stats();config.read();auto after=config.stats();assert(after.hits==before.hits+1&&after.parses==before.parses);
    }
    noFDs();
}
static void cacheCases(){
    writeConfig(flags(1));TLinkHelperConfigSnapshot cache(kTLinkautoJSHelperConfigPath,ops());NSDictionary *held=cache.read();assert([held[@"allowAdminRPC"] boolValue]);
    const unsigned initialReads=reads.load(),initialOpens=opens.load();
    for(unsigned n=0;n<10000;++n)assert([cache.read()[@"enabled"] boolValue]);
    auto stats=cache.stats();assert(stats.parses==1&&stats.reloads==1&&stats.hits==10000&&reads==initialReads&&opens==initialOpens);
    writeConfig(flags(0));NSDictionary *current=cache.read();assert([current[@"configValid"] boolValue]&&![current[@"allowAdminRPC"] boolValue]&&[held[@"allowAdminRPC"] boolValue]);
    // Same inode/size/mtime: ctime still invalidates after an in-place write.
    struct stat original;assert(::stat(kTLinkautoJSHelperConfigPath.fileSystemRepresentation,&original)==0);
    writeConfig(flags(1),false);struct timespec times[2]={original.st_atimespec,original.st_mtimespec};
    const int fd=::open(kTLinkautoJSHelperConfigPath.fileSystemRepresentation,O_WRONLY);assert(fd>=0&&futimens(fd,times)==0);assert(::close(fd)==0);
    assert([cache.read()[@"allowAdminRPC"] boolValue]);
    auto before=cache.stats();struct stat permissions;assert(::stat(kTLinkautoJSHelperConfigPath.fileSystemRepresentation,&permissions)==0);const mode_t newMode=(permissions.st_mode&0777)==0600?0640:0600;assert(chmod(kTLinkautoJSHelperConfigPath.fileSystemRepresentation,newMode)==0);assert([cache.read()[@"configValid"] boolValue]);assert(cache.stats().reloads==before.reloads+1);
    assert(unlink(kTLinkautoJSHelperConfigPath.fileSystemRepresentation)==0);denied(cache.read());writeConfig(flags(0));assert([cache.read()[@"configValid"] boolValue]&&![cache.read()[@"enabled"] boolValue]);
    // A static production adapter sees the same file changes; its policy remains unchanged.
    writeConfig(flags(1));assert([TLinkautoJSHelperConfigSnapshot()[@"allowAdminRPC"] boolValue]);writeConfig(flags(0));assert(![TLinkautoJSHelperConfigSnapshot()[@"allowAdminRPC"] boolValue]);
    NSDictionary *retained=nil;{TLinkHelperConfigSnapshot temporary(kTLinkautoJSHelperConfigPath);@autoreleasepool{retained=temporary.read();}}
    assert([retained[@"configValid"] boolValue]);noFDs();
}
static void faultCases(){
    for(unsigned kind=0;kind<7;++kind){
        resetFaults();writeConfig(flags(1));TLinkHelperConfigSnapshot cache(kTLinkautoJSHelperConfigPath,ops());
        if(kind==0)failStat=true;if(kind==1)failOpen=true;if(kind==2)failFstat=true;if(kind==3)failRead=true;if(kind==4)failClose=true;if(kind==5)readThrows=1;if(kind==6)readThrows=2;
        denied(cache.read());noFDs();resetFaults();assert([cache.read()[@"allowAdminRPC"] boolValue]);noFDs();
    }
    resetFaults();writeConfig(flags(1));TLinkHelperConfigSnapshot partial(kTLinkautoJSHelperConfigPath,ops());interruptions=3;chunkBytes=7;assert([partial.read()[@"allowAdminRPC"] boolValue]);noFDs();
    resetFaults();TLinkHelperConfigSnapshot interrupted(kTLinkautoJSHelperConfigPath,ops());interruptions=33;denied(interrupted.read());noFDs();resetFaults();assert([interrupted.read()[@"allowAdminRPC"] boolValue]);
    for(bool atomic:{false,true}){resetFaults();writeConfig(flags(1));replacement=flags(0);replaceOnRead=atomic;changeOnRead=!atomic;TLinkHelperConfigSnapshot raced(kTLinkautoJSHelperConfigPath,ops());denied(raced.read());noFDs();assert([raced.read()[@"configValid"] boolValue]&&![raced.read()[@"allowAdminRPC"] boolValue]);}
    resetFaults();
}
static void boundsAndConcurrency(){
    NSMutableData *large=[NSMutableData dataWithLength:TLinkHelperConfigMaxBytes+1];writeConfig(large);TLinkHelperConfigSnapshot cache(kTLinkautoJSHelperConfigPath,ops());const unsigned initialOpens=opens.load();denied(cache.read());assert(opens==initialOpens);
    std::vector<char> padded(TLinkHelperConfigMaxBytes,' ');padded[0]='{';padded[1]='}';writeConfig([NSData dataWithBytes:padded.data() length:padded.size()]);assert([cache.read()[@"configValid"] boolValue]);
    assert(unlink(kTLinkautoJSHelperConfigPath.fileSystemRepresentation)==0);assert(mkfifo(kTLinkautoJSHelperConfigPath.fileSystemRepresentation,0600)==0);denied(cache.read());assert(unlink(kTLinkautoJSHelperConfigPath.fileSystemRepresentation)==0);
    writeConfig(flags(1));TLinkHelperConfigSnapshot shared(kTLinkautoJSHelperConfigPath,ops());std::vector<std::thread> workers;
    for(unsigned t=0;t<8;++t)workers.emplace_back([&]{@autoreleasepool{for(unsigned n=0;n<1000;++n)assert([shared.read()[@"allowAdminRPC"] boolValue]);}});
    for(auto &thread:workers)thread.join();auto stats=shared.stats();assert(stats.checks==8000&&stats.parses==1&&stats.hits==7999);noFDs();
}
int main(int argc,char **argv){assert(argc==2);@autoreleasepool{
    kTLinkautoJSHelperConfigPath=[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"config.json"];
    normalizerCases();cacheCases();faultCases();boundsAndConcurrency();assert(opens.load()>=closes.load());noFDs();
    puts("Helper config Foundation passed: frozen normalization/policy, 10k cache hits without open/read/parse, identity/ctime/replacement invalidation, immutable readers, read/race/exception recovery, bounded files and 8k concurrent reads with zero live fixture FDs.");
}return 0;}
