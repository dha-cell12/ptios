#import <Foundation/Foundation.h>
#include "../shared/TLinkVPNHelperChild.h"
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <thread>
#include <stdexcept>
extern char **environ;
using namespace TLinkVPNHelperChild;
enum class Mode {Success,Exit7,Signalled,SpawnError,InvalidPid,Hang,Held,Missing,Interrupted};
static Mode mode=Mode::Success;
static NSString *helperPath=@"/fixture/privhelper";
static NSArray *lastArgs;
static unsigned spawns=0,allocCalls=0,failAllocation=0;
static unsigned fixtureWaitLimit=3000;
static std::set<void *> allocations;
static std::atomic<bool> heldDone{false},interrupted{false};
static std::atomic<unsigned> heldSignals{0};
static pid_t childPid=-1;
@interface TLinkScriptSession:NSObject
@property BOOL stopRequested;
@end
@implementation TLinkScriptSession
@end
static NSString *TLinkScriptRunTask(int taskType,NSString *body);
#include "StreamdScriptHelperScope.inc"
static TLinkScriptSession *sessionToStop;
static bool stopDuringPath=false,stopDuringAllocation=false,stopAfterSpawn=false,stopDuringProbe=false;
static unsigned taskFault=0;
static NSString *TLinkPrivhelperPath(){if(stopDuringPath)sessionToStop.stopRequested=YES;return helperPath;}
static void *fixtureCalloc(size_t count,size_t size){++allocCalls;if(allocCalls==failAllocation)return nullptr;void *p=::calloc(count,size);if(p)assert(allocations.insert(p).second);return p;}
static char *fixtureDup(const char *s){++allocCalls;if(stopDuringAllocation)sessionToStop.stopRequested=YES;if(allocCalls==failAllocation)return nullptr;char *p=::strdup(s);if(p)assert(allocations.insert(p).second);return p;}
static void fixtureFree(void *p){if(p){assert(allocations.erase(p)==1);::free(p);}}
static int fixtureSpawn(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,const posix_spawnattr_t *attrs,char *const argv[],char *const envp[]){
    assert(std::strcmp(path,"/fixture/privhelper")==0&&!actions&&!attrs&&envp==environ);++spawns;
    NSMutableArray *args=[NSMutableArray array];for(size_t n=0;argv[n];++n)[args addObject:[NSString stringWithUTF8String:argv[n]]];lastArgs=[args copy];
    if(mode==Mode::SpawnError)return EACCES;
    if(mode==Mode::InvalidPid){*pid=0;return 0;}
    if(mode==Mode::Held||mode==Mode::Missing){*pid=42;if(stopAfterSpawn)sessionToStop.stopRequested=YES;return 0;}
    const pid_t created=::fork();assert(created>=0);
    if(created==0){
        if(mode==Mode::Hang){for(;;)::pause();}
        if(mode==Mode::Signalled){::kill(::getpid(),SIGTERM);::_exit(1);}
        ::_exit(mode==Mode::Exit7?7:0);
    }
    childPid=created;*pid=created;if(stopAfterSpawn)sessionToStop.stopRequested=YES;return 0;
}
static Ops fixtureOps(){
    Ops ops=posixOps();
    if(stopAfterSpawn||stopDuringProbe){
        ops.probe=[](void *,int pid,int &status,int &error){
            if(stopDuringProbe)sessionToStop.stopRequested=YES;
            const auto base=posixOps();return base.probe(base.context,pid,status,error);
        };
    }
    if(mode==Mode::Held){
        ops.probe=[](void *,int pid,int &status,int &error){(void)error;assert(pid==42);if(heldDone){status=0;return Probe::Reaped;}return Probe::Running;};
        ops.signal=[](void *,int pid,Signal){assert(pid==42);++heldSignals;return EPERM;};
    }else if(mode==Mode::Missing){
        ops.probe=[](void *,int pid,int &,int &error){assert(pid==42);error=ECHILD;return Probe::Missing;};
    }else if(mode==Mode::Interrupted){
        ops.probe=[](void *,int pid,int &status,int &error){
            if(!interrupted.exchange(true)){error=EINTR;return Probe::Retry;}
            const auto base=posixOps();return base.probe(base.context,pid,status,error);
        };
    }
    return ops;
}
#define calloc fixtureCalloc
#define strdup fixtureDup
#define free fixtureFree
#define posix_spawn fixtureSpawn
#include "StreamdHelperUnderTest.inc"
#include "StreamdHelperLegacy.inc"
#undef posix_spawn
#undef free
#undef strdup
#undef calloc
static NSString *TLinkScriptRunTask(int taskType,NSString *body){
    (void)body;
    if(taskFault==1)[NSException raise:@"ScriptHelperFixture" format:@"task"];
    if(taskFault==2)throw std::runtime_error("task");
    if(taskType==17||taskType==30){assert(!sTLinkScriptHelperStop);return @"non-helper";}
    if(taskType==74)sessionToStop.stopRequested=YES;
    return [NSString stringWithFormat:@"%d",TLinkRunPrivhelper(@[@"--fixture"],3000)];
}
static void awaitEmpty(){const uint64_t until=posixOps().now(nullptr)+5000;while(pending().load()){assert(posixOps().now(nullptr)<until);std::this_thread::sleep_for(std::chrono::milliseconds(10));}}
static void reset(){awaitEmpty();assert(allocations.empty());mode=Mode::Success;helperPath=@"/fixture/privhelper";lastArgs=nil;spawns=allocCalls=failAllocation=0;fixtureWaitLimit=3000;heldDone=false;heldSignals=0;interrupted=false;childPid=-1;sessionToStop=nil;stopDuringPath=stopDuringAllocation=stopAfterSpawn=stopDuringProbe=false;taskFault=0;assert(!sTLinkScriptHelperStop);}
static void parityCases(){
    NSArray *args=@[@"--open-bundle",@"com.fixture.Ứng dụng"];
    for(Mode value:{Mode::Success,Mode::Exit7,Mode::Signalled,Mode::SpawnError,Mode::InvalidPid}){
        reset();mode=value;const int expected=LegacyRunPrivhelper(args,1000);NSArray *oldArgs=lastArgs;
        reset();mode=value;const int actual=TLinkRunPrivhelper(args,1000);assert(actual==expected&&[lastArgs isEqual:oldArgs]&&allocations.empty());awaitEmpty();
    }
    reset();assert(TLinkRunPrivhelper(@[],100)==-100&&spawns==0);helperPath=nil;assert(TLinkRunPrivhelper(args,100)==-101&&spawns==0);
    for(unsigned allocation=1;allocation<=4;++allocation){reset();failAllocation=allocation;assert(TLinkRunPrivhelper(args,100)==-102&&spawns==0&&allocations.empty());awaitEmpty();}
}
static void boundedCases(){
    reset();mode=Mode::Hang;
    assert(TLinkRunPrivhelper(@[@"--fixture"],100)==-106);awaitEmpty();
    int status=0;errno=0;assert(::waitpid(childPid,&status,WNOHANG)==-1&&errno==ECHILD);
    reset();mode=Mode::Missing;assert(TLinkRunPrivhelper(@[@"--fixture"],100)==-105);awaitEmpty();
    reset();mode=Mode::Interrupted;assert(TLinkRunPrivhelper(@[@"--fixture"],3000)==0&&interrupted);awaitEmpty();
    reset();mode=Mode::Held;
    for(unsigned n=0;n<4;++n){assert(TLinkRunPrivhelper(@[@"--fixture"],100)==-106&&pending().load()==n+1);}
    assert(heldSignals>0&&allocations.empty());const unsigned before=spawns;
    assert(TLinkRunPrivhelper(@[@"--fixture"],100)==-107&&spawns==before&&pending().load()==4);
    heldDone=true;awaitEmpty();reset();assert(TLinkRunPrivhelper(@[@"--fixture"],3000)==0);awaitEmpty();
    for(unsigned n=0;n<32;++n){reset();assert(TLinkRunPrivhelper(@[@"--fixture"],3000)==0);awaitEmpty();assert(allocations.empty());}
}
static void cancellationCases(){
    for(unsigned phase=0;phase<5;++phase){
        reset();TLinkScriptSession *session=[TLinkScriptSession new];sessionToStop=session;
        if(phase==0)session.stopRequested=YES;
        if(phase==1)stopDuringPath=true;
        if(phase==2)stopDuringAllocation=true;
        if(phase==3){mode=Mode::Hang;stopDuringProbe=true;}
        if(phase==4)stopAfterSpawn=true;
        assert([TLinkScriptRunTaskForSession(session,11,@"") isEqualToString:@"-109"]&&!sTLinkScriptHelperStop&&allocations.empty());
        assert(spawns==(phase>=3?1U:0U));awaitEmpty();
    }
    reset();TLinkScriptSession *old=[TLinkScriptSession new],*fresh=[TLinkScriptSession new];old.stopRequested=YES;
    {
        TLinkScriptHelperStopScope outer(old,true);const auto outerStop=sTLinkScriptHelperStop;
        assert(outerStop->stopped());
        std::thread external([]{@autoreleasepool{assert(!sTLinkScriptHelperStop&&TLinkRunPrivhelper(@[@"--fixture"],3000)==0);}});external.join();awaitEmpty();
        assert([TLinkScriptRunTaskForSession(fresh,11,@"") isEqualToString:@"0"]&&sTLinkScriptHelperStop==outerStop&&outerStop->stopped());awaitEmpty();
        for(unsigned kind=1;kind<=2;++kind){taskFault=kind;bool caught=false;
            @try{try{(void)TLinkScriptRunTaskForSession(fresh,11,@"");}catch(const std::runtime_error &){caught=kind==2;}}
            @catch(NSException *exception){(void)exception;caught=kind==1;}
            assert(caught&&sTLinkScriptHelperStop==outerStop);
        }
        taskFault=0;
    }
    assert(!sTLinkScriptHelperStop);
    reset();TLinkScriptSession *respring=[TLinkScriptSession new];sessionToStop=respring;
    assert([TLinkScriptRunTaskForSession(respring,74,@"confirm") isEqualToString:@"0"]&&respring.stopRequested&&!sTLinkScriptHelperStop);awaitEmpty();
    reset();TLinkScriptSession *stopped=[TLinkScriptSession new];stopped.stopRequested=YES;sessionToStop=stopped;
    assert(TLinkRunPrivhelper(@[@"--fixture"],3000)==0);awaitEmpty(); // An external call has no script binding.
    reset();assert([TLinkScriptRunTaskForSession(nil,11,@"") isEqualToString:@"-109"]&&spawns==0);
    reset();TLinkScriptSession *cleanup=[TLinkScriptSession new];cleanup.stopRequested=YES;
    assert([TLinkScriptRunTaskForSession(cleanup,17,@"stop") isEqualToString:@"non-helper"]&&spawns==0);
    __weak TLinkScriptSession *released;
    @autoreleasepool{TLinkScriptSession *session=[TLinkScriptSession new];released=session;{TLinkScriptHelperStopScope scope(session,true);session=nil;assert(released);}}
    assert(!released);
    reset();mode=Mode::Held;stopAfterSpawn=true;
    @autoreleasepool{TLinkScriptSession *session=[TLinkScriptSession new];released=session;sessionToStop=session;
        assert([TLinkScriptRunTaskForSession(session,11,@"") isEqualToString:@"-109"]&&pending().load()==1);sessionToStop=nil;session=nil;}
    assert(!released&&pending().load()==1);heldDone=true;awaitEmpty();
    puts("Streamd script helper stop passed: bound preflight/path/allocation/in-flight cancellation, nested/reentrant scope restoration, NS/C++ unwind, nil/lifetime, external isolation and intentional respring.");
}
int main(){@autoreleasepool{parityCases();boundedCases();cancellationCases();reset();dispatch_sync(reaperQueue(),^{});
    puts("Streamd privhelper passed: actual/frozen argv/spawn/exit/allocation parity, real disposable children, bounded timeout/reap, EINTR/ECHILD, four retained unknown children/fifth refusal, late retirement and 32 balanced lifecycles. No privileged helper or real service controlled.");}}
