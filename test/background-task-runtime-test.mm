#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>

typedef void (^RefreshReply)(BOOL, NSString *);
typedef RefreshReply SCLicenseLifecycleCompletion;
@protocol SCLicenseRefreshSubscription <NSObject>
- (void)cancel;
@end
#include "BackgroundRefreshSubscriber.inc"
static std::atomic<unsigned> liveTasks{0};
static BOOL expireOnInstall=NO;
@interface BGTask : NSObject
@property(nonatomic,copy) dispatch_block_t expirationHandler;
@property(nonatomic,readonly) unsigned completions;
@property(nonatomic,readonly) BOOL success;
- (void)setTaskCompletedWithSuccess:(BOOL)success;
@end
@implementation BGTask {
    dispatch_block_t _expirationHandler;
    unsigned _completions;
    BOOL _success;
}
- (instancetype)init {self=[super init];if(self)++liveTasks;return self;}
- (void)dealloc {--liveTasks;}
- (dispatch_block_t)expirationHandler {@synchronized(self){return _expirationHandler;}}
- (void)setExpirationHandler:(dispatch_block_t)handler {
    // Deliver during publication, then install the old value to test the post-install check.
    if(handler && expireOnInstall)handler();
    @synchronized(self){_expirationHandler=[handler copy];}
}
- (void)setTaskCompletedWithSuccess:(BOOL)success {@synchronized(self){++_completions;_success=success;}}
- (unsigned)completions {@synchronized(self){return _completions;}}
- (BOOL)success {@synchronized(self){return _success;}}
@end
@interface BGAppRefreshTaskRequest : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,strong) NSDate *earliestBeginDate;
- (instancetype)initWithIdentifier:(NSString *)identifier;
@end
@implementation BGAppRefreshTaskRequest
- (instancetype)initWithIdentifier:(NSString *)identifier {self=[super init];if(self)_identifier=[identifier copy];return self;}
@end
@interface BGProcessingTaskRequest : BGAppRefreshTaskRequest
@property BOOL requiresNetworkConnectivity;
@property BOOL requiresExternalPower;
@end
@implementation BGProcessingTaskRequest
@end
@interface BGTaskScheduler : NSObject
@property(nonatomic,strong) NSMutableArray *requests;
+ (instancetype)sharedScheduler;
- (BOOL)registerForTaskWithIdentifier:(NSString *)identifier usingQueue:(dispatch_queue_t)queue launchHandler:(void (^)(BGTask *))handler;
- (void)cancelTaskRequestWithIdentifier:(NSString *)identifier;
- (BOOL)submitTaskRequest:(BGAppRefreshTaskRequest *)request error:(NSError **)error;
@end
@implementation BGTaskScheduler
+ (instancetype)sharedScheduler {static BGTaskScheduler *value;static dispatch_once_t once;dispatch_once(&once,^{value=[BGTaskScheduler new];value.requests=[NSMutableArray array];});return value;}
- (BOOL)registerForTaskWithIdentifier:(NSString *)identifier usingQueue:(dispatch_queue_t)queue launchHandler:(void (^)(BGTask *))handler {(void)identifier;(void)queue;(void)handler;return YES;}
- (void)cancelTaskRequestWithIdentifier:(NSString *)identifier {(void)identifier;}
- (BOOL)submitTaskRequest:(BGAppRefreshTaskRequest *)request error:(NSError **)error {(void)error;[_requests addObject:request];return YES;}
@end
@interface SCLicenseLifecycleCoordinator : NSObject
@property(nonatomic,copy) RefreshReply reply;
@property unsigned calls;
@property int fault;
@property unsigned retirements;
@property BOOL subscriptionUnavailable;
@property(nonatomic,copy) dispatch_block_t beforeSubscriptionReturn;
- (void)performBackgroundRefreshWithCompletion:(RefreshReply)completion;
- (id<SCLicenseRefreshSubscription>)subscribeToBackgroundRefreshWithCompletion:(RefreshReply)completion;
@end
@implementation SCLicenseLifecycleCoordinator
- (void)performBackgroundRefreshWithCompletion:(RefreshReply)completion {
    ++_calls;_reply=[completion copy];
    if(_fault==1)[NSException raise:@"Fixture" format:@"refresh"];
    if(_fault==2)throw std::runtime_error("refresh");
}
- (id<SCLicenseRefreshSubscription>)subscribeToBackgroundRefreshWithCompletion:(RefreshReply)completion {
    if(_subscriptionUnavailable)return nil;
    __weak SCLicenseLifecycleCoordinator *weakSelf=self;
    SCBackgroundRefreshSubscription *subscription=[[SCBackgroundRefreshSubscription alloc] initWithCompletion:completion retirement:^{SCLicenseLifecycleCoordinator *owner=weakSelf;owner.retirements=owner.retirements+1;}];
    @try {
        try {
            [self performBackgroundRefreshWithCompletion:^(BOOL success,NSString *detail){[subscription deliverSuccess:success message:detail];}];
            if(_beforeSubscriptionReturn)_beforeSubscriptionReturn();
        } catch (...) {[subscription cancel];throw;}
    } @catch(NSException *exception){[subscription cancel];@throw exception;}
    return subscription;
}
@end
@interface SCStreamSupervisor : NSObject
@property(nonatomic,copy) RefreshReply reply;
@property(nonatomic,copy) RefreshReply queuedReply;
@property(nonatomic,copy) BOOL (^startPermission)(void);
@property BOOL holdStart;
@property unsigned calls;
@property int fault;
- (void)ensureServiceWithCompletion:(RefreshReply)completion;
- (void)ensureServiceWithStartPermission:(BOOL (^)(void))startPermission completion:(RefreshReply)completion;
- (void)releaseStart;
@end
@implementation SCStreamSupervisor
- (void)ensureServiceWithCompletion:(RefreshReply)completion {
    ++_calls;_reply=[completion copy];
    if(_fault==1)[NSException raise:@"Fixture" format:@"ensure"];
    if(_fault==2)throw std::runtime_error("ensure");
}
- (void)ensureServiceWithStartPermission:(BOOL (^)(void))startPermission completion:(RefreshReply)completion {
    if(_holdStart){_startPermission=[startPermission copy];_queuedReply=[completion copy];return;}
    if(!startPermission||startPermission())[self ensureServiceWithCompletion:completion];
    else completion(NO,@"supervisor_ensure_cancelled_before_start");
}
- (void)releaseStart {
    BOOL (^permission)(void)=_startPermission;RefreshReply completion=_queuedReply;
    _startPermission=nil;_queuedReply=nil;assert(permission&&completion);
    if(permission())[self ensureServiceWithCompletion:completion];
    else completion(NO,@"supervisor_ensure_cancelled_before_start");
}
@end
#import "../stream-app/app/BackgroundServiceScheduler.h"
// Same public surface, with a separate class name for the frozen implementation.
@interface SCLegacyBackgroundScheduler : NSObject
- (instancetype)initWithSupervisor:(SCStreamSupervisor *)supervisor licenseCoordinator:(SCLicenseLifecycleCoordinator *)coordinator;
- (void)registerTasks;
- (void)scheduleRecoveryTasksForReason:(NSString *)reason;
@end

