#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
static unsigned created=0,cancelled=0,live=0;
static bool allocationFailure=false;
static int setupFault=0;
@interface FixtureTimer:NSObject
@property BOOL resumed;
@property BOOL cancelled;
@property BOOL armed;
@property(nonatomic,copy) dispatch_block_t handler;
@end
@implementation FixtureTimer
- (instancetype)init{self=[super init];if(self){++created;++live;}return self;}
- (void)dealloc{assert(_resumed&&_cancelled);--live;}
@end
static FixtureTimer *lastTimer;
static FixtureTimer *fixtureCreate(dispatch_source_type_t type,uintptr_t handle,unsigned long mask,dispatch_queue_t queue){
    assert(type==DISPATCH_SOURCE_TYPE_TIMER&&handle==0&&mask==0&&queue);
    if(allocationFailure)return nil;
    lastTimer=[FixtureTimer new];return lastTimer;
}
static void fixtureResume(FixtureTimer *timer){assert(!timer.resumed);timer.resumed=YES;}
static void failSetup(int kind){if(kind&1)[NSException raise:@"RespawnFixture" format:@"setup"];throw std::runtime_error("setup");}
static void fixtureHandler(FixtureTimer *timer,dispatch_block_t handler){
    assert(timer.resumed);
    if(setupFault==1||setupFault==2){const int kind=setupFault;setupFault=0;failSetup(kind);}
    timer.handler=handler;
}
static void fixtureArm(FixtureTimer *timer,dispatch_time_t when,uint64_t interval,uint64_t leeway){
    (void)when;assert(timer.resumed&&!timer.cancelled&&interval==DISPATCH_TIME_FOREVER&&leeway==0);
    if(setupFault==3||setupFault==4){const int kind=setupFault;setupFault=0;failSetup(kind);}
    timer.armed=YES;
}
static void fixtureCancel(FixtureTimer *timer){assert(timer.resumed&&!timer.cancelled);timer.cancelled=YES;++cancelled;}
@interface RespawnHarness:NSObject {
@protected
    dispatch_queue_t _queue;
    BOOL _autoRespawn;
    BOOL _running;
}
@property(nonatomic,strong) NSMutableArray *logs;
@property unsigned spawns;
@property int spawnFault;
@property(nonatomic,copy) dispatch_block_t duringSpawn;
@property(nonatomic,strong) dispatch_semaphore_t spawned;
@property(nonatomic,readonly) dispatch_queue_t ownerQueue;
- (void)emitLog:(NSString *)message;
- (void)spawnLocked;
- (void)enable:(BOOL)enabled running:(BOOL)running;
@end
@implementation RespawnHarness
- (instancetype)init{self=[super init];if(self){_queue=dispatch_queue_create("fixture.respawn.owner",DISPATCH_QUEUE_SERIAL);_autoRespawn=YES;_logs=[NSMutableArray array];_spawned=dispatch_semaphore_create(0);}return self;}
- (dispatch_queue_t)ownerQueue{return _queue;}
- (void)enable:(BOOL)enabled running:(BOOL)running{_autoRespawn=enabled;_running=running;}
- (void)emitLog:(NSString *)message{[_logs addObject:message];}
- (void)spawnLocked{
    ++_spawns;dispatch_block_t hook=_duringSpawn;_duringSpawn=nil;if(hook)hook();
    if(_spawnFault==1)[NSException raise:@"RespawnFixture" format:@"spawn"];
    if(_spawnFault==2)throw std::runtime_error("spawn");
    dispatch_semaphore_signal(_spawned);
}
@end
@protocol OwnedRespawn <NSObject>
- (void)cancelPendingRespawnLocked;
- (void)scheduleRespawnLockedWithDelay:(NSTimeInterval)delay;
- (BOOL)hasTimer;
- (NSObject *)token;
@end
@interface FakeOwner:RespawnHarness <OwnedRespawn> {
#include "RespawnFields.inc"
}
@end
@implementation FakeOwner
#include "RespawnUnderTest.inc"
- (BOOL)hasTimer{return _respawnTimer!=nil;}
- (NSObject *)token{return _respawnIdentity;}
@end
@interface RealOwner:RespawnHarness <OwnedRespawn> {
#include "RespawnRealFields.inc"
}
@end
@implementation RealOwner
#include "RespawnRealUnderTest.inc"
- (BOOL)hasTimer{return _respawnTimer!=nullptr;}
- (NSObject *)token{return _respawnIdentity;}
@end
static void idle(id<OwnedRespawn> owner){assert(![owner hasTimer]&&![owner token]);}
static void staleCases(){@autoreleasepool{
    FakeOwner *owner=[FakeOwner new];[owner scheduleRespawnLockedWithDelay:3];
    FixtureTimer *old=lastTimer;dispatch_block_t stale=old.handler;NSObject *oldToken=[owner token];
    [owner cancelPendingRespawnLocked];idle(owner);assert(old.cancelled);
    [owner scheduleRespawnLockedWithDelay:3];FixtureTimer *current=lastTimer;NSObject *token=[owner token];
    assert(token!=oldToken&&current.armed);stale();
    assert([owner token]==token&&!current.cancelled&&owner.spawns==0);
    dispatch_block_t delivery=current.handler;delivery();idle(owner);assert(current.cancelled&&owner.spawns==1);
    delivery();stale();assert(owner.spawns==1);lastTimer=nil;
}assert(live==0);}
static void gateAndFaultCases(){
    for(unsigned gate=0;gate<2;++gate){@autoreleasepool{
        FakeOwner *owner=[FakeOwner new];[owner scheduleRespawnLockedWithDelay:0];
        [owner enable:gate?YES:NO running:gate?YES:NO];dispatch_block_t block=lastTimer.handler;block();
        idle(owner);assert(lastTimer.cancelled&&owner.spawns==0);lastTimer=nil;
    }}
    @autoreleasepool{
        FakeOwner *owner=[FakeOwner new];allocationFailure=true;[owner scheduleRespawnLockedWithDelay:0];allocationFailure=false;
        idle(owner);assert(owner.logs.count==1&&owner.spawns==0);
    }
    for(int kind=1;kind<=4;++kind){@autoreleasepool{
        FakeOwner *owner=[FakeOwner new];setupFault=kind;bool caught=false;
        @try{try{[owner scheduleRespawnLockedWithDelay:0];}catch(const std::runtime_error &){caught=true;}}
        @catch(NSException *exception){(void)exception;caught=true;}
        idle(owner);assert(caught&&lastTimer.resumed&&lastTimer.cancelled);lastTimer=nil;
    }}
    for(int kind=1;kind<=2;++kind){@autoreleasepool{
        FakeOwner *owner=[FakeOwner new];owner.spawnFault=kind;[owner scheduleRespawnLockedWithDelay:0];
        dispatch_block_t block=lastTimer.handler;bool caught=false;
        @try{try{block();}catch(const std::runtime_error &){caught=true;}}
        @catch(NSException *exception){(void)exception;caught=true;}
        idle(owner);assert(caught&&lastTimer.cancelled&&owner.spawns==1);lastTimer=nil;
    }}
    assert(live==0);
}
static void lifetimeCases(){
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        FakeOwner *owner=[FakeOwner new];[owner scheduleRespawnLockedWithDelay:0];[owner scheduleRespawnLockedWithDelay:0];
        dispatch_block_t block=lastTimer.handler;block();idle(owner);assert(owner.spawns==1);lastTimer=nil;
    }}
    assert(live==0&&created==cancelled);
    __weak FakeOwner *weakOwner;
    @autoreleasepool{
        FakeOwner *owner=[FakeOwner new];weakOwner=owner;[owner scheduleRespawnLockedWithDelay:3];
        [owner cancelPendingRespawnLocked];lastTimer=nil;
    }
    assert(!weakOwner&&live==0);
    @autoreleasepool{
        FakeOwner *owner=[FakeOwner new];__weak FakeOwner *weak=owner;
        owner.duringSpawn=^{[weak scheduleRespawnLockedWithDelay:0];};
        [owner scheduleRespawnLockedWithDelay:0];dispatch_block_t first=lastTimer.handler;first();
        assert([owner hasTimer]&&owner.spawns==1);NSObject *token=[owner token];first();assert([owner token]==token&&owner.spawns==1);
        dispatch_block_t next=lastTimer.handler;next();idle(owner);assert(owner.spawns==2);lastTimer=nil;
    }
    assert(live==0&&created==cancelled);
}
static void realCases(){
    for(unsigned n=0;n<32;++n){@autoreleasepool{
        RealOwner *owner=[RealOwner new];dispatch_sync(owner.ownerQueue,^{
            [owner scheduleRespawnLockedWithDelay:0];[owner cancelPendingRespawnLocked];[owner scheduleRespawnLockedWithDelay:0];
        });
        assert(dispatch_semaphore_wait(owner.spawned,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        dispatch_sync(owner.ownerQueue,^{idle(owner);assert(owner.spawns==1);});
    }}
    @autoreleasepool{
        RealOwner *owner=[RealOwner new];dispatch_sync(owner.ownerQueue,^{
            [owner scheduleRespawnLockedWithDelay:3];[owner cancelPendingRespawnLocked];idle(owner);assert(owner.spawns==0);
        });
    }
}
int main(){@autoreleasepool{
    staleCases();gateAndFaultCases();lifetimeCases();realCases();
    puts("Supervisor respawn passed: actual owned timer cancellation/replacement, stale/duplicate delivery fences, disabled/running gates, allocation/NS-C++ setup/spawn faults, reentry/lifetime, 1000 balanced fake cycles and 32 real serial-GCD one-shot deliveries. No real service spawned; device qualification pending.");
}return 0;}
