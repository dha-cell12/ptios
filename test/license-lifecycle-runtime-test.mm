#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>
#include <memory>
#include <math.h>
#include <stdlib.h>
#import "../stream-app/app/LicenseLifecycleCoordinator.h"
#import "LegacyLifecycle.h"
#import "../stream-app/app/LicenseManager.h"
static NSString *currentPath,*legacyPath;
static std::atomic<unsigned> performanceReads{0};
static NSDictionary *TLinkLicensePerformanceDictionary(){++performanceReads;return @{};}
static NSDictionary *TLinkLicenseStatusDictionary(){return @{@"state":@"valid",@"licensed":@YES};}
static void TLinkLicenseInvalidateCache(){}
static uint64_t TLinkLicenseGeneration(){return 7;}
static uint32_t fixtureRandom(uint32_t upper){assert(upper==4001);return 2000;}
@interface TLinkSocketClient:NSObject
+ (NSString *)requestTask:(int)task args:(NSArray *)args timeout:(NSTimeInterval)timeout;
@end
@implementation TLinkSocketClient
+ (NSString *)requestTask:(int)task args:(NSArray *)args timeout:(NSTimeInterval)timeout{(void)task;(void)args;(void)timeout;return @"0;;fixture";}
@end
#define arc4random_uniform fixtureRandom
#include "LifecycleUnderTest.inc"
#include "LifecycleLegacy.inc"
#undef arc4random_uniform