@interface TimerRecord : NSObject
@property(nonatomic,strong) dispatch_source_t source;
@property(nonatomic,copy) dispatch_block_t handler;
@property(nonatomic,strong) dispatch_group_t retired;
@property BOOL resumed;
@property BOOL cancelled;
@property unsigned arms;
@end
@implementation TimerRecord
@end
static NSMutableDictionary<NSValue *,TimerRecord *> *timers;
static TimerRecord *lastTimer;
static NSMutableArray *legacyTimers;
static bool createFailure=false,realTimer=false;
static std::atomic<unsigned> created{0},cancelled{0};
static NSValue *timerKey(dispatch_source_t source){return [NSValue valueWithPointer:(__bridge const void *)source];}
static TimerRecord *recordFor(dispatch_source_t source){@synchronized(timers){return timers[timerKey(source)];}}
static dispatch_source_t fixtureCreate(dispatch_source_type_t type,uintptr_t handle,uintptr_t mask,dispatch_queue_t queue){
    if(createFailure)return nullptr;
    dispatch_source_t source=dispatch_source_create(type,handle,mask,queue);assert(source);
    TimerRecord *record=[TimerRecord new];record.source=source;record.retired=dispatch_group_create();
    dispatch_group_enter(record.retired);dispatch_group_t retired=record.retired;
    dispatch_source_set_cancel_handler(source,^{dispatch_group_leave(retired);});
    @synchronized(timers){timers[timerKey(source)]=record;lastTimer=record;}
    ++created;return source;
}
static void fixtureHandler(dispatch_source_t source,dispatch_block_t handler){TimerRecord *record=recordFor(source);assert(record);@synchronized(record){record.handler=handler;}dispatch_source_set_event_handler(source,handler);}
static void fixtureResume(dispatch_source_t source){TimerRecord *record=recordFor(source);assert(record&&!record.resumed);record.resumed=YES;dispatch_resume(source);}
static void fixtureCancel(dispatch_source_t source){TimerRecord *record=recordFor(source);assert(record&&record.resumed&&!record.cancelled);record.cancelled=YES;++cancelled;dispatch_source_cancel(source);}
static void fixtureTimer(dispatch_source_t source,dispatch_time_t start,uint64_t interval,uint64_t leeway){
    TimerRecord *record=recordFor(source);assert(record&&!record.cancelled&&interval==DISPATCH_TIME_FOREVER&&leeway==0);
    if(start!=DISPATCH_TIME_FOREVER)++record.arms;
    dispatch_source_set_timer(source,realTimer&&start!=DISPATCH_TIME_FOREVER?dispatch_time(DISPATCH_TIME_NOW,1000000):DISPATCH_TIME_FOREVER,interval,leeway);
}
#define dispatch_source_set_event_handler fixtureHandler
#define dispatch_source_cancel fixtureCancel
#define dispatch_source_set_timer fixtureTimer
#include "../shared/TLinkBackgroundTaskRun.h"
#define dispatch_source_create fixtureCreate
#define dispatch_resume fixtureResume
#include "BackgroundTaskUnderTest.inc"
#undef dispatch_source_set_event_handler
#undef dispatch_source_cancel
#undef dispatch_source_set_timer
#undef dispatch_source_create
#undef dispatch_resume
static void fixtureAfter(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block){(void)when;(void)queue;[legacyTimers addObject:[block copy]];}
#define dispatch_after fixtureAfter
#include "BackgroundTaskLegacy.inc"
#undef dispatch_after

