#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <stdexcept>
#include <thread>
#include <vector>
static NSString *const SCLicenseLifecycleDidChangeNotification=@"fixture.ui.snapshot.changed";
@interface UIHarness:NSObject
@property(nonatomic,strong) dispatch_queue_t uiSnapshotQueue;
@property(nonatomic,copy) NSDictionary *uiLicenseSnapshot;
@property BOOL uiSnapshotRefreshInFlight;
@property BOOL uiSnapshotRefreshPending;
@property(nonatomic,copy) NSString *uiSnapshotPendingReason;
@property uint64_t uiSnapshotRefreshCount;
@property double uiSnapshotLastRefreshMs;
@property double uiSnapshotMaxRefreshMs;
@property(nonatomic,strong) NSMutableArray *jobs;
@property(nonatomic,strong) NSMutableArray *writes;
@property(nonatomic,strong) dispatch_group_t work;
@property(nonatomic,strong) dispatch_semaphore_t entered;
@property(nonatomic,strong) dispatch_semaphore_t releaseStatus;
@property(nonatomic,copy) dispatch_block_t duringStatus;
@property(nonatomic,copy) dispatch_block_t duringDiagnostics;
@property int statusFault;
@property int performanceFault;
@property int diagnosticsFault;
@property unsigned statusCalls;
@property unsigned notifications;
@property unsigned workers;
@property BOOL realScheduler;
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason;
- (NSDictionary *)statusProvider;
- (NSDictionary *)performanceProvider;
- (void)updateDiagnostics:(NSDictionary *)values;
- (uint64_t)nowMilliseconds;
- (void)runNext;
- (void)drain;
@end
static void failProvider(int kind){if(kind==1)[NSException raise:@"UISnapshotFixture" format:@"provider"];if(kind==2)throw std::runtime_error("provider");}
static void fixtureAsync(UIHarness *owner,dispatch_queue_t queue,dispatch_block_t block){
    if(queue==dispatch_get_main_queue()){
        dispatch_block_t deliver=^{assert([NSThread isMainThread]);owner.notifications++;block();};
        if(owner.realScheduler)dispatch_async(queue,deliver);else deliver();return;
    }
    assert(queue==owner.uiSnapshotQueue);owner.workers++;
    if(owner.realScheduler)dispatch_group_async(owner.work,queue,^{@autoreleasepool{block();}});
    else [owner.jobs addObject:[block copy]];
}
@implementation UIHarness
- (instancetype)init{self=[super init];if(self){_uiSnapshotQueue=dispatch_queue_create("fixture.ui.snapshot",DISPATCH_QUEUE_SERIAL);_uiLicenseSnapshot=@{@"snapshot_ready":@NO,@"state":@"loading"};_jobs=[NSMutableArray array];_writes=[NSMutableArray array];_work=dispatch_group_create();}return self;}
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason{(void)reason;assert(false);}
- (NSDictionary *)statusProvider {
    dispatch_block_t hook;int fault;unsigned call;
    @synchronized(self){call=++_statusCalls;hook=_duringStatus;_duringStatus=nil;fault=_statusFault;_statusFault=0;}
    if(hook)hook();
    if(call==1&&_entered){dispatch_semaphore_signal(_entered);assert(dispatch_semaphore_wait(_releaseStatus,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    failProvider(fault);
    return @{@"state":@"valid",@"licensed":@YES,@"features":@[@"automation"],@"license_generation":@7};
}
- (NSDictionary *)performanceProvider{const int fault=_performanceFault;_performanceFault=0;failProvider(fault);return @{@"fixture":@1};}
- (void)updateDiagnostics:(NSDictionary *)values {
    dispatch_block_t hook;int fault;
    @synchronized(self){hook=_duringDiagnostics;_duringDiagnostics=nil;fault=_diagnosticsFault;_diagnosticsFault=0;}
    if(hook)hook();failProvider(fault);[_writes addObject:[values copy]];
}
- (uint64_t)nowMilliseconds{return 100;}
- (void)runNext{assert(_jobs.count);dispatch_block_t block=(dispatch_block_t)_jobs[0];[_jobs removeObjectAtIndex:0];@autoreleasepool{block();}}
- (void)drain{unsigned turns=0;while(_jobs.count){assert(++turns<10);[self runNext];}}
@end
@interface CurrentUI:UIHarness
@end
@implementation CurrentUI
#include "UISnapshotUnderTest.inc"
@end
@interface LegacyUI:UIHarness
@end
@implementation LegacyUI
#include "UISnapshotLegacy.inc"
@end
static void idle(UIHarness *owner){assert(!owner.uiSnapshotRefreshInFlight&&!owner.uiSnapshotRefreshPending&&!owner.uiSnapshotPendingReason&&owner.jobs.count==0);}
static NSDictionary *normalized(NSDictionary *snapshot){NSMutableDictionary *copy=[snapshot mutableCopy];copy[@"snapshot_refresh_ms"]=@0;return copy;}
static NSArray *normalizedWrites(NSArray *writes){
    NSMutableArray *result=[NSMutableArray array];for(NSDictionary *row in writes){NSMutableDictionary *copy=[row mutableCopy];copy[@"ui_snapshot_last_refresh_ms"]=@0;copy[@"ui_snapshot_max_refresh_ms"]=@0;[result addObject:copy];}return result;
}
static void parityCases(){
    for(id value in @[@"normal",@"",[NSNull null]]){@autoreleasepool{
        NSString *reason=value==[NSNull null]?nil:value;CurrentUI *current=[CurrentUI new];LegacyUI *old=[LegacyUI new];
        [current refreshLicenseUISnapshotAsyncForReason:reason];[old refreshLicenseUISnapshotAsyncForReason:reason];[current drain];[old drain];idle(current);
        assert([normalized(current.uiLicenseSnapshot) isEqual:normalized(old.uiLicenseSnapshot)]);
        assert([normalizedWrites(current.writes) isEqual:normalizedWrites(old.writes)]&&current.notifications==1&&current.uiSnapshotRefreshCount==1);
    }}
    CurrentUI *current=[CurrentUI new];NSMutableString *mutableReason=[@"original" mutableCopy];
    [current refreshLicenseUISnapshotAsyncForReason:mutableReason];[mutableReason setString:@"later"];[current drain];idle(current);
    assert([current.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"original"]);
}
static void installHandoff(UIHarness *owner){
    __weak UIHarness *weak=owner;
    owner.duringStatus=^{[weak refreshLicenseUISnapshotAsyncForReason:@"older_pending"];};
    owner.duringDiagnostics=^{[weak refreshLicenseUISnapshotAsyncForReason:@"newer"];};
}
static void pendingCases(){
    @autoreleasepool{
        CurrentUI *current=[CurrentUI new];LegacyUI *old=[LegacyUI new];
        [current refreshLicenseUISnapshotAsyncForReason:@"initial"];[old refreshLicenseUISnapshotAsyncForReason:@"initial"];
        for(unsigned n=0;n<1000;++n){NSString *reason=[NSString stringWithFormat:@"burst-%u",n];[current refreshLicenseUISnapshotAsyncForReason:reason];[old refreshLicenseUISnapshotAsyncForReason:reason];}
        assert(current.jobs.count==1&&old.jobs.count==1);[current drain];[old drain];idle(current);
        assert(current.statusCalls==1&&old.statusCalls==2&&current.workers==1);
        assert([current.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"burst-999"]);
    }
    @autoreleasepool{
        CurrentUI *current=[CurrentUI new];LegacyUI *old=[LegacyUI new];installHandoff(current);installHandoff(old);
        [current refreshLicenseUISnapshotAsyncForReason:@"initial"];[old refreshLicenseUISnapshotAsyncForReason:@"initial"];[current drain];[old drain];idle(current);
        assert(current.statusCalls==2&&old.statusCalls==3&&current.workers==1);
        assert([current.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"newer"]&&[old.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"older_pending"]);
    }
    @autoreleasepool{
        CurrentUI *owner=[CurrentUI new];__weak CurrentUI *weak=owner;
        owner.duringStatus=^{[weak refreshLicenseUISnapshotAsyncForReason:@""];};
        [owner refreshLicenseUISnapshotAsyncForReason:@"initial"];[owner drain];idle(owner);
        assert(owner.statusCalls==2&&[owner.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@""]);
    }
}
static void faultCases(){
    for(int kind=1;kind<=2;++kind){
        for(unsigned stage=0;stage<3;++stage){@autoreleasepool{
            CurrentUI *owner=[CurrentUI new];NSDictionary *before=owner.uiLicenseSnapshot;
            if(!stage)owner.statusFault=kind;else if(stage==1)owner.performanceFault=kind;else owner.diagnosticsFault=kind;
            [owner refreshLicenseUISnapshotAsyncForReason:@"fault"];[owner drain];idle(owner);
            if(!stage)assert([owner.uiLicenseSnapshot isEqual:before]&&owner.notifications==0&&owner.uiSnapshotRefreshCount==0);
            else assert([owner.uiLicenseSnapshot[@"snapshot_ready"] boolValue]&&owner.notifications==1&&owner.uiSnapshotRefreshCount==1);
            [owner refreshLicenseUISnapshotAsyncForReason:@"recovered"];[owner drain];idle(owner);assert([owner.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"recovered"]);
        }}
        @autoreleasepool{
            CurrentUI *owner=[CurrentUI new];owner.statusFault=kind;__weak CurrentUI *weak=owner;
            owner.duringStatus=^{[weak refreshLicenseUISnapshotAsyncForReason:@"pending_after_failure"];};
            [owner refreshLicenseUISnapshotAsyncForReason:@"initial"];[owner drain];idle(owner);
            assert(owner.statusCalls==2&&owner.notifications==1&&[owner.uiLicenseSnapshot[@"snapshot_reason"] isEqualToString:@"pending_after_failure"]);
            LegacyUI *old=[LegacyUI new];old.statusFault=kind;[old refreshLicenseUISnapshotAsyncForReason:@"failure"];bool caught=false;
            @try{try{[old runNext];}catch(const std::runtime_error &){caught=true;}}
            @catch(NSException *exception){(void)exception;caught=true;}
            assert(caught&&old.uiSnapshotRefreshInFlight);[old refreshLicenseUISnapshotAsyncForReason:@"blocked"];assert(old.jobs.count==0);
        }
    }
    @autoreleasepool{
        CurrentUI *owner=[CurrentUI new];[owner refreshLicenseUISnapshotAsyncForReason:@"good"];[owner drain];NSDictionary *before=owner.uiLicenseSnapshot;
        owner.statusFault=1;[owner refreshLicenseUISnapshotAsyncForReason:@"failure"];[owner drain];idle(owner);
        assert([owner.uiLicenseSnapshot isEqual:before]&&owner.notifications==1&&owner.uiSnapshotRefreshCount==1);
    }
}
static void realCases(){
    for(unsigned n=0;n<32;++n){@autoreleasepool{
        CurrentUI *owner=[CurrentUI new];owner.realScheduler=YES;owner.entered=dispatch_semaphore_create(0);owner.releaseStatus=dispatch_semaphore_create(0);
        [owner refreshLicenseUISnapshotAsyncForReason:@"initial"];
        assert(dispatch_semaphore_wait(owner.entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        std::vector<std::thread> threads;
        for(unsigned t=0;t<8;++t){threads.emplace_back([owner,t]{@autoreleasepool{for(unsigned k=0;k<32;++k)[owner refreshLicenseUISnapshotAsyncForReason:[NSString stringWithFormat:@"thread-%u-%u",t,k]];}});}
        for(auto &thread:threads){thread.join();}dispatch_semaphore_signal(owner.releaseStatus);
        assert(dispatch_group_wait(owner.work,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);idle(owner);
        const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;
        while(owner.notifications<2&&CFAbsoluteTimeGetCurrent()<end)CFRunLoopRunInMode(kCFRunLoopDefaultMode,.01,false);
        assert(owner.statusCalls==2&&owner.workers==1&&owner.notifications==2&&owner.uiSnapshotRefreshCount==2);
    }}
}
int main(){@autoreleasepool{
    parityCases();pendingCases();faultCases();realCases();
    puts("License UI snapshot passed: frozen ordinary snapshots/diagnostics, immutable reason, 1000 pre-start changes, latest/empty pending handoff, NS-C++ status/performance/diagnostic recovery, retained good snapshot/ready notifications and 32 real GCD/eight-thread lifecycles. Verifier/UI/persistence providers controlled; device qualification pending.");
}return 0;}
