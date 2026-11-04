#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include "../shared/TLinkSupervisorWatch.h"
#include "supervisor-watch-wait-fixture.h"
#include <sys/wait.h>
#include <spawn.h>
#include <unistd.h>
#include <signal.h>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
extern char **environ;
#include "WatchThrottle.inc"
static uint64_t tick=100;
static double wallOffset=0;
static uint64_t fixtureNow(){return tick;}
@interface FixtureDate:NSObject
@property double value;
+ (instancetype)date;
- (NSTimeInterval)timeIntervalSinceDate:(FixtureDate *)other;
@end
@implementation FixtureDate
+ (instancetype)date{FixtureDate *date=[FixtureDate new];date.value=tick/1000.0+wallOffset;return date;}
- (NSTimeInterval)timeIntervalSinceDate:(FixtureDate *)other{return self.value-other.value;}
@end
@interface WatchHarness:NSObject {
@protected
    dispatch_queue_t _queue;
    pid_t _pid;
    BOOL _running;
    BOOL _autoRespawn;
    uint64_t _lastSpawnContinuous;
    FixtureDate *_lastSpawn;
}
@property(nonatomic,strong) NSMutableArray *logs;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,copy) dispatch_block_t pending;
@property int64_t delayNs;
@property unsigned spawns;
- (void)handleChildExit:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid;
- (void)seed:(pid_t)pid started:(uint64_t)started;
- (void)emitLog:(NSString *)message;
- (void)emitRunning:(BOOL)running pid:(pid_t)pid;
- (void)spawnLocked;
- (void)cancelPendingRespawnLocked;
- (void)scheduleRespawnLockedWithDelay:(NSTimeInterval)delay;
- (void)fire;
- (void)disable;
- (void)markRunning;
- (NSDictionary *)snapshot;
@end
static void fixtureAfter(WatchHarness *owner,int64_t delay,dispatch_queue_t queue,dispatch_block_t block){
    assert(queue);owner.delayNs=delay;owner.pending=block;
}
@implementation WatchHarness
- (instancetype)init{self=[super init];if(self){_queue=dispatch_queue_create("fixture.supervisor.watch",DISPATCH_QUEUE_SERIAL);_logs=[NSMutableArray array];_events=[NSMutableArray array];}return self;}
- (void)seed:(pid_t)pid started:(uint64_t)started {
    _pid=pid;_running=YES;_autoRespawn=YES;_lastSpawnContinuous=started;
    _lastSpawn=[FixtureDate new];_lastSpawn.value=started/1000.0;
}
- (void)handleChildExit:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid{(void)w;(void)status;(void)expectedPid;assert(false);}
- (void)emitLog:(NSString *)message{[_logs addObject:message];}
- (void)emitRunning:(BOOL)running pid:(pid_t)pid{[_events addObject:@{@"running":@(running),@"pid":@(pid)}];}
- (void)spawnLocked{++_spawns;}
- (void)cancelPendingRespawnLocked{_pending=nil;}
- (void)scheduleRespawnLockedWithDelay:(NSTimeInterval)delay {
    fixtureAfter(self,static_cast<int64_t>(delay*NSEC_PER_SEC),_queue,^{if(self->_autoRespawn&&!self->_running)[self spawnLocked];});
}
- (void)fire{dispatch_block_t block=_pending;_pending=nil;if(block)block();}
- (void)disable{_autoRespawn=NO;}
- (void)markRunning{_running=YES;}
- (NSDictionary *)snapshot{return @{@"pid":@(_pid),@"running":@(_running),@"logs":[_logs copy],@"events":[_events copy],@"scheduled":@(_pending!=nil)};}
@end
@interface CurrentWatch:WatchHarness
@end
@implementation CurrentWatch
#include "WatchExitUnderTest.inc"
@end
@interface LegacyWatch:WatchHarness
@end
@implementation LegacyWatch
#include "WatchExitLegacy.inc"
@end
static void parityCases(){
    for(uint64_t age:{uint64_t(0),uint64_t(250),uint64_t(1000),uint64_t(2500),uint64_t(3000),uint64_t(9000)}){
        for(unsigned scenario=0;scenario<5;++scenario){@autoreleasepool{
            wallOffset=0;tick=100+age;CurrentWatch *current=[CurrentWatch new];LegacyWatch *old=[LegacyWatch new];
            [current seed:42 started:100];[old seed:42 started:100];
            if(scenario==3){[current disable];[old disable];}
            const pid_t expected=scenario==4?99:42;
            const pid_t returned=scenario==2?-1:42;
            const int status=scenario==1?SIGTERM:(7<<8);
            [current handleChildExit:returned status:status expectedPid:expected];
            [old handleChildExit:returned status:status expectedPid:expected];
            assert([[current snapshot] isEqual:[old snapshot]]&&std::llabs(current.delayNs-old.delayNs)<=1);
            [current fire];[old fire];assert(current.spawns==old.spawns);
        }}
    }
    for(unsigned gate=0;gate<2;++gate){@autoreleasepool{
        tick=350;CurrentWatch *owner=[CurrentWatch new];[owner seed:42 started:100];
        [owner handleChildExit:42 status:0 expectedPid:42];assert(owner.pending&&owner.delayNs==2750000000LL);
        if(gate)[owner markRunning];else [owner disable];
        [owner fire];assert(owner.spawns==0);
    }}
}
static void clockCases(){
    for(double offset:{-3600.0,3600.0}){@autoreleasepool{
        tick=350;wallOffset=offset;CurrentWatch *current=[CurrentWatch new];LegacyWatch *old=[LegacyWatch new];
        [current seed:42 started:100];[old seed:42 started:100];
        [current handleChildExit:42 status:0 expectedPid:42];[old handleChildExit:42 status:0 expectedPid:42];
        assert(current.delayNs==2750000000LL);
        assert(offset>0?old.delayNs==0:old.delayNs>3600000000000LL);
        [current fire];[old fire];
    }}
    wallOffset=0;
    for(unsigned kind=0;kind<3;++kind){@autoreleasepool{
        CurrentWatch *owner=[CurrentWatch new];[owner seed:42 started:kind==1?UINT64_MAX:100];
        tick=kind==0?UINT64_MAX:(kind==2?99:350);
        [owner handleChildExit:42 status:0 expectedPid:42];assert(owner.delayNs==3000000000LL);
        [owner fire];assert(owner.spawns==1);
    }}
}
static unsigned waitCalls=0,interrupted=0;
static void posixCases(){
    watchWaitProvider=[](pid_t pid,int *status,int flags)->pid_t{
        assert(pid>0&&flags==0);++waitCalls;
        if(interrupted){--interrupted;errno=EINTR;return -1;}
        return ::waitpid(pid,status,flags);
    };
    for(unsigned n=0;n<32;++n){
        char shell[]="/bin/sh",flag[]="-c",command[]="exit 7";char *args[]={shell,flag,command,nullptr};
        pid_t child=-1;assert(::posix_spawn(&child,shell,nullptr,nullptr,args,environ)==0&&child>0);
        waitCalls=0;interrupted=3;const auto result=runWatcherWait(child);
        assert(result.pid==child&&WIFEXITED(result.status)&&WEXITSTATUS(result.status)==7&&waitCalls>=4);
        int status=0;assert(::waitpid(child,&status,WNOHANG)==-1&&errno==ECHILD);
    }
}
int main(){@autoreleasepool{
    parityCases();clockCases();posixCases();
    puts("Supervisor watcher Foundation passed: frozen exit/state/log/respawn gates, continuous throttle despite wall jumps/clock faults and 32 real disposable children reaped after injected EINTR. Clocks/timer/spawn effects controlled; no real service changed. Device qualification pending.");
}return 0;}