@interface FixtureManager:SCLicenseManager
@property(nonatomic,copy) NSDictionary *before;
@property(nonatomic,copy) NSDictionary *after;
@property(nonatomic,copy) SCLicenseLifecycleCompletion reply;
@property(nonatomic,readonly) NSUInteger localReads;
@property(nonatomic,readonly) NSUInteger requests;
@property BOOL firstReadOnMain;
@property NSUInteger holdRead;
@property NSUInteger faultRead;
@property int readFault;
@property int requestFault;
@property(nonatomic,strong) dispatch_semaphore_t entered;
@property(nonatomic,strong) dispatch_semaphore_t releaseRead;
@property(nonatomic,strong) dispatch_group_t resultWorker;
@end
// Only a benign stub is returned by the complete coordinator's original init.
@implementation SCLicenseManager
+ (instancetype)sharedManager{static SCLicenseManager *value;static dispatch_once_t once;dispatch_once(&once,^{value=[SCLicenseManager new];});return value;}
- (NSDictionary *)localStatus{return @{};}
- (void)activateLicenseKey:(NSString *)key completion:(SCLicenseLifecycleCompletion)completion{[self activateLicenseKey:key intent:@"fixture" completion:completion];}
- (void)activateLicenseKey:(NSString *)key intent:(NSString *)intent completion:(SCLicenseLifecycleCompletion)completion{(void)key;(void)intent;if(completion)completion(NO,@"fixture_activation");}
- (void)refreshLeaseWithCompletion:(SCLicenseLifecycleCompletion)completion{if(completion)completion(NO,@"fixture_refresh");}
- (void)deactivateLeaseWithCompletion:(SCLicenseLifecycleCompletion)completion{if(completion)completion(NO,@"fixture_deactivation");}
- (BOOL)removeLocalLease:(NSError **)error{(void)error;return YES;}
- (BOOL)repairDevicePublicKey:(NSError **)error{(void)error;return YES;}
@end
static void waitSemaphore(dispatch_semaphore_t value){assert(dispatch_semaphore_wait(value,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
@implementation FixtureManager {
    NSUInteger _localReads;
    NSUInteger _requests;
}
- (instancetype)init{self=[super init];if(self){_entered=dispatch_semaphore_create(0);_releaseRead=dispatch_semaphore_create(0);}return self;}
- (NSDictionary *)localStatus{
    NSUInteger index;NSDictionary *snapshot;
    @synchronized(self){index=++_localReads;if(index==1)_firstReadOnMain=[NSThread isMainThread];snapshot=(index>1?_after:_before);}
    if(index==self.holdRead){dispatch_semaphore_signal(self.entered);waitSemaphore(self.releaseRead);}
    if(index==self.faultRead){if(self.readFault==1)[NSException raise:@"Lifecycle" format:@"status"];if(self.readFault==2)throw std::runtime_error("status");}
    return snapshot;
}
- (void)refreshLeaseWithCompletion:(SCLicenseLifecycleCompletion)completion{
    @synchronized(self){++_requests;_reply=[completion copy];}
    if(_requestFault==1)[NSException raise:@"Lifecycle" format:@"request"];
    if(_requestFault==2)throw std::runtime_error("request");
    if(_requestFault==3){completion(YES,@"inline-success");[NSException raise:@"Lifecycle" format:@"after result"];}
    if(_requestFault==4||_requestFault==5){
        _resultWorker=dispatch_group_create();dispatch_group_async(_resultWorker,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{@autoreleasepool{completion(YES,@"async-success");}});
        waitSemaphore(_entered);
        if(_requestFault==4)[NSException raise:@"Lifecycle" format:@"after result claim"];
        throw std::runtime_error("after result claim");
    }
}
- (NSUInteger)localReads{@synchronized(self){return _localReads;}}
- (NSUInteger)requests{@synchronized(self){return _requests;}}
@end
@protocol FixtureLifecycle <NSObject>
- (void)refreshForTrigger:(NSString *)trigger force:(BOOL)force completion:(SCLicenseLifecycleCompletion)completion;
- (void)finishOperation:(NSString *)kind success:(BOOL)success message:(NSString *)message completion:(SCLicenseLifecycleCompletion)completion;
- (BOOL)beginOperation:(NSString *)kind completion:(SCLicenseLifecycleCompletion)completion;
- (void)appendRefreshHistoryEvent:(NSDictionary *)event;
- (BOOL)isRequestInFlight;
- (NSUInteger)transactions;
- (NSArray *)published;
- (void)activateLicenseKey:(NSString *)key completion:(SCLicenseLifecycleCompletion)completion;
- (void)deactivateWithCompletion:(SCLicenseLifecycleCompletion)completion;
- (BOOL)removeLocalLease:(NSError **)error;
- (BOOL)repairDevicePublicKey:(NSError **)error;
@end
#define PRIVATE_LIFECYCLE_METHODS \
- (void)refreshForTrigger:(NSString *)trigger force:(BOOL)force completion:(SCLicenseLifecycleCompletion)completion; \
- (void)finishOperation:(NSString *)kind success:(BOOL)success message:(NSString *)message completion:(SCLicenseLifecycleCompletion)completion; \
- (BOOL)beginOperation:(NSString *)kind completion:(SCLicenseLifecycleCompletion)completion; \
- (void)appendRefreshHistoryEvent:(NSDictionary *)event;
@interface SCLicenseLifecycleCoordinator(FixturePrivate)
PRIVATE_LIFECYCLE_METHODS
@end
@interface SCLegacyLifecycleCoordinator(FixturePrivate)
PRIVATE_LIFECYCLE_METHODS
@end
#undef PRIVATE_LIFECYCLE_METHODS
@interface CurrentLifecycle:SCLicenseLifecycleCoordinator<FixtureLifecycle>
@property NSUInteger transactions;
@property(nonatomic,strong) NSMutableArray *published;
@property BOOL holdPolicy;
@property BOOL holdBackoff;
@property(nonatomic,strong) dispatch_semaphore_t policyEntered;
@property(nonatomic,strong) dispatch_semaphore_t releasePolicy;
- (void)drainRefreshDecisions;
@end
@interface LegacyLifecycle:SCLegacyLifecycleCoordinator<FixtureLifecycle>
@property NSUInteger transactions;
@property(nonatomic,strong) NSMutableArray *published;
@end
@implementation CurrentLifecycle
- (uint64_t)nowMilliseconds{return 1000000;}
- (void)drainRefreshDecisions{dispatch_sync(self.refreshDecisionQueue,^{});}
- (void)updateDiagnostics:(NSDictionary *)values refreshHistoryEvent:(NSDictionary *)event{
    if(values.count||event.count){@synchronized(self){++_transactions;}}
    [super updateDiagnostics:values refreshHistoryEvent:event];
}
- (void)publishLicenseChange:(NSString *)reason{if(!_published)_published=[NSMutableArray array];[_published addObject:reason];}
- (BOOL)automaticRefreshNeededForStatus:(NSDictionary *)status reason:(NSString **)reason{
    BOOL result=[super automaticRefreshNeededForStatus:status reason:reason];
    if(_holdPolicy){dispatch_semaphore_signal(_policyEntered);waitSemaphore(_releasePolicy);}return result;
}
- (BOOL)backoffAllowsAttempt:(NSString **)reason{
    BOOL result=[super backoffAllowsAttempt:reason];
    if(_holdBackoff){dispatch_semaphore_signal(_policyEntered);waitSemaphore(_releasePolicy);}return result;
}
@end
@implementation LegacyLifecycle
- (uint64_t)nowMilliseconds{return 1000000;}
- (void)updateDiagnostics:(NSDictionary *)values{if(values.count)++_transactions;[super updateDiagnostics:values];}
- (void)publishLicenseChange:(NSString *)reason{if(!_published)_published=[NSMutableArray array];[_published addObject:reason];}
@end
static void pump(){CFRunLoopRunInMode(kCFRunLoopDefaultMode,.001,false);}
template<typename Predicate>static void await(Predicate predicate){const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;while(!predicate()&&CFAbsoluteTimeGetCurrent()<end)pump();assert(predicate());}
static id<FixtureLifecycle> coordinator(BOOL legacy,FixtureManager *manager){
    id<FixtureLifecycle> value=legacy?(id<FixtureLifecycle>)[LegacyLifecycle new]:(id<FixtureLifecycle>)[CurrentLifecycle new];
    [(NSObject *)value setValue:manager forKey:@"manager"];return value;
}
static NSString *pathFor(BOOL legacy){return legacy?legacyPath:currentPath;}
static NSDictionary *fileState(BOOL legacy){return [NSDictionary dictionaryWithContentsOfFile:pathFor(legacy)]?:@{};}
static void prepare(BOOL legacy,BOOL backoff){
    assert(([@{@"untouched":@7,@"next_attempt_at_ms":@(backoff?1010000:0),@"consecutive_failures":@0} writeToFile:pathFor(legacy) atomically:YES]));
}
static FixtureManager *managerFor(unsigned kind){
    FixtureManager *manager=[FixtureManager new];NSTimeInterval now=[[NSDate date] timeIntervalSince1970];
    NSString *state=kind==2?@"invalid":kind==3?@"offline_grace":@"valid";
    NSTimeInterval expiry=kind==1?now+50000:kind==4?0:now+3600;
    manager.before=@{@"state":state,@"expires_at":@(expiry),@"lease_expires_at":@100,@"license_expires_at":@10000};
    manager.after=@{@"state":@"valid",@"lease_expires_at":@200,@"license_expires_at":@10000};
    return manager;
}
struct Reply {
    std::atomic<unsigned> calls{0};
    BOOL success=NO;
    NSString *message=nil;
};
static SCLicenseLifecycleCompletion completionFor(std::shared_ptr<Reply> result){return ^(BOOL success,NSString *message){assert([NSThread isMainThread]);result->success=success;result->message=[message copy];++result->calls;};}
static NSDictionary *scenario(BOOL legacy,unsigned kind,BOOL force,BOOL success){
    prepare(legacy,kind==5);FixtureManager *manager=managerFor(kind);id<FixtureLifecycle> value=coordinator(legacy,manager);auto result=std::make_shared<Reply>();
    auto notifications=std::make_shared<std::atomic<unsigned>>(0);
    id observer=[[NSNotificationCenter defaultCenter] addObserverForName:legacy?SCLegacyLifecycleDidChangeNotification:SCLicenseLifecycleDidChangeNotification object:value queue:nil usingBlock:^(NSNotification *notification){(void)notification;++*notifications;}];
    [value refreshForTrigger:@"fixture" force:force completion:completionFor(result)];
    await([&]{return manager.requests>0||result->calls.load()>0;});
    BOOL attempted=manager.requests>0;
    if(attempted)manager.reply(success,success?@"license_refreshed":@"network-failed");
    await([&]{return result->calls.load()==1;});assert(![value isRequestInFlight]);
    NSDictionary *state=fileState(legacy);NSMutableDictionary *normalized=[state mutableCopy];
    if(!attempted){[normalized removeObjectForKey:@"request_in_flight"];[normalized removeObjectForKey:@"operation"];}
    NSDictionary *output=@{@"state":normalized,@"success":@(result->success),@"message":result->message?:@"",@"published":[value published]?:@[],@"reads":@(manager.localReads),@"requests":@(manager.requests)};
    if(attempted)await([&]{return notifications->load()==2;});else pump();
    assert(notifications->load()==(attempted?2U:0U));[[NSNotificationCenter defaultCenter] removeObserver:observer];
    assert([value transactions]==(attempted?(legacy?5U:3U):1U));assert(manager.firstReadOnMain==legacy);manager.reply=nil;return output;
}
static void parityCases(){
    for(unsigned kind=0;kind<6;++kind){
        for(unsigned force=0;force<2;++force){
            for(unsigned success=0;success<2;++success){
                @autoreleasepool{NSDictionary *old=scenario(YES,kind,force,success);NSDictionary *current=scenario(NO,kind,force,success);if(![old isEqual:current])NSLog(@"lifecycle parity kind=%u force=%u success=%u old=%@ current=%@",kind,force,success,old,current);assert([old isEqual:current]);}
            }
        }
    }
}
static void coalescingCases(){
    for(unsigned kind=0;kind<3;++kind){
        @autoreleasepool{
            prepare(NO,NO);FixtureManager *manager=managerFor(kind==0?0:1);manager.holdRead=1;
            id<FixtureLifecycle> value=coordinator(NO,manager);auto result=std::make_shared<Reply>();
            [value refreshForTrigger:@"leader" force:NO completion:completionFor(result)];waitSemaphore(manager.entered);
            assert([value isRequestInFlight]&&manager.localReads==1);
            std::vector<std::thread> callers;
            for(unsigned t=0;t<8;++t)callers.emplace_back([value,result,kind,t]{@autoreleasepool{for(unsigned n=0;n<8;++n)[value refreshForTrigger:@"follower" force:(kind==2&&t==0&&n==0) completion:completionFor(result)];}});
            for(auto &thread:callers){thread.join();}
            assert(manager.localReads==1&&manager.requests==0);
            dispatch_semaphore_signal(manager.releaseRead);await([&]{return manager.requests>0||result->calls.load()>0;});
            BOOL attempted=kind!=1;if(attempted){assert(manager.requests==1);manager.reply(YES,@"license_refreshed");}
            await([&]{return result->calls.load()==65;});assert(manager.localReads==(attempted?2U:1U)&&![value isRequestInFlight]);
            assert([value transactions]==(attempted?3U:1U));manager.reply=nil;
        }
    }
    for(unsigned gate=0;gate<2;++gate){
        @autoreleasepool{
            prepare(NO,gate==1);FixtureManager *manager=managerFor(gate==0?1:0);CurrentLifecycle *value=(CurrentLifecycle *)coordinator(NO,manager);
            value.holdPolicy=gate==0;value.holdBackoff=gate==1;value.policyEntered=dispatch_semaphore_create(0);value.releasePolicy=dispatch_semaphore_create(0);
            auto result=std::make_shared<Reply>();[value refreshForTrigger:@"automatic" force:NO completion:completionFor(result)];waitSemaphore(value.policyEntered);
            [value refreshForTrigger:@"manual" force:YES completion:completionFor(result)];dispatch_semaphore_signal(value.releasePolicy);
            await([&]{return manager.requests==1;});manager.reply(YES,@"license_refreshed");await([&]{return result->calls.load()==2;});
            assert([fileState(NO)[@"last_decision"] isEqualToString:@"manual_force_refresh"]&&manager.localReads==2);manager.reply=nil;
        }
    }
}
static void staleAndBusyCases(){
    @autoreleasepool{
        prepare(NO,NO);FixtureManager *manager=managerFor(0);id<FixtureLifecycle> value=coordinator(NO,manager);auto first=std::make_shared<Reply>();
        [value refreshForTrigger:@"first" force:YES completion:completionFor(first)];await([&]{return manager.requests==1;});
        SCLicenseLifecycleCompletion oldReply=manager.reply;oldReply(YES,@"first-ok");await([&]{return first->calls.load()==1;});
        auto next=std::make_shared<Reply>();[value refreshForTrigger:@"next" force:YES completion:completionFor(next)];await([&]{return manager.requests==2;});
        NSDictionary *before=fileState(NO);NSUInteger writes=[value transactions],reads=manager.localReads;
        for(unsigned n=0;n<16;++n)oldReply(n%2,@"late");
        assert([value isRequestInFlight]&&next->calls.load()==0&&[before isEqual:fileState(NO)]&&[value transactions]==writes&&manager.localReads==reads);
        manager.reply(NO,@"next-failed");await([&]{return next->calls.load()==1;});assert(![value isRequestInFlight]);manager.reply=nil;oldReply=nil;
    }
    @autoreleasepool{
        prepare(NO,NO);FixtureManager *manager=managerFor(0);manager.holdRead=2;id<FixtureLifecycle> value=coordinator(NO,manager);auto result=std::make_shared<Reply>();
        [value refreshForTrigger:@"first-result" force:YES completion:completionFor(result)];await([&]{return manager.requests==1;});
        SCLicenseLifecycleCompletion reply=manager.reply;std::thread first([reply]{@autoreleasepool{reply(YES,@"first");}});waitSemaphore(manager.entered);
        const NSUInteger writes=[value transactions];reply(NO,@"duplicate-during-publication");assert([value transactions]==writes&&[value isRequestInFlight]);
        dispatch_semaphore_signal(manager.releaseRead);first.join();await([&]{return result->calls.load()==1;});
        assert(result->success&&manager.localReads==2&&[value transactions]==3&&[value published].count==1);manager.reply=nil;
    }
    @autoreleasepool{
        prepare(NO,NO);FixtureManager *manager=managerFor(0);id<FixtureLifecycle> value=coordinator(NO,manager);assert([value beginOperation:@"activate" completion:nil]);
        auto result=std::make_shared<Reply>();[value refreshForTrigger:@"busy" force:NO completion:completionFor(result)];await([&]{return result->calls.load()==1;});
        assert(!result->success&&[result->message isEqualToString:@"license_request_in_progress"]&&manager.localReads==0&&manager.requests==0);
        [value finishOperation:@"activate" success:NO message:@"fixture" completion:nil];
    }
}
static void faultCases(){
    for(unsigned site=0;site<3;++site){
        for(int kind=1;kind<=2;++kind){
            @autoreleasepool{
                prepare(NO,NO);FixtureManager *manager=managerFor(0);id<FixtureLifecycle> value=coordinator(NO,manager);auto result=std::make_shared<Reply>();
                if(site==1)manager.requestFault=kind;else{manager.faultRead=site==0?1:2;manager.readFault=kind;}
                [value refreshForTrigger:@"fault" force:YES completion:completionFor(result)];
                if(site==2){await([&]{return manager.requests==1;});manager.reply(YES,@"post-status-fault");}
                await([&]{return result->calls.load()==1;});assert(![value isRequestInFlight]&&!result->success&&[result->message isEqualToString:@"license_refresh_exception"]);
                assert([fileState(NO)[@"last_error"] isEqualToString:@"license_refresh_exception"]);
                SCLicenseLifecycleCompletion late=manager.reply;NSUInteger writes=[value transactions];if(late)late(YES,@"late");assert([value transactions]==writes);
                manager.requestFault=0;manager.faultRead=0;manager.readFault=0;auto recovery=std::make_shared<Reply>();NSUInteger previous=manager.requests;
                [value refreshForTrigger:@"recovery" force:YES completion:completionFor(recovery)];await([&]{return manager.requests==previous+1;});manager.reply(YES,@"recovered");await([&]{return recovery->calls.load()==1;});
                assert(recovery->success&&![value isRequestInFlight]);manager.reply=nil;late=nil;
            }
        }
    }
    @autoreleasepool{
        prepare(NO,NO);FixtureManager *manager=managerFor(0);manager.requestFault=3;id<FixtureLifecycle> value=coordinator(NO,manager);auto result=std::make_shared<Reply>();
        [value refreshForTrigger:@"inline" force:YES completion:completionFor(result)];await([&]{return result->calls.load()==1;});
        assert(result->success&&![(NSObject *)value valueForKey:@"refreshOperationIdentity"]&&[fileState(NO)[@"last_result"] isEqualToString:@"success"]);manager.reply=nil;
    }
    for(int fault=4;fault<=5;++fault){
        @autoreleasepool{
            prepare(NO,NO);FixtureManager *manager=managerFor(0);manager.holdRead=2;manager.requestFault=fault;
            CurrentLifecycle *value=(CurrentLifecycle *)coordinator(NO,manager);auto result=std::make_shared<Reply>();
            [value refreshForTrigger:@"claimed-result" force:YES completion:completionFor(result)];await([&]{return manager.localReads==2;});
            [value drainRefreshDecisions];assert([value isRequestInFlight]&&result->calls.load()==0);
            dispatch_semaphore_signal(manager.releaseRead);assert(dispatch_group_wait(manager.resultWorker,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
            await([&]{return result->calls.load()==1;});assert(result->success&&![value isRequestInFlight]&&[fileState(NO)[@"last_result"] isEqualToString:@"success"]);manager.reply=nil;
        }
    }
}
static void otherOperationsCases(){
    for(unsigned operation=0;operation<2;++operation){
        NSDictionary *old;
        for(unsigned variant=0;variant<2;++variant){
            BOOL legacy=variant==0;prepare(legacy,NO);id<FixtureLifecycle> value=coordinator(legacy,managerFor(0));auto result=std::make_shared<Reply>();
            if(operation==0)[value activateLicenseKey:@"fixture" completion:completionFor(result)];else [value deactivateWithCompletion:completionFor(result)];
            await([&]{return result->calls.load()==1;});assert(![value isRequestInFlight]&&[value transactions]==3);
            NSDictionary *snapshot=@{@"file":fileState(legacy),@"message":result->message?:@"",@"success":@(result->success)};
            if(legacy)old=snapshot;else assert([old isEqual:snapshot]);
        }
    }
    @autoreleasepool{
        prepare(NO,NO);FixtureManager *manager=managerFor(0);manager.holdRead=1;id<FixtureLifecycle> value=coordinator(NO,manager);auto result=std::make_shared<Reply>();
        [value refreshForTrigger:@"held" force:YES completion:completionFor(result)];waitSemaphore(manager.entered);NSError *error=nil;
        assert(![value removeLocalLease:&error]&&error.code==70);error=nil;assert(![value repairDevicePublicKey:&error]&&error.code==409);
        auto busy=std::make_shared<Reply>();[value activateLicenseKey:@"busy" completion:completionFor(busy)];await([&]{return busy->calls.load()==1;});assert(!busy->success&&[value isRequestInFlight]);
        dispatch_semaphore_signal(manager.releaseRead);await([&]{return manager.requests==1;});manager.reply(YES,@"done");await([&]{return result->calls.load()==1;});
        assert([value removeLocalLease:nullptr]&&[value repairDevicePublicKey:nullptr]);manager.reply=nil;
    }
}
static void historyCases(){
    NSDictionary *old;
    for(unsigned variant=0;variant<2;++variant){
        BOOL legacy=variant==0;
        prepare(legacy,NO);id<FixtureLifecycle> value=coordinator(legacy,managerFor(0));const unsigned before=performanceReads;
        for(unsigned n=0;n<60;++n)[value appendRefreshHistoryEvent:@{@"id":@(n)}];
        assert(performanceReads.load()-before==(legacy?60U:0U));
        NSDictionary *state=fileState(legacy);assert([state[@"refresh_history"] count]==20);
        if(legacy)old=state;else assert([old isEqual:state]);
    }
    prepare(NO,NO);id<FixtureLifecycle> small=coordinator(NO,managerFor(0));std::vector<std::thread> smallThreads;
    for(unsigned t=0;t<8;++t)smallThreads.emplace_back([small,t]{@autoreleasepool{for(unsigned n=0;n<2;++n)[small appendRefreshHistoryEvent:@{@"id":@(t*2+n)}];}});
    for(auto &thread:smallThreads){thread.join();}
    assert([fileState(NO)[@"refresh_history"] count]==16);
    prepare(NO,NO);id<FixtureLifecycle> value=coordinator(NO,managerFor(0));std::vector<std::thread> threads;
    for(unsigned t=0;t<8;++t)threads.emplace_back([value,t]{@autoreleasepool{for(unsigned n=0;n<16;++n)[value appendRefreshHistoryEvent:@{@"id":@(t*16+n)}];}});
    for(auto &thread:threads){thread.join();}
    NSArray *history=fileState(NO)[@"refresh_history"];
    NSMutableSet *ids=[NSMutableSet set];for(NSDictionary *event in history)[ids addObject:event[@"id"]];
    assert(history.count==20&&ids.count==20&&[value transactions]==128);
}
int main(){@autoreleasepool{
    setvbuf(stdout,nullptr,_IONBF,0);
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-lifecycle-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nullptr]);
    currentPath=[directory stringByAppendingPathComponent:@"current.plist"];legacyPath=[directory stringByAppendingPathComponent:@"legacy.plist"];
    puts("License lifecycle Foundation: complete current/frozen coordinator, real plist IO and controlled manager/authority publication");
    parityCases();puts("License lifecycle: coalesced decisions and late manual force");
    coalescingCases();puts("License lifecycle: stale/duplicate results and busy operation gates");
    staleAndBusyCases();puts("License lifecycle: NS/C++ provider/result faults and ownership recovery");
    faultCases();otherOperationsCases();puts("License lifecycle: serial/concurrent history and repeated lifecycles");historyCases();
    for(unsigned n=0;n<128;++n){@autoreleasepool{(void)scenario(NO,0,YES,n%2);}}
    pump();assert([[NSFileManager defaultManager] removeItemAtPath:directory error:nullptr]);
    puts("License lifecycle passed: 24 frozen decision/result graphs, 5-to-3 attempt and 1-to-1 skip diagnostic transactions, 65-caller single decisions, manual force during policy/backoff, stale results/new-flight protection, busy/NS/C++/inline result recovery, exact 20-entry history, concurrent append and 128 lifecycles. HTTP, signed persistence and device performance remain unqualified.");
}return 0;}
