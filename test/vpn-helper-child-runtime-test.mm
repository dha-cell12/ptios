#import <Foundation/Foundation.h>
#include "../shared/TLinkVPNHelperChild.h"
#include <cassert>
#include <cstdio>
#include <fcntl.h>
#include <spawn.h>
#include <poll.h>
#include <sys/stat.h>
#include <stdexcept>
extern char **environ;
#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif
using namespace TLinkVPNHelperChild;
static NSString *fixtureDirectory;
static unsigned fixtureTimeout=TimeoutMs;
static unsigned mode=0,spawns=0;
static pid_t lastChild=-1;
static uid_t fixtureUID(){return 501;}
static gid_t fixtureGID(){return 501;}
static int fixturePersona(posix_spawnattr_t *attr,uid_t uid,uint32_t flags){(void)attr;(void)uid;(void)flags;return 0;}
static int fixturePersonaUID(posix_spawnattr_t *attr,uid_t uid){(void)attr;(void)uid;return 0;}
static int fixturePersonaGID(posix_spawnattr_t *attr,gid_t gid){(void)attr;(void)gid;return 0;}
static int fixtureLstat(const char *path,struct stat *value){
    const int result=::lstat(path,value);
    if(result==0)value->st_uid=501; // Exercise actual modes/links/lengths under a controlled identity.
    return result;
}
static int fixtureSpawn(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,
    const posix_spawnattr_t *attr,char *const argv[],char *const envp[]){
    (void)path;(void)actions;(void)attr;(void)envp;++spawns;
    NSString *requestPath=[NSString stringWithUTF8String:argv[2]];
    NSDictionary *request=[NSDictionary dictionaryWithContentsOfFile:requestPath];
    assert([request[@"version"] integerValue]==2&&[request[@"password"] isEqualToString:@"fixture-secret"]);
    if(mode!=2){
        NSDictionary *result=@{@"ok":@1,@"code":@"fixture_ok",
            @"request_id":mode==3?@"wrong":request[@"request_id"],@"version":mode==4?@1:@2};
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:result format:NSPropertyListBinaryFormat_v1_0 options:0 error:nullptr];
        NSString *resultPath=[requestPath stringByAppendingString:@".result"];
        assert([data writeToFile:resultPath atomically:NO]);
        assert(chmod(resultPath.fileSystemRepresentation,mode==5?0644:0600)==0);
    }
    char executable[]="/bin/sh",flag[]="-c",success[]="exit 0",failure[]="exit 7",hold[]="exec /bin/sleep 10";
    char *childArgs[]={executable,flag,mode==6?hold:(mode==1?failure:success),nullptr};
    const int result=::posix_spawn(pid,executable,nullptr,nullptr,childArgs,environ);
    if(result==0)lastChild=*pid;
    return result;
}
#define geteuid fixtureUID
#define getegid fixtureGID
#define lstat fixtureLstat
#define posix_spawn fixtureSpawn
#define posix_spawnattr_set_persona_np fixturePersona
#define posix_spawnattr_set_persona_uid_np fixturePersonaUID
#define posix_spawnattr_set_persona_gid_np fixturePersonaGID
namespace Current {
#include "VPNPrivateRequestUnderTest.inc"
}
namespace Legacy {
#include "VPNPrivateRequestLegacy.inc"
}
#undef geteuid
#undef getegid
#undef lstat
#undef posix_spawn
#undef posix_spawnattr_set_persona_np
#undef posix_spawnattr_set_persona_uid_np
#undef posix_spawnattr_set_persona_gid_np
static void drain(){
    const auto ops=posixOps();const uint64_t start=ops.now(nullptr);
    while(pending()!=0&&remaining(start,ops.now(nullptr),5000))ops.sleep(nullptr,10);
    assert(pending()==0);
}
static void assertEmpty(){
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:fixtureDirectory error:nullptr];
    assert(files&&files.count==0);
}
static void assertReaped(pid_t pid){int status=0;errno=0;assert(::waitpid(pid,&status,WNOHANG)==-1&&errno==ECHILD);}
static void transportCases(NSString *helper){
    NSDictionary *configuration=@{@"profile_type":@"IKEv2",@"server":@"fixture.invalid",@"username":@"fixture",@"password":@"fixture-secret"};
    for(mode=0;mode<6;++mode){
        NSDictionary *expected=Legacy::TLinkVPNRunPrivateConfigurationHelper(helper,configuration);
        const pid_t expectedPID=lastChild;
        assertEmpty();
        NSDictionary *actual=Current::TLinkVPNRunPrivateConfigurationHelper(helper,configuration);
        if(expected[@"helper_wait"]){
            assert([expected[@"helper_wait"] intValue]==expectedPID&&[actual[@"helper_wait"] intValue]==lastChild);
            NSMutableDictionary *expectedFields=[expected mutableCopy],*actualFields=[actual mutableCopy];
            [expectedFields removeObjectForKey:@"helper_wait"];[actualFields removeObjectForKey:@"helper_wait"];
            assert([actualFields isEqual:expectedFields]);
        }else{
            assert([actual isEqual:expected]);
        }
        assertReaped(lastChild);drain();assertEmpty();
    }
    mode=6;fixtureTimeout=20;
    NSDictionary *timeout=Current::TLinkVPNRunPrivateConfigurationHelper(helper,configuration);
    assert(![timeout[@"ok"] boolValue]&&[timeout[@"code"] isEqualToString:@"vpn_private_helper_timeout"]);
    drain();assertReaped(lastChild);assertEmpty();fixtureTimeout=TimeoutMs;
    {
        Owner a,b,c,d;assert(a.ready()&&b.ready()&&c.ready()&&d.ready());
        const unsigned before=spawns;
        NSDictionary *busy=Current::TLinkVPNRunPrivateConfigurationHelper(helper,configuration);
        assert([busy[@"code"] isEqualToString:@"vpn_private_helper_busy"]&&spawns==before);assertEmpty();
    }
    drain();
}
static pid_t spawnSleeping(){
    char path[]="/bin/sleep",duration[]="10";char *args[]={path,duration,nullptr};pid_t pid=-1;
    assert(::posix_spawn(&pid,path,nullptr,nullptr,args,environ)==0&&pid>0);return pid;
}
static void ownerCases(){
    // Child-side calls after fork are restricted to async-signal-safe POSIX APIs.
    pid_t ignoredTermPID=-1;
    {
        int pipeFDs[2];assert(pipe(pipeFDs)==0);Owner owner;assert(owner.ready());
        const pid_t pid=fork();
        if(pid==0){
            close(pipeFDs[0]);struct sigaction ignore={};ignore.sa_handler=SIG_IGN;sigemptyset(&ignore.sa_mask);
            if(sigaction(SIGTERM,&ignore,nullptr)!=0)_exit(90);
            const char ready='R';if(write(pipeFDs[1],&ready,1)!=1)_exit(91);
            close(pipeFDs[1]);for(;;)pause();
        }
        assert(pid>0);ignoredTermPID=pid;owner.adopted(pid);close(pipeFDs[1]);
        struct pollfd readable={pipeFDs[0],POLLIN,0};int polled;
        do{polled=poll(&readable,1,3000);}while(polled<0&&errno==EINTR);
        char ready=0;assert(polled==1&&read(pipeFDs[0],&ready,1)==1&&ready=='R');close(pipeFDs[0]);
        Result result=owner.wait(20,20);
        assert(result.reason==Reason::Timeout&&result.termAttempted&&result.killAttempted);
        if(result.retired)assert(WIFSIGNALED(result.status)&&WTERMSIG(result.status)==SIGKILL);
    }
    drain();assertReaped(ignoredTermPID);
    for(unsigned fault=0;fault<2;++fault){
        pid_t pid=-1;bool caught=false;
        try{
            @try{
                Owner owner;assert(owner.ready());pid=spawnSleeping();owner.adopted(pid);
                if(fault==0)throw std::runtime_error("fixture");
                [NSException raise:@"FixtureChild" format:@"unwind"];
            }@catch(NSException *exception){(void)exception;caught=true;}
        }catch(...){caught=true;}
        assert(caught);drain();assertReaped(pid);
    }
    // ECHILD retires ownership without signalling a PID that another owner already reaped.
    {
        Owner owner;assert(owner.ready());const pid_t pid=spawnSleeping();owner.adopted(pid);
        assert(kill(pid,SIGKILL)==0);int status=0;pid_t waited;
        do{waited=::waitpid(pid,&status,0);}while(waited<0&&errno==EINTR);
        assert(waited==pid);Result result=owner.wait();assert(result.reason==Reason::WaitFailed&&result.retired);
    }
    drain();
    NSString *request=[fixtureDirectory stringByAppendingPathComponent:@"foreign"],*result=[request stringByAppendingString:@".result"];
    assert([@"foreign" writeToFile:request atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);
    assert([@"foreign" writeToFile:result atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);
    {Owner owner;owner.paths(request.fileSystemRepresentation,result.fileSystemRepresentation);}
    drain();assert([[NSFileManager defaultManager] fileExistsAtPath:request]&&[[NSFileManager defaultManager] fileExistsAtPath:result]);
    assert(unlink(request.fileSystemRepresentation)==0&&unlink(result.fileSystemRepresentation)==0);
}
struct HeldChild {
    std::atomic<bool> finished{false};std::atomic<unsigned> probes{0},kills{0};
    Ops ops(){Ops ops=posixOps();ops.context=this;
        ops.probe=[](void *p,int pid,int &status,int &error){
            HeldChild &child=*static_cast<HeldChild *>(p);assert(pid==42);++child.probes;(void)error;
            if(child.finished.load()){status=0;return Probe::Reaped;}return Probe::Running;
        };
        ops.signal=[](void *p,int pid,Signal kind){assert(pid==42&&kind==Signal::Kill);++static_cast<HeldChild *>(p)->kills;return EPERM;};
        return ops;
    }
};
static void deferredCases(){
    HeldChild held;
    NSString *request=[fixtureDirectory stringByAppendingPathComponent:@"owned"],*result=[request stringByAppendingString:@".result"];
    {
        Owner owner(held.ops());assert(owner.ready());owner.paths(request.fileSystemRepresentation,result.fileSystemRepresentation);
        assert([@"credential" writeToFile:request atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);owner.createdRequest();owner.adopted(42);
        Result timeout=owner.wait(0,0);assert(timeout.reason==Reason::Timeout&&!timeout.retired);
    }
    assert(pending()==1&&held.kills==1&&![[NSFileManager defaultManager] fileExistsAtPath:request]);
    {
        Owner b,c,d,excess;assert(b.admitted()&&c.admitted()&&d.admitted()&&!excess.admitted());
    }
    const uint64_t start=posixOps().now(nullptr);
    while((held.probes<3||pending()!=1)&&remaining(start,posixOps().now(nullptr),3000))posixOps().sleep(nullptr,10);
    assert(held.probes>=3&&pending()==1&&held.kills==1);
    assert([@"late" writeToFile:result atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);
    held.finished=true;drain();assertEmpty(); // Last cleanup happens after late result publication, without replay.
}
int main(){@autoreleasepool{
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-vpn-helper-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    fixtureDirectory=[root stringByAppendingPathComponent:@"requests"];
    NSString *bundle=[root stringByAppendingPathComponent:@"StreamControl.app"],*helper=[bundle stringByAppendingPathComponent:@"privhelper"];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:bundle withIntermediateDirectories:YES attributes:nil error:nullptr]);
    assert([@"#!/bin/sh\nexit 0\n" writeToFile:helper atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);assert(chmod(helper.fileSystemRepresentation,0700)==0);
    puts("VPN helper child Foundation: actual/frozen request transport, POSIX child waits, unwind and held deferred reaper");
    transportCases(helper);ownerCases();deferredCases();
    for(unsigned n=0;n<64;++n){@autoreleasepool{Owner owner;assert(owner.ready());owner.adopted(spawnSleeping());}drain();}
    assertEmpty();assert([[NSFileManager defaultManager] removeItemAtPath:root error:nullptr]);
    puts("VPN helper child Foundation passed: frozen healthy/result faults, real timeout/TERM/reap, NS/C++ unwind, ECHILD, foreign paths, four-child admission, retained deferred ownership, late file cleanup and 64 balanced cycles. Identity/persona/private effects are controlled; device qualification pending.");
}return 0;}
