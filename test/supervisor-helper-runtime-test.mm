#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include "../shared/TLinkVPNHelperChild.h"
#include "../shared/TLinkSupervisorHelper.h"
#import "../stream-app/app/StreamSupervisor.h"
#import "LegacySupervisor.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/stat.h>
#include <spawn.h>
#include <cassert>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include "../shared/TLinkBackgroundTaskRun.h"
extern char **environ;
#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif
using namespace TLinkVPNHelperChild;
static NSString *helperPath,*daemonPath;
static NSMutableArray *logs,*arguments;
enum Mode {Normal,Exit7,SpawnError,Held};
static Mode mode=Normal;
static bool attrFailure=false;
static unsigned fixtureTimeout=TimeoutMs,dupCalls=0,failDup=0,liveArgs=0,attrs=0,personaCalls=0;
static std::atomic<unsigned> spawns{0},daemonSpawns{0},scans{0},shutdowns{0},probes{0},queries{0},runningEvents{0},serviceSignals{0};
static pid_t lastChild=-1;
static int fixtureProcPath(int pid,void *buffer,uint32_t size){(void)pid;(void)buffer;(void)size;return 0;}
static int fixtureServiceKill(pid_t pid,int signal){(void)pid;(void)signal;++serviceSignals;errno=EPERM;return -1;}
struct HeldChild {
    std::atomic<bool> finished{false};std::atomic<unsigned> probes{0},signals{0};
} held;
static Ops fixtureOps(){
    Ops ops=posixOps();
    if(mode!=Held)return ops;
    ops.context=&held;
    ops.probe=[](void *p,int pid,int &status,int &error){
        (void)error;auto &child=*static_cast<HeldChild *>(p);assert(pid==42);++child.probes;
        if(child.finished){status=0;return Probe::Reaped;}return Probe::Running;
    };
    ops.signal=[](void *p,int pid,Signal kind){(void)kind;assert(pid==42);++static_cast<HeldChild *>(p)->signals;return EPERM;};
    return ops;
}
static char *fixtureStrdup(const char *text){++dupCalls;if(dupCalls==failDup)return nullptr;char *value=::strdup(text);if(value)++liveArgs;return value;}
static void fixtureFree(void *p){if(p){assert(liveArgs>0);--liveArgs;::free(p);}}
static int fixtureAttrInit(posix_spawnattr_t *attr){if(attrFailure)return ENOMEM;const int result=::posix_spawnattr_init(attr);if(!result)++attrs;return result;}
static int fixtureAttrDestroy(posix_spawnattr_t *attr){assert(attrs==1);--attrs;return ::posix_spawnattr_destroy(attr);}
static int fixturePersona(posix_spawnattr_t *attr,uid_t uid,uint32_t flags){(void)attr;assert(attrs==1&&uid==99&&flags==1);++personaCalls;return 0;}
static int fixturePersonaUID(posix_spawnattr_t *attr,uid_t uid){(void)attr;assert(attrs==1&&uid==0);++personaCalls;return 0;}
static int fixturePersonaGID(posix_spawnattr_t *attr,gid_t gid){(void)attr;assert(attrs==1&&gid==0);++personaCalls;return 0;}
static int fixtureSpawn(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,const posix_spawnattr_t *attr,char *const argv[],char *const envp[]){
    (void)path;(void)actions;(void)attr;(void)envp;
    if(argv[1]&&strcmp(argv[1],"--daemon")==0){++daemonSpawns;return EACCES;}
    ++spawns;NSMutableArray *args=[NSMutableArray array];for(unsigned n=0;argv[n];++n)[args addObject:[NSString stringWithUTF8String:argv[n]]];
    [arguments addObject:[args copy]];
    if(mode==SpawnError)return EACCES;
    if(mode==Held){*pid=42;lastChild=42;return 0;}
    char shell[]="/bin/sh",flag[]="-c",success[]="exit 0",failure[]="exit 7";char *childArgs[]={shell,flag,mode==Exit7?failure:success,nullptr};
    const int result=::posix_spawn(pid,shell,nullptr,nullptr,childArgs,environ);if(!result)lastChild=*pid;return result;
}
#define strdup fixtureStrdup
#define free fixtureFree
#define posix_spawn fixtureSpawn
#define posix_spawnattr_init fixtureAttrInit
#define posix_spawnattr_destroy fixtureAttrDestroy
#define posix_spawnattr_set_persona_np fixturePersona
#define posix_spawnattr_set_persona_uid_np fixturePersonaUID
#define posix_spawnattr_set_persona_gid_np fixturePersonaGID
#define proc_pidpath fixtureProcPath
#define kill fixtureServiceKill
#include "SupervisorUnderTest.inc"
#include "SupervisorLegacy.inc"
#undef strdup
#undef free
#undef posix_spawn
#undef posix_spawnattr_init
#undef posix_spawnattr_destroy
#undef posix_spawnattr_set_persona_np
#undef posix_spawnattr_set_persona_uid_np
#undef posix_spawnattr_set_persona_gid_np
#undef proc_pidpath
#undef kill
@interface SCStreamSupervisor (FixtureQueue)
- (dispatch_queue_t)fixtureQueue;
@end
@implementation SCStreamSupervisor (FixtureQueue)
- (dispatch_queue_t)fixtureQueue {return _queue;}
@end
@protocol PrivateMethods
- (int)runPrivhelperKillStreamdLocked;
- (int)runPrivhelperEnsureStreamdLocked:(BOOL)replace;
- (BOOL)preparePortForSpawnLocked;
- (void)spawnLocked;
@end
@interface SCStreamSupervisor (FixturePrivate)
- (int)runPrivhelperKillStreamdLocked;
- (int)runPrivhelperEnsureStreamdLocked:(BOOL)replace;
- (BOOL)preparePortForSpawnLocked;
- (void)spawnLocked;
@end
@interface SCLegacySupervisor (FixturePrivate)
- (int)runPrivhelperKillStreamdLocked;
- (int)runPrivhelperEnsureStreamdLocked:(BOOL)replace;
- (BOOL)preparePortForSpawnLocked;
- (void)spawnLocked;
@end
@interface CurrentFixture:SCStreamSupervisor<PrivateMethods>
@end
@interface LegacyFixture:SCLegacySupervisor<PrivateMethods>
@end
#define FIXTURE_METHODS \
- (NSString *)privhelperPath{return helperPath;} \
- (NSString *)streamdPath{return daemonPath;} \
- (void)emitLog:(NSString *)line{@synchronized(logs){[logs addObject:line];}} \
- (void)emitRunning:(BOOL)running pid:(pid_t)pid{(void)running;(void)pid;++runningEvents;} \
- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)timeout{(void)line;(void)timeout;++queries;return @"";} \
- (void)requestTaskServerShutdownLocked:(NSString *)reason{(void)reason;++shutdowns;} \
- (void)killStaleStreamdLocked{++scans;} \
- (BOOL)probeTaskServerAndUpdateLocked:(NSString *)reason{(void)reason;++probes;return NO;}
@implementation CurrentFixture
FIXTURE_METHODS
@end
@implementation LegacyFixture
FIXTURE_METHODS
@end
#undef FIXTURE_METHODS
@interface AdmissionFixture : CurrentFixture
@property BOOL providerRunning;
@property unsigned ensures;
@property unsigned fallbacks;
@property(nonatomic,strong) dispatch_semaphore_t started;
@property(nonatomic,strong) dispatch_semaphore_t releaseProvider;
@end
@interface LegacyAdmissionFixture : LegacyFixture
@property BOOL providerRunning;
@property unsigned ensures;
@property unsigned fallbacks;
@property(nonatomic,strong) dispatch_semaphore_t started;
@property(nonatomic,strong) dispatch_semaphore_t releaseProvider;
@end
#define ADMISSION_METHODS \
- (BOOL)ensureServiceLockedWithReplace:(BOOL)replace reason:(NSString *)reason { \
    assert(!replace&&[reason isEqualToString:@"ensure"]);++_ensures; \
    if(_started){dispatch_semaphore_signal(_started);assert(dispatch_semaphore_wait(_releaseProvider,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);} \
    return _providerRunning; \
} \
- (void)spawnLocked {++_fallbacks;} \
- (BOOL)probeTaskServerAndUpdateLocked:(NSString *)reason {(void)reason;++probes;return YES;}
@implementation AdmissionFixture
ADMISSION_METHODS
@end
@implementation LegacyAdmissionFixture
ADMISSION_METHODS
@end
#undef ADMISSION_METHODS
struct EnsureReply {
    std::atomic<unsigned> calls{0};
    BOOL running=NO;
    NSString *detail=nil;
};
typedef void (^EnsureCompletion)(BOOL, NSString *);
static EnsureCompletion completionFor(std::shared_ptr<EnsureReply> result){
    return ^(BOOL running,NSString *detail){assert([NSThread isMainThread]);result->running=running;result->detail=[detail copy];++result->calls;};
}
static void pump(){CFRunLoopRunInMode(kCFRunLoopDefaultMode,.01,false);}
static void awaitReply(std::shared_ptr<EnsureReply> result){
    const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;
    while(result->calls.load()==0&&CFAbsoluteTimeGetCurrent()<end)pump();
    assert(result->calls.load()==1);
}
static void waitSemaphore(dispatch_semaphore_t value){assert(dispatch_semaphore_wait(value,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
static void drainQueue(AdmissionFixture *supervisor){
    dispatch_semaphore_t drained=dispatch_semaphore_create(0);
    dispatch_async([supervisor fixtureQueue],^{dispatch_semaphore_signal(drained);});waitSemaphore(drained);
}
static void drain(){
    const uint64_t start=posixOps().now(nullptr);
    while((TLinkSupervisorHelper::busy()||pending()!=0)&&remaining(start,posixOps().now(nullptr),5000))pump();
    assert(!TLinkSupervisorHelper::busy()&&pending()==0&&attrs==0&&liveArgs==0);
}
static void awaitLog(NSString *part){
    const uint64_t start=posixOps().now(nullptr);bool found=false;
    while(!found&&remaining(start,posixOps().now(nullptr),5000)){
        @synchronized(logs){for(NSString *line in logs)if([line containsString:part]){found=true;break;}}
        if(!found)pump();
    }
    assert(found);
}
static int invoke(id<PrivateMethods> object,unsigned operation){return operation==0?[object runPrivhelperKillStreamdLocked]:[object runPrivhelperEnsureStreamdLocked:operation==2];}
static void reaped(){int status=0;errno=0;assert(waitpid(lastChild,&status,WNOHANG)==-1&&errno==ECHILD);}
static void normalCases(){
    for(unsigned operation=0;operation<3;++operation){
        for(unsigned kind=0;kind<3;++kind){
            mode=static_cast<Mode>(kind);dupCalls=0;personaCalls=0;
            const int expected=invoke([LegacyFixture new],operation);NSArray *expectedArgs=arguments.lastObject;
            assert(attrs==0&&liveArgs==0&&personaCalls==3);dupCalls=0;personaCalls=0;
            const int actual=invoke([CurrentFixture new],operation);
            assert(actual==expected&&[arguments.lastObject isEqual:expectedArgs]&&personaCalls==3);
            drain();if(mode!=SpawnError)reaped();
        }
        mode=Normal;
        for(failDup=1;failDup<=4;++failDup){
            if(operation==1&&failDup==4)continue;
            dupCalls=0;const int expected=invoke([LegacyFixture new],operation);
            dupCalls=0;const unsigned before=spawns;const int actual=invoke([CurrentFixture new],operation);
            assert(actual==expected&&spawns==before);drain();
        }
        failDup=0;attrFailure=true;const unsigned before=spawns;
        assert(invoke([CurrentFixture new],operation)==ENOMEM&&spawns==before);drain();attrFailure=false;
    }
}
static void pendingCases(){
    CurrentFixture *supervisor=[CurrentFixture new];mode=Held;fixtureTimeout=20;
    {
        Owner a,b,c,d;assert(a.ready()&&b.ready()&&c.ready()&&d.ready());
        const unsigned before=spawns;
        assert([supervisor runPrivhelperKillStreamdLocked]==-EBUSY&&spawns==before&&!TLinkSupervisorHelper::busy());
    }
    drain();
    held.finished=false;held.probes=0;held.signals=0;
    @synchronized(logs){[logs removeAllObjects];}
    scans=0;shutdowns=0;probes=0;queries=0;runningEvents=0;daemonSpawns=0;serviceSignals=0;
    assert([supervisor runPrivhelperEnsureStreamdLocked:YES]==-ETIMEDOUT);
    assert(TLinkSupervisorHelper::busy()&&pending()==1&&held.signals==2);
    const unsigned before=spawns;
    assert([[CurrentFixture new] runPrivhelperKillStreamdLocked]==-EBUSY&&spawns==before);
    __block BOOL done=NO;
    [supervisor ensureServiceWithCompletion:^(BOOL running,NSString *detail){assert(!running&&[detail isEqualToString:@"supervisor_helper_pending"]);done=YES;}];
    const uint64_t start=posixOps().now(nullptr);while(!done&&remaining(start,posixOps().now(nullptr),5000))pump();assert(done);
    [supervisor restart];awaitLog(@"restart requires retry");
    [supervisor stop];awaitLog(@"stop requires retry");
    [supervisor spawnLocked];
    assert(!supervisor.autoRespawn&&spawns==before&&daemonSpawns==0&&scans==0&&shutdowns==0&&probes==0&&queries==0&&runningEvents==0&&serviceSignals==0);
    held.finished=true;drain();assert(spawns==before); // No replay of rejected lifecycle operations.
    mode=Normal;fixtureTimeout=TimeoutMs;assert([supervisor runPrivhelperEnsureStreamdLocked:NO]==0);drain();reaped();
    mode=Held;fixtureTimeout=20;held.finished=false;held.signals=0;
    assert(![supervisor preparePortForSpawnLocked]);
    assert(TLinkSupervisorHelper::busy()&&daemonSpawns==0&&shutdowns==1&&scans==1&&queries==1);
    held.finished=true;drain();mode=Normal;fixtureTimeout=TimeoutMs;
}
static void admissionCases(){
    for(unsigned fallback=0;fallback<2;++fallback){
        @autoreleasepool{
            LegacyAdmissionFixture *old=[LegacyAdmissionFixture new];old.autoRespawn=NO;old.providerRunning=!fallback;
            auto expected=std::make_shared<EnsureReply>();[old ensureServiceWithCompletion:completionFor(expected)];awaitReply(expected);
            for(unsigned api=0;api<3;++api){
                AdmissionFixture *current=[AdmissionFixture new];current.autoRespawn=NO;current.providerRunning=!fallback;
                auto result=std::make_shared<EnsureReply>();auto permissions=std::make_shared<std::atomic<unsigned>>(0);
                if(api==0)[current ensureServiceWithCompletion:completionFor(result)];
                else if(api==1)[current ensureServiceWithStartPermission:nil completion:completionFor(result)];
                else [current ensureServiceWithStartPermission:^BOOL{++*permissions;return YES;} completion:completionFor(result)];
                assert(result->calls.load()==0);awaitReply(result);
                assert(result->running==expected->running&&[result->detail isEqualToString:expected->detail]);
                assert(current.ensures==old.ensures&&current.fallbacks==old.fallbacks&&current.autoRespawn&&permissions->load()==(api==2?1U:0U));
            }
        }
    }
    for(unsigned kind=0;kind<3;++kind){
        @autoreleasepool{
            AdmissionFixture *supervisor=[AdmissionFixture new];supervisor.autoRespawn=NO;auto result=std::make_shared<EnsureReply>();
            auto permissions=std::make_shared<std::atomic<unsigned>>(0);const unsigned before=spawns,oldProbes=probes,oldScans=scans,oldShutdowns=shutdowns;
            [supervisor ensureServiceWithStartPermission:^BOOL{
                ++*permissions;
                if(kind==1)[NSException raise:@"Admission" format:@"NS failure"];
                if(kind==2)throw std::runtime_error("admission");
                return NO;
            } completion:completionFor(result)];
            awaitReply(result);NSString *expected=kind?@"supervisor_ensure_admission_exception":@"supervisor_ensure_cancelled_before_start";
            assert(!result->running&&[result->detail isEqualToString:expected]&&permissions->load()==1);
            assert(!supervisor.autoRespawn&&supervisor.ensures==0&&supervisor.fallbacks==0&&spawns==before&&probes==oldProbes&&scans==oldScans&&shutdowns==oldShutdowns);
        }
    }
    // Queue residence: close the actual BGTask owner before the real supervisor queue can start.
    for(unsigned n=0;n<64;++n){
        @autoreleasepool{
            AdmissionFixture *supervisor=[AdmissionFixture new];supervisor.autoRespawn=NO;supervisor.providerRunning=YES;
            dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
            dispatch_async([supervisor fixtureQueue],^{dispatch_semaphore_signal(entered);waitSemaphore(release);});waitSemaphore(entered);
            auto deliveries=std::make_shared<std::atomic<unsigned>>(0);auto permissions=std::make_shared<std::atomic<unsigned>>(0);
            auto run=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;++*deliveries;});
            assert(run->beginRefresh()&&run->beginEnsure());auto result=std::make_shared<EnsureReply>();EnsureCompletion reply=completionFor(result);
            [supervisor ensureServiceWithStartPermission:^BOOL{++*permissions;assert(![NSThread isMainThread]);return run->beginSupervisor();}
                completion:^(BOOL running,NSString *detail){run->finish(running,detail,nil);reply(running,detail);}];
            assert(permissions->load()==0&&result->calls.load()==0);run->finish(NO,@"expired-while-queued",nil);
            dispatch_semaphore_signal(release);awaitReply(result);drainQueue(supervisor);
            assert(permissions->load()==1&&!result->running&&[result->detail isEqualToString:@"supervisor_ensure_cancelled_before_start"]);
            assert(deliveries->load()==1&&supervisor.ensures==0&&supervisor.fallbacks==0&&!supervisor.autoRespawn&&!run->beginSupervisor());
        }
    }
    @autoreleasepool{
        AdmissionFixture *supervisor=[AdmissionFixture new];supervisor.autoRespawn=NO;supervisor.providerRunning=YES;
        supervisor.started=dispatch_semaphore_create(0);supervisor.releaseProvider=dispatch_semaphore_create(0);
        auto deliveries=std::make_shared<std::atomic<unsigned>>(0);auto result=std::make_shared<EnsureReply>();EnsureCompletion reply=completionFor(result);
        auto run=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;++*deliveries;});
        assert(run->beginRefresh()&&run->beginEnsure());
        [supervisor ensureServiceWithStartPermission:^BOOL{return run->beginSupervisor();} completion:^(BOOL running,NSString *detail){run->finish(running,detail,nil);reply(running,detail);}];
        waitSemaphore(supervisor.started);run->finish(NO,@"expired-after-start",nil);dispatch_semaphore_signal(supervisor.releaseProvider);awaitReply(result);
        assert(result->running&&supervisor.ensures==1&&supervisor.autoRespawn&&deliveries->load()==1&&!run->beginSupervisor());
    }
    @autoreleasepool{
        AdmissionFixture *supervisor=[AdmissionFixture new];supervisor.autoRespawn=NO;
        [supervisor ensureServiceWithStartPermission:^BOOL{return NO;} completion:nil];drainQueue(supervisor);
        assert(supervisor.ensures==0&&!supervisor.autoRespawn);
    }
    for(unsigned n=0;n<200;++n){
        @autoreleasepool{
            auto starts=std::make_shared<std::atomic<unsigned>>(0);auto deliveries=std::make_shared<std::atomic<unsigned>>(0);
            auto run=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;++*deliveries;});
            assert(!run->beginSupervisor()&&run->beginRefresh()&&!run->beginSupervisor()&&run->beginEnsure());
            std::thread start([run,starts]{if(run->beginSupervisor())++*starts;});
            std::thread finish([run]{@autoreleasepool{run->finish(NO,@"expired",nil);}});start.join();finish.join();
            assert(starts->load()<=1&&deliveries->load()==1&&!run->beginSupervisor());
        }
    }
}
int main(){@autoreleasepool{
    logs=[NSMutableArray array];arguments=[NSMutableArray array];
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-supervisor-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nullptr]);
    helperPath=[root stringByAppendingPathComponent:@"privhelper"];daemonPath=[root stringByAppendingPathComponent:@"streamd"];
    for(NSString *path in @[helperPath,daemonPath]){assert([@"#!/bin/sh\nexit 0\n" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);assert(chmod(path.fileSystemRepresentation,0700)==0);}
    puts("Supervisor helper Foundation: complete current/frozen supervisor, real disposable children and controlled daemon/persona effects");
    normalCases();pendingCases();admissionCases();
    for(unsigned n=0;n<64;++n){dupCalls=0;assert(invoke([CurrentFixture new],n%3)==0);drain();reaped();}
    assert([[NSFileManager defaultManager] removeItemAtPath:root error:nullptr]);
    puts("Supervisor helper Foundation passed: frozen argv/persona/exit/fault parity, spawn attributes, bounded unreaped wait, retained process lane, busy lifecycle/fallback fences, legacy/nil/allowed owner-start parity, NS/C++ permission refusal, 64 expired real-queue requests, admitted-work boundary, 200 start/finish races, nil completion, late retirement and 64 balanced helper cycles. No real service or privileged helper controlled; active cancellation/device qualification pending.");
}return 0;}
