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
static void pump(){CFRunLoopRunInMode(kCFRunLoopDefaultMode,.01,false);}
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
int main(){@autoreleasepool{
    logs=[NSMutableArray array];arguments=[NSMutableArray array];
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-supervisor-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nullptr]);
    helperPath=[root stringByAppendingPathComponent:@"privhelper"];daemonPath=[root stringByAppendingPathComponent:@"streamd"];
    for(NSString *path in @[helperPath,daemonPath]){assert([@"#!/bin/sh\nexit 0\n" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nullptr]);assert(chmod(path.fileSystemRepresentation,0700)==0);}
    puts("Supervisor helper Foundation: complete current/frozen supervisor, real disposable children and controlled daemon/persona effects");
    normalCases();pendingCases();
    for(unsigned n=0;n<64;++n){dupCalls=0;assert(invoke([CurrentFixture new],n%3)==0);drain();reaped();}
    assert([[NSFileManager defaultManager] removeItemAtPath:root error:nullptr]);
    puts("Supervisor helper Foundation passed: frozen argv/persona/exit/fault parity, spawn attributes, bounded unreaped wait, retained process lane, queue/completion progress, busy ensure/restart/stop/spawn, post-cleanup fallback refusal, late retirement and 64 balanced helper cycles. No real service or privileged helper controlled; device qualification pending.");
}return 0;}