@protocol TestScheduler <NSObject>
- (void)handleTask:(BGTask *)task kind:(NSString *)kind;
- (void)registerTasks;
- (void)scheduleRecoveryTasksForReason:(NSString *)reason;
- (NSDictionary *)snapshot;
- (NSArray *)events;
@end
@interface CurrentScheduler : SCBackgroundServiceScheduler <TestScheduler>
@property(nonatomic,strong) NSMutableArray *updates;
@end
@implementation CurrentScheduler
- (void)updateDiagnostics:(NSDictionary *)values {@synchronized(self){if(!_updates)_updates=[NSMutableArray array];[_updates addObject:[values copy]];}}
- (NSDictionary *)snapshot {@synchronized(self){NSMutableDictionary *result=[NSMutableDictionary dictionary];for(NSDictionary *event in _updates)[result addEntriesFromDictionary:event];return result;}}
- (NSArray *)events {@synchronized(self){return [_updates copy];}}
@end
@interface LegacyScheduler : SCLegacyBackgroundScheduler <TestScheduler>
@property(nonatomic,strong) NSMutableArray *updates;
@end
@implementation LegacyScheduler
- (void)updateDiagnostics:(NSDictionary *)values {if(!_updates)_updates=[NSMutableArray array];[_updates addObject:[values copy]];}
- (NSDictionary *)snapshot {NSMutableDictionary *result=[NSMutableDictionary dictionary];for(NSDictionary *event in _updates)[result addEntriesFromDictionary:event];return result;}
- (NSArray *)events {return [_updates copy];}
@end
static id<TestScheduler> scheduler(BOOL legacy,SCStreamSupervisor *supervisor,SCLicenseLifecycleCoordinator *coordinator){
    if(legacy)return [[LegacyScheduler alloc] initWithSupervisor:supervisor licenseCoordinator:coordinator];
    return [[CurrentScheduler alloc] initWithSupervisor:supervisor licenseCoordinator:coordinator];
}
static void pump(){CFRunLoopRunInMode(kCFRunLoopDefaultMode,.001,false);}
static void reset(){
    NSArray *records;@synchronized(timers){records=[timers.allValues copy];}
    for(TimerRecord *record in records){assert(record.cancelled);assert(dispatch_group_wait(record.retired,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    assert(created.load()==cancelled.load());
    @synchronized(timers){[timers removeAllObjects];lastTimer=nil;}
    [legacyTimers removeAllObjects];[[BGTaskScheduler sharedScheduler].requests removeAllObjects];
    createFailure=realTimer=false;expireOnInstall=NO;pump();
}
static void expire(BGTask *task){dispatch_block_t handler=task.expirationHandler;assert(handler);handler();}
static void watchdog(BOOL legacy){
    dispatch_block_t handler=legacy?legacyTimers.lastObject:lastTimer.handler;assert(handler);
    if(!legacy)assert(lastTimer.arms==1&&!lastTimer.cancelled);handler();
}
static NSDictionary *outcome(BOOL legacy,BOOL processing,BOOL missing,BOOL licenseOK,BOOL running,unsigned terminal){
    SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=missing?nil:[SCLicenseLifecycleCoordinator new];
    id<TestScheduler> value=scheduler(legacy,supervisor,coordinator);[value registerTasks];
    BGTask *task=[BGTask new];[value handleTask:task kind:processing?@"processing":@"refresh"];
    assert(coordinator.calls==(missing?0U:1U));
    if(terminal==1)expire(task);
    else if(terminal==2)watchdog(legacy);
    else {
        if(coordinator)coordinator.reply(licenseOK,@"license-detail");
        assert(supervisor.calls==1);supervisor.reply(running,@"probe-detail");
    }
    assert(task.completions==1);if(!legacy)assert(!task.expirationHandler&&lastTimer.cancelled);
    NSDictionary *state=[value snapshot];
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    for(NSString *field in @[@"last_completed_kind",@"last_result",@"last_detail",@"last_license_result",@"last_license_detail"])
        if(state[field])result[field]=state[field];
    result[@"success"]=@(task.success);
    BGAppRefreshTaskRequest *request=[BGTaskScheduler sharedScheduler].requests.lastObject;
    result[@"request"]=request.identifier;result[@"request_class"]=NSStringFromClass(request.class);
    if([request isKindOfClass:[BGProcessingTaskRequest class]]){
        BGProcessingTaskRequest *processingRequest=(BGProcessingTaskRequest *)request;
        assert(!processingRequest.requiresNetworkConnectivity&&!processingRequest.requiresExternalPower);
    }
    // Deliberately drain the frozen retained timeout and clear its expiration cycle.
    if(legacy){watchdog(YES);task.expirationHandler=nil;}
    coordinator.reply=nil;supervisor.reply=nil;return result;
}
static void parityCases(){
    for(unsigned processing=0;processing<2;++processing){
        for(unsigned missing=0;missing<2;++missing){
            for(unsigned license=0;license<2;++license){
                for(unsigned running=0;running<2;++running){
                    for(unsigned terminal=0;terminal<3;++terminal){
                        @autoreleasepool{
                            NSDictionary *old=outcome(YES,processing,missing,license,running,terminal);reset();
                            NSDictionary *current=outcome(NO,processing,missing,license,running,terminal);
                            assert([old isEqual:current]);reset();
                        }
                    }
                }
            }
        }
    }
}
static void lateCases(){
    for(unsigned terminal=0;terminal<2;++terminal){
        for(unsigned stage=0;stage<2;++stage){
            @autoreleasepool{
                SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
                id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
                dispatch_block_t lateExpiration=task.expirationHandler,lateWatchdog=lastTimer.handler;
                if(stage)coordinator.reply(YES,@"first-license");
                if(terminal)watchdog(NO);else expire(task);
                NSDictionary *before=[value snapshot];NSUInteger updates=[value events].count;
                for(unsigned n=0;n<8;++n){coordinator.reply(YES,@"late-license");if(stage)supervisor.reply(YES,@"late-probe");lateExpiration();lateWatchdog();}
                assert(supervisor.calls==stage&&task.completions==1&&[before isEqual:[value snapshot]]&&[value events].count==updates);
                assert(!task.expirationHandler&&lastTimer.cancelled);
                coordinator.reply=nil;supervisor.reply=nil;lateExpiration=nil;lateWatchdog=nil;
            }
            reset();
        }
    }
    @autoreleasepool{
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"processing"];
        coordinator.reply(NO,@"failed-license");coordinator.reply(YES,@"duplicate-license");assert(supervisor.calls==1);
        supervisor.reply(YES,@"first-probe");NSDictionary *before=[value snapshot];supervisor.reply(NO,@"duplicate-probe");
        assert(!task.success&&task.completions==1&&[before isEqual:[value snapshot]]);coordinator.reply=nil;supervisor.reply=nil;
    }
    reset();
}
static void faultCases(){
    for(unsigned site=0;site<2;++site){
        for(int fault=1;fault<=2;++fault){
            @autoreleasepool{
                SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
                if(site)supervisor.fault=fault;else coordinator.fault=fault;
                id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
                if(site)coordinator.reply(YES,@"license");assert(task.completions==1&&!task.success&&lastTimer.cancelled&&!task.expirationHandler);
                NSString *expected=site?@"background_streamd_ensure_exception":@"background_task_setup_or_refresh_exception";
                assert([[value snapshot][@"last_detail"] isEqualToString:expected]);
                coordinator.fault=0;supervisor.fault=0;NSDictionary *before=[value snapshot];
                coordinator.reply(YES,@"late");if(site)supervisor.reply(YES,@"late");
                assert(task.completions==1&&[before isEqual:[value snapshot]]&&supervisor.calls==site);
                coordinator.reply=nil;supervisor.reply=nil;
            }
            reset();
        }
    }
    @autoreleasepool{
        createFailure=true;SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
        assert(task.completions==1&&!task.success&&coordinator.calls==0&&supervisor.calls==0&&!task.expirationHandler);
        assert([[value snapshot][@"last_detail"] isEqualToString:@"background_task_watchdog_unavailable"]);
    }
    reset();
    @autoreleasepool{
        expireOnInstall=YES;SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
        assert(task.completions==1&&coordinator.calls==0&&supervisor.calls==0&&!task.expirationHandler&&lastTimer.cancelled&&lastTimer.arms==0);
    }
    reset();
}
static void lifetimeCases(){
    __weak BGTask *releasedTask;RefreshReply lateRefresh;dispatch_block_t lateExpiration,lateWatchdog;
    SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
    @autoreleasepool{
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];releasedTask=task;
        [value handleTask:task kind:@"refresh"];lateRefresh=coordinator.reply;lateExpiration=task.expirationHandler;lateWatchdog=lastTimer.handler;
        expire(task);coordinator.reply=nil;
    }
    reset();assert(!releasedTask);lateRefresh(YES,@"late");lateExpiration();lateWatchdog();assert(supervisor.calls==0);
    lateRefresh=nil;lateExpiration=nil;lateWatchdog=nil;
    __weak BGTask *successfulTask;RefreshReply lateEnsure;
    @autoreleasepool{
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];successfulTask=task;
        [value handleTask:task kind:@"processing"];coordinator.reply(YES,@"ok");lateEnsure=supervisor.reply;supervisor.reply(YES,@"ok");
        coordinator.reply=nil;supervisor.reply=nil;
    }
    reset();assert(!successfulTask);lateEnsure(YES,@"late");lateEnsure=nil;
    BGTask *task=[BGTask new];__weak id<TestScheduler> releasedScheduler;
    @autoreleasepool{id<TestScheduler> value=scheduler(NO,supervisor,coordinator);releasedScheduler=value;[value handleTask:task kind:@"refresh"];}
    assert(!releasedScheduler);coordinator.reply(YES,@"ok");assert(task.completions==1&&!task.success&&lastTimer.cancelled);coordinator.reply=nil;task=nil;
    reset();
}
static void raceCases(){
    for(unsigned n=0;n<200;++n){
        @autoreleasepool{
            auto deliveries=std::make_shared<std::atomic<unsigned>>(0);
            auto value=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;++*deliveries;});
            assert(!value->beginEnsure()&&value->beginRefresh()&&!value->beginRefresh());
            std::thread first([value]{@autoreleasepool{if(value->beginEnsure())value->finish(YES,@"probe",nil);}});
            std::thread second([value]{@autoreleasepool{value->finish(NO,@"expired",nil);}});
            first.join();second.join();assert(value->finished()&&!value->beginEnsure()&&!value->beginRefresh()&&deliveries->load()==1);
        }
    }
    auto weak=std::make_shared<std::weak_ptr<TLinkBackgroundTaskRun>>();auto deliveries=std::make_shared<std::atomic<unsigned>>(0);
    auto value=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;++*deliveries;if(auto nested=weak->lock())nested->finish(NO,@"reentrant",nil);});
    *weak=value;value->finish(YES,@"first",nil);assert(deliveries->load()==1);value.reset();assert(weak->expired());
    // Late publication must cancel an already resumed source and never arm it.
    value=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;});
    value->finish(NO,@"early",nil);dispatch_source_t timer=fixtureCreate(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0));
    fixtureTimer(timer,DISPATCH_TIME_FOREVER,DISPATCH_TIME_FOREVER,0);fixtureResume(timer);value->installTimer(timer);value->arm(1);
    assert(lastTimer.cancelled&&lastTimer.arms==0);reset();
    for(unsigned n=0;n<64;++n){
        @autoreleasepool{
            SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
            id<TestScheduler> schedulerValue=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[schedulerValue handleTask:task kind:@"refresh"];
            RefreshReply refresh=coordinator.reply;dispatch_block_t expiration=task.expirationHandler;
            std::thread first([refresh]{@autoreleasepool{refresh(YES,@"racing-license");}});
            std::thread second([expiration]{@autoreleasepool{expiration();}});
            first.join();second.join();
            assert(task.completions==1&&supervisor.calls<=1&&!task.expirationHandler&&lastTimer.cancelled);
            NSDictionary *before=[schedulerValue snapshot];if(supervisor.reply)supervisor.reply(YES,@"late-probe");
            refresh(YES,@"late-license");assert(task.completions==1&&[before isEqual:[schedulerValue snapshot]]);
            coordinator.reply=nil;supervisor.reply=nil;
        }
        reset();
    }
}
static void independentRunsCase(){
    @autoreleasepool{
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);
        BGTask *oldTask=[BGTask new],*newTask=[BGTask new];[value handleTask:oldTask kind:@"refresh"];
        RefreshReply oldReply=coordinator.reply;dispatch_block_t oldExpiration=oldTask.expirationHandler,oldWatchdog=lastTimer.handler;
        expire(oldTask);[value handleTask:newTask kind:@"processing"];RefreshReply newReply=coordinator.reply;
        NSDictionary *before=[value snapshot];oldReply(YES,@"old");oldExpiration();oldWatchdog();
        assert([before isEqual:[value snapshot]]&&supervisor.calls==0&&newTask.completions==0);
        newReply(YES,@"new");supervisor.reply(YES,@"new");
        assert(oldTask.completions==1&&newTask.completions==1&&newTask.success&&supervisor.calls==1);
        assert([[value snapshot][@"last_completed_kind"] isEqualToString:@"processing"]);
        coordinator.reply=nil;supervisor.reply=nil;
    }
    reset();
}
static void queuedSupervisorCases(){
    for(unsigned terminal=0;terminal<2;++terminal){
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];supervisor.holdStart=YES;
        SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];__weak BGTask *releasedTask;
        NSDictionary *before;id<TestScheduler> value=scheduler(NO,supervisor,coordinator);
        @autoreleasepool{
            BGTask *task=[BGTask new];releasedTask=task;[value handleTask:task kind:@"refresh"];coordinator.reply(YES,@"accepted-license");
            assert(supervisor.startPermission&&supervisor.calls==0);
            if(terminal)watchdog(NO);else expire(task);
            assert(task.completions==1&&!task.success);before=[value snapshot];coordinator.reply=nil;
        }
        reset();assert(!releasedTask);[supervisor releaseStart];
        assert(supervisor.calls==0&&[before isEqual:[value snapshot]]&&!supervisor.startPermission&&!supervisor.queuedReply);
    }
    @autoreleasepool{
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];supervisor.holdStart=YES;
        SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];id<TestScheduler> value=scheduler(NO,supervisor,coordinator);
        BGTask *task=[BGTask new];[value handleTask:task kind:@"processing"];coordinator.reply(YES,@"license");
        BOOL (^duplicatePermission)(void)=supervisor.startPermission;
        [supervisor releaseStart];assert(supervisor.calls==1&&!duplicatePermission());supervisor.reply(YES,@"probe");
        assert(task.completions==1&&task.success);coordinator.reply=nil;supervisor.reply=nil;
    }
    reset();
}
static void realTimerCase(){
    @autoreleasepool{
        realTimer=true;SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
        const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;
        while(task.completions==0&&CFAbsoluteTimeGetCurrent()<end)pump();
        assert(task.completions==1&&!task.success);
        assert(dispatch_group_wait(lastTimer.retired,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        coordinator.reply(YES,@"late");assert(supervisor.calls==0&&!task.expirationHandler);coordinator.reply=nil;
    }
    reset();
}
static void subscriptionSchedulerCases(){
    for(unsigned terminal=0;terminal<2;++terminal){
        @autoreleasepool{
            SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
            id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];
            coordinator.beforeSubscriptionReturn=^{if(terminal)watchdog(NO);else expire(task);};
            [value handleTask:task kind:@"refresh"];coordinator.beforeSubscriptionReturn=nil;
            assert(task.completions==1&&!task.success&&coordinator.retirements==1&&supervisor.calls==0&&lastTimer.cancelled);
            NSDictionary *before=[value snapshot];coordinator.reply(YES,@"late-after-publication");
            assert([before isEqual:[value snapshot]]&&supervisor.calls==0&&coordinator.retirements==1);coordinator.reply=nil;
        }
        reset();
    }
    @autoreleasepool{
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];coordinator.subscriptionUnavailable=YES;
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"refresh"];
        assert(task.completions==1&&!task.success&&coordinator.calls==0&&supervisor.calls==0&&lastTimer.cancelled);
        assert([[value snapshot][@"last_detail"] isEqualToString:@"license_refresh_subscription_unavailable"]);
    }
    reset();
    @autoreleasepool{
        SCStreamSupervisor *supervisor=[SCStreamSupervisor new];SCLicenseLifecycleCoordinator *coordinator=[SCLicenseLifecycleCoordinator new];
        id<TestScheduler> value=scheduler(NO,supervisor,coordinator);BGTask *task=[BGTask new];[value handleTask:task kind:@"processing"];
        coordinator.reply(YES,@"delivered");assert(coordinator.retirements==1&&supervisor.calls==1);
        expire(task);supervisor.reply(YES,@"late");coordinator.reply(YES,@"duplicate");
        assert(task.completions==1&&coordinator.retirements==1);coordinator.reply=nil;supervisor.reply=nil;
    }
    reset();
    for(int fault=0;fault<3;++fault){
        auto cleanups=std::make_shared<std::atomic<unsigned>>(0),deliveries=std::make_shared<std::atomic<unsigned>>(0);
        auto weak=std::make_shared<std::weak_ptr<TLinkBackgroundTaskRun>>();
        auto run=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;assert(cleanups->load()==1);++*deliveries;});*weak=run;
        run->installCleanup(^{++*cleanups;auto owner=weak->lock();assert(owner&&owner->finished());if(fault==1)[NSException raise:@"Cleanup" format:@"NS"];if(fault==2)throw std::runtime_error("cleanup");});
        run->finish(NO,@"expired",nil);run->finish(NO,@"duplicate",nil);assert(deliveries->load()==1&&cleanups->load()==1);
        auto late=std::make_shared<TLinkBackgroundTaskRun>(^(BOOL success,NSString *detail,NSDictionary *license){(void)success;(void)detail;(void)license;});late->finish(NO,@"before-publication",nil);
        late->installCleanup(^{++*cleanups;if(fault==1)[NSException raise:@"Cleanup" format:@"late NS"];if(fault==2)throw std::runtime_error("late cleanup");});
        assert(cleanups->load()==2);
    }
}
int main(){@autoreleasepool{
    timers=[NSMutableDictionary dictionary];legacyTimers=[NSMutableArray array];
    puts("Background task Foundation: complete current/frozen scheduler, controlled BGTask/providers and real resumed GCD sources");
    parityCases();lateCases();faultCases();lifetimeCases();raceCases();independentRunsCase();queuedSupervisorCases();realTimerCase();subscriptionSchedulerCases();
    for(unsigned n=0;n<128;++n){@autoreleasepool{(void)outcome(NO,n%2,NO,YES,YES,0);}reset();}
    assert(created.load()==cancelled.load()&&liveTasks.load()==0);
    puts("Background task passed: frozen replies/rescheduling, duplicate/late callback refusal, first-result diagnostics, allocation/installation/NS/C++ faults, early task release with retained callbacks, 200 policy/64 actual callback races, independent runs, owner-start permission after queued expiration/timeout, subscriber cancellation/late publication/nil provider, cleanup reentry/faults, real timeout delivery and 128 balanced source/task lifecycles. HTTP/active supervisor cancellation and device qualification remain pending.");
}return 0;}
