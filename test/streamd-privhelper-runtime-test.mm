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
static NSString *TLinkPrivhelperPath(){return helperPath;}
static void *fixtureCalloc(size_t count,size_t size){++allocCalls;if(allocCalls==failAllocation)return nullptr;void *p=::calloc(count,size);if(p)assert(allocations.insert(p).second);return p;}
static char *fixtureDup(const char *s){++allocCalls;if(allocCalls==failAllocation)return nullptr;char *p=::strdup(s);if(p)assert(allocations.insert(p).second);return p;}
static void fixtureFree(void *p){if(p){assert(allocations.erase(p)==1);::free(p);}}
static int fixtureSpawn(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,const posix_spawnattr_t *attrs,char *const argv[],char *const envp[]){
    assert(std::strcmp(path,"/fixture/privhelper")==0&&!actions&&!attrs&&envp==environ);++spawns;
    NSMutableArray *args=[NSMutableArray array];for(size_t n=0;argv[n];++n)[args addObject:[NSString stringWithUTF8String:argv[n]]];lastArgs=[args copy];
    if(mode==Mode::SpawnError)return EACCES;
    if(mode==Mode::InvalidPid){*pid=0;return 0;}
    if(mode==Mode::Held||mode==Mode::Missing){*pid=42;return 0;}
    const pid_t created=::fork();assert(created>=0);
    if(created==0){
        if(mode==Mode::Hang){for(;;)::pause();}
        if(mode==Mode::Signalled){::kill(::getpid(),SIGTERM);::_exit(1);}
        ::_exit(mode==Mode::Exit7?7:0);
    }
    childPid=created;*pid=created;return 0;
}
static Ops fixtureOps(){
    Ops ops=posixOps();
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
static void awaitEmpty(){const uint64_t until=posixOps().now(nullptr)+5000;while(pending().load()){assert(posixOps().now(nullptr)<until);std::this_thread::sleep_for(std::chrono::milliseconds(10));}}
static void reset(){awaitEmpty();assert(allocations.empty());mode=Mode::Success;helperPath=@"/fixture/privhelper";lastArgs=nil;spawns=allocCalls=failAllocation=0;fixtureWaitLimit=3000;heldDone=false;heldSignals=0;interrupted=false;childPid=-1;}
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
int main(){@autoreleasepool{parityCases();boundedCases();reset();dispatch_sync(reaperQueue(),^{});
    puts("Streamd privhelper passed: actual/frozen argv/spawn/exit/allocation parity, real disposable children, bounded timeout/reap, EINTR/ECHILD, four retained unknown children/fifth refusal, late retirement and 32 balanced lifecycles. No privileged helper or real service controlled.");}}
