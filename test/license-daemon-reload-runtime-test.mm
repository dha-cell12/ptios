#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <stdexcept>
#include <thread>
#include <vector>
static NSString *const SCLicenseLifecycleDidChangeNotification=@"fixture.license.daemon.changed";
static uint64_t TLinkLicenseGeneration(){return 7;}
@interface ReloadHarness:NSObject
@property(nonatomic,strong) NSMutableArray *jobs;
@property(nonatomic,strong) NSMutableArray *diagnosticWrites;
@property(nonatomic,copy) NSArray *replies;
@property NSUInteger requests;
@property NSUInteger invalidations;
@property NSUInteger uiRefreshes;
@property NSUInteger mainNotifications;
@property NSUInteger queuedHighWater;
@property NSUInteger replyIndex;
@property int transportFault;
@property int diagnosticFault;
@property BOOL realScheduler;
@property(nonatomic,copy) dispatch_block_t duringTransport;
@property(nonatomic,strong) dispatch_group_t work;
- (void)publishLicenseChange:(NSString *)reason;
- (void)enqueue:(dispatch_block_t)block queue:(dispatch_queue_t)queue delayed:(BOOL)delayed;
- (void)runNext;
- (void)drain;
- (NSString *)transport;
- (void)invalidateCache;
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason;
- (void)updateDiagnostics:(NSDictionary *)values;
- (uint64_t)nowMilliseconds;
@end
static void fixtureAsync(ReloadHarness *owner,dispatch_queue_t queue,dispatch_block_t block){[owner enqueue:block queue:queue delayed:NO];}
static void fixtureAfter(ReloadHarness *owner,dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block){
    (void)when;[owner enqueue:block queue:queue delayed:YES];
}
@implementation ReloadHarness
- (instancetype)init {
    self=[super init];if(self){_jobs=[NSMutableArray array];_diagnosticWrites=[NSMutableArray array];_replies=@[@"0;;ok"];_work=dispatch_group_create();}return self;
}
- (void)publishLicenseChange:(NSString *)reason{(void)reason;assert(false);}
- (void)enqueue:(dispatch_block_t)block queue:(dispatch_queue_t)queue delayed:(BOOL)delayed {
    if(queue==dispatch_get_main_queue()){
        @synchronized(self){++_mainNotifications;}block();return; // UI delivery controlled; no real UI.
    }
    if(self.realScheduler){
        dispatch_group_enter(_work);
        dispatch_block_t delivery=^{@autoreleasepool{block();dispatch_group_leave(self.work);}};
        if(delayed)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_MSEC),queue,delivery);
        else dispatch_async(queue,delivery);
        return;
    }
    @synchronized(self){
        [_jobs addObject:@{@"block":[block copy],@"delayed":@(delayed)}];
        _queuedHighWater=MAX(_queuedHighWater,_jobs.count);
    }
}
- (void)runNext {
    dispatch_block_t block;
    @synchronized(self){assert(_jobs.count>0);block=(dispatch_block_t)_jobs[0][@"block"];[_jobs removeObjectAtIndex:0];}
    @autoreleasepool{block();}
}
- (void)drain{unsigned turns=0;while(self.jobs.count){assert(++turns<10000);[self runNext];}}
- (NSString *)transport {
    NSString *reply;dispatch_block_t hook;int fault;
    @synchronized(self){
        ++_requests;const NSUInteger index=MIN(_replyIndex,_replies.count-1);++_replyIndex;
        id value=_replies[index];reply=value==[NSNull null]?nil:value;
        hook=_duringTransport;_duringTransport=nil;fault=_transportFault;_transportFault=0;
    }
    if(hook)hook();
    if(fault==1)[NSException raise:@"ReloadFixture" format:@"transport"];
    if(fault==2)throw std::runtime_error("transport");
    return reply;
}
- (void)invalidateCache{@synchronized(self){++_invalidations;}}
- (void)refreshLicenseUISnapshotAsyncForReason:(NSString *)reason{assert(reason);@synchronized(self){++_uiRefreshes;}}
- (void)updateDiagnostics:(NSDictionary *)values {
    @synchronized(self){
        if(values[@"streamd_invalidate_response"]||values[@"streamd_invalidate_retry_response"]){
            const int fault=_diagnosticFault;_diagnosticFault=0;
            if(fault==1)[NSException raise:@"ReloadFixture" format:@"diagnostics"];
            if(fault==2)throw std::runtime_error("diagnostics");
        }
        [_diagnosticWrites addObject:[values copy]];
    }
}
- (uint64_t)nowMilliseconds{return 100;}
@end
@interface CurrentReload:ReloadHarness
#include "DaemonReloadProperties.inc"
@end
@implementation CurrentReload
- (instancetype)init{self=[super init];if(self){
#include "DaemonReloadInit.inc"
}return self;}
#include "DaemonReloadUnderTest.inc"
@end
@interface LegacyReload:ReloadHarness
@end
@implementation LegacyReload
#include "DaemonReloadLegacy.inc"
@end
static void idle(CurrentReload *owner){assert(!owner.daemonReloadIdentity&&!owner.daemonReloadPending&&owner.jobs.count==0);}
static void parityCases(){
    for(NSArray *replies in @[@[@"0;;ok"],@[@"-1;;fail",@"0;;retry"],@[[NSNull null],@"-1;;failed"],@[@"0;;Ứng dụng 测试 😀"]]){@autoreleasepool{
        LegacyReload *old=[LegacyReload new];old.replies=replies;
        [old publishLicenseChange:@"fixture"];[old drain];
        CurrentReload *current=[CurrentReload new];current.replies=replies;
        [current publishLicenseChange:@"fixture"];[current drain];idle(current);
        assert([old.diagnosticWrites isEqual:current.diagnosticWrites]&&old.requests==current.requests);
        assert(current.invalidations==1&&current.uiRefreshes==1&&current.mainNotifications==1&&current.queuedHighWater==1);
    }}
}
static void coalescingCases(){
    CurrentReload *current=[CurrentReload new];LegacyReload *old=[LegacyReload new];
    for(unsigned n=0;n<1000;++n){[current publishLicenseChange:@"burst"];[old publishLicenseChange:@"burst"];}
    assert(current.jobs.count==1&&old.jobs.count==1000);
    [current drain];[old drain];idle(current);
    assert(current.requests==1&&old.requests==1000&&current.diagnosticWrites.count==1001&&old.diagnosticWrites.count==2000);
    assert(current.invalidations==1000&&current.uiRefreshes==1000&&current.mainNotifications==1000);
    current=[CurrentReload new];
    __weak CurrentReload *weakCurrent=current;
    current.duringTransport=^{for(unsigned n=0;n<1000;++n)[weakCurrent publishLicenseChange:@"during"];};
    [current publishLicenseChange:@"initial"];[current runNext];
    assert(current.requests==1&&current.jobs.count==1&&current.queuedHighWater==1);
    [current drain];idle(current);assert(current.requests==2&&current.invalidations==1001);
    // A pending change replaces the old delayed retry with a fresh attempt,
    // which may have its own single retry if it fails.
    current=[CurrentReload new];current.replies=@[@"-1;;old",@"-1;;new",@"0;;new-retry"];
    [current publishLicenseChange:@"old"];[current runNext];
    assert([current.jobs[0][@"delayed"] boolValue]);
    for(unsigned n=0;n<1000;++n)[current publishLicenseChange:@"new"];
    assert(current.jobs.count==1);[current drain];idle(current);assert(current.requests==3);
    assert([current.diagnosticWrites[1002][@"streamd_invalidate_response"] isEqualToString:@"-1;;new"]);
    assert([current.diagnosticWrites.lastObject[@"streamd_invalidate_retry_response"] isEqualToString:@"0;;new-retry"]);
}
static void faultCases(){
    for(int kind=1;kind<=2;++kind){@autoreleasepool{
        CurrentReload *owner=[CurrentReload new];owner.transportFault=kind;
        [owner publishLicenseChange:nil];[owner drain];idle(owner);assert(owner.requests==2);
        assert([owner.diagnosticWrites[1][@"streamd_invalidate_response"] isEqualToString:@"daemon_reload_exception"]);
        owner.diagnosticFault=kind;[owner publishLicenseChange:@"diagnostics"];[owner drain];idle(owner);
        assert(owner.requests==3); // A successful reload is never replayed for diagnostics alone.
        [owner publishLicenseChange:@"recovered"];[owner drain];idle(owner);assert(owner.requests==4);
    }}
    CurrentReload *owner=[CurrentReload new];[owner publishLicenseChange:@"first"];
    NSObject *old=owner.daemonReloadIdentity;[owner drain];idle(owner);
    [owner publishLicenseChange:@"next"];NSObject *next=owner.daemonReloadIdentity;
    [owner performDaemonReload:old retry:YES];assert(owner.requests==1&&owner.daemonReloadIdentity==next);
    [owner drain];idle(owner);assert(owner.requests==2);
}
static void realQueueCases(){
    @autoreleasepool{
        CurrentReload *owner=[CurrentReload new];owner.realScheduler=YES;owner.replies=@[@"-1;;retry",@"0;;recovered"];
        [owner publishLicenseChange:@"real-retry"];
        assert(dispatch_group_wait(owner.work,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        idle(owner);assert(owner.requests==2);
        assert([owner.diagnosticWrites.lastObject[@"streamd_invalidate_retry_response"] isEqualToString:@"0;;recovered"]);
    }
    for(unsigned cycle=0;cycle<32;++cycle){@autoreleasepool{
        CurrentReload *owner=[CurrentReload new];owner.realScheduler=YES;
        dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
        owner.duringTransport=^{dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);};
        [owner publishLicenseChange:@"held"];
        assert(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        std::vector<std::thread> threads;
        for(unsigned n=0;n<8;++n){threads.emplace_back([owner]{@autoreleasepool{for(unsigned k=0;k<32;++k)[owner publishLicenseChange:@"concurrent"];}});}
        for(auto &thread:threads){thread.join();}
        dispatch_semaphore_signal(release);
        assert(dispatch_group_wait(owner.work,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        idle(owner);assert(owner.requests==2&&owner.invalidations==257&&owner.mainNotifications==257);
    }}
}
int main(){@autoreleasepool{
    parityCases();coalescingCases();faultCases();realQueueCases();
    puts("License daemon reload passed: frozen isolated primary/retry diagnostics, 1000-publication coalescing, in-flight pending and retry promotion, NS/C++ provider/diagnostics recovery, stale identities and 32 real serial-GCD/concurrent publication lifecycles. Transport/UI/persistence/delay controlled; device qualification pending.");
}return 0;}
