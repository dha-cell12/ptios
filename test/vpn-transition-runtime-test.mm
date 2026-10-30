#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#include <atomic>
#include <cassert>
#include <cstdio>
#include <functional>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>
typedef NS_ENUM(NSInteger,NEVPNStatus){NEVPNStatusInvalid,NEVPNStatusDisconnected,NEVPNStatusConnecting,NEVPNStatusConnected,NEVPNStatusReasserting,NEVPNStatusDisconnecting};
typedef void (^TLinkVPNResultCompletion)(NSDictionary *);
static NSString *const NEVPNStatusDidChangeNotification=@"test.vpn.transition.status";
static void (^lastObserverBlock)(NSNotification *);
static std::atomic<unsigned> managers{0};
@interface NEVPNConnection:NSObject
@property NEVPNStatus status;
@property BOOL failStart;
@property BOOL nativeError;
@property BOOL inlineStatus;
@property int fault;
@property unsigned starts;
@property unsigned stops;
@property NEVPNStatus nextStatus;
- (BOOL)startVPNTunnelAndReturnError:(NSError **)error;
- (void)stopVPNTunnel;
@end
@implementation NEVPNConnection
- (void)effect {if(_fault==1)[NSException raise:@"TransitionFixture" format:@"effect"];if(_fault==2)throw std::runtime_error("effect");if(_inlineStatus){_status=_nextStatus;if(lastObserverBlock)lastObserverBlock(nil);}}
- (BOOL)startVPNTunnelAndReturnError:(NSError **)error {++_starts;[self effect];if(_nativeError&&error)*error=[NSError errorWithDomain:@"Fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"start fixture"}];return !_failStart;}
- (void)stopVPNTunnel {++_stops;[self effect];}
@end
@interface NEVPNManager:NSObject
@property(nonatomic,strong) NEVPNConnection *connection;
@end
@implementation NEVPNManager
- (instancetype)init {self=[super init];if(self){++managers;_connection=[NEVPNConnection new];}return self;}
- (void)dealloc {--managers;}
@end
static __weak NEVPNConnection *activeConnection;
static NSMutableSet *observers;
static NSInteger registrationStatus=-1;
static int registrationFault=0;
@interface FixtureCenter:NSObject
+ (instancetype)defaultCenter;
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *))block;
- (void)removeObserver:(id)observer;
@end
@implementation FixtureCenter
+ (instancetype)defaultCenter {static FixtureCenter *center;static dispatch_once_t once;dispatch_once(&once, ^{center=[FixtureCenter new];});return center;}
- (id)addObserverForName:(NSString *)name object:(id)object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *))block {
    if(registrationFault==1)[NSException raise:@"TransitionFixture" format:@"register"];if(registrationFault==2)throw std::runtime_error("register");
    id token=[[NSNotificationCenter defaultCenter] addObserverForName:name object:object queue:queue usingBlock:block];assert(token);
    [observers addObject:token];lastObserverBlock=[block copy];
    if(registrationStatus>=0){activeConnection.status=static_cast<NEVPNStatus>(registrationStatus);block(nil);}return token;
}
- (void)removeObserver:(id)observer {assert([observers containsObject:observer]);[[NSNotificationCenter defaultCenter] removeObserver:observer];[observers removeObject:observer];lastObserverBlock=nil;}
@end
@interface TimerRecord:NSObject
@property(nonatomic,strong) dispatch_source_t source;
@property(nonatomic,copy) dispatch_block_t handler;
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
static unsigned created=0,cancelled=0,statusReads=0;
static NSValue *key(dispatch_source_t source){return [NSValue valueWithPointer:(__bridge const void *)source];}
static dispatch_source_t FixtureCreate(dispatch_source_type_t type,uintptr_t handle,uintptr_t mask,dispatch_queue_t queue){
    if(createFailure)return nullptr;dispatch_source_t source=dispatch_source_create(type,handle,mask,queue);assert(source);
    TimerRecord *record=[TimerRecord new];record.source=source;timers[key(source)]=record;lastTimer=record;++created;return source;
}
static void FixtureHandler(dispatch_source_t source,dispatch_block_t handler){TimerRecord *record=timers[key(source)];assert(record);record.handler=handler;dispatch_source_set_event_handler(source,handler);}
static void FixtureResume(dispatch_source_t source){TimerRecord *record=timers[key(source)];assert(record&&!record.resumed);record.resumed=YES;dispatch_resume(source);}
static void FixtureCancel(dispatch_source_t source){TimerRecord *record=timers[key(source)];assert(record&&record.resumed&&!record.cancelled);record.cancelled=YES;++cancelled;dispatch_source_cancel(source);}
static void FixtureTimer(dispatch_source_t source,dispatch_time_t start,uint64_t interval,uint64_t leeway){
    TimerRecord *record=timers[key(source)];assert(record&&!record.cancelled);assert(interval==DISPATCH_TIME_FOREVER&&leeway==0);
    if(start!=DISPATCH_TIME_FOREVER)++record.arms;
    dispatch_source_set_timer(source,realTimer?start:DISPATCH_TIME_FOREVER,interval,leeway);
}
#define NSNotificationCenter FixtureCenter
#define dispatch_source_set_event_handler FixtureHandler
#define dispatch_source_set_timer FixtureTimer
#define dispatch_source_cancel FixtureCancel
#include "../shared/TLinkVPNTransition.h"
#undef NSNotificationCenter
#undef dispatch_source_set_event_handler
#undef dispatch_source_set_timer
#undef dispatch_source_cancel
static NSDictionary *TLinkVPNResult(BOOL ok,NSString *code,NSDictionary *extra){NSMutableDictionary *result=extra?[extra mutableCopy]:[NSMutableDictionary dictionary];result[@"ok"]=@(ok);result[@"code"]=code;return result;}
static NSDictionary *TLinkVPNStatusFields(NEVPNManager *manager){++statusReads;return @{@"status":@(manager.connection.status)};}
static void TLinkVPNComplete(TLinkVPNResultCompletion completion,NSDictionary *result){if(completion)dispatch_async(dispatch_get_main_queue(), ^{completion(result);});}
#define NSNotificationCenter FixtureCenter
#define dispatch_source_create FixtureCreate
#define dispatch_source_set_event_handler FixtureHandler
#define dispatch_source_set_timer FixtureTimer
#define dispatch_resume FixtureResume
#include "VPNTransitionUnderTest.inc"
#undef NSNotificationCenter
#undef dispatch_source_create
#undef dispatch_source_set_event_handler
#undef dispatch_source_set_timer
#undef dispatch_resume
static void FixtureAfter(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t handler){(void)when;(void)queue;[legacyTimers addObject:[handler copy]];}
#define NSNotificationCenter FixtureCenter
#define dispatch_after FixtureAfter
#include "VPNTransitionLegacy.inc"
#undef NSNotificationCenter
#undef dispatch_after
static void pump(){for(unsigned n=0;n<10;++n)CFRunLoopRunInMode(kCFRunLoopDefaultMode,.001,false);}
static void awaitManagers(){const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;while(managers.load()!=0&&CFAbsoluteTimeGetCurrent()<end)pump();assert(managers.load()==0);}
static void reset(){
    assert(observers.count==0&&created==cancelled);[timers removeAllObjects];lastTimer=nil;[legacyTimers removeAllObjects];lastObserverBlock=nil;activeConnection=nil;
    createFailure=realTimer=false;registrationStatus=-1;registrationFault=0;statusReads=0;pump();
}
static NEVPNManager *managerFor(BOOL connect){NEVPNManager *manager=[NEVPNManager new];manager.connection.status=connect?NEVPNStatusConnecting:NEVPNStatusDisconnecting;activeConnection=manager.connection;return manager;}
static void begin(BOOL legacy,NEVPNManager *manager,BOOL connect,double timeout,TLinkVPNResultCompletion completion){
    if(legacy)LegacyTransition(manager,connect,connect?NEVPNStatusConnected:NEVPNStatusDisconnected,timeout,completion);
    else TLinkVPNBeginTransition(manager,connect,connect?NEVPNStatusConnected:NEVPNStatusDisconnected,timeout,completion);
}
static void fire(BOOL legacy){if(legacy){dispatch_block_t block=legacyTimers.lastObject;assert(block);block();}else{dispatch_block_t block=lastTimer.handler;assert(block);block();}}
static NSDictionary *scenario(BOOL legacy,BOOL connect,unsigned kind){
    reset();NEVPNManager *manager=managerFor(connect);NSMutableArray *results=[NSMutableArray array];
    if(kind==3&&connect){manager.connection.failStart=YES;manager.connection.nativeError=YES;}
    if(kind==5){manager.connection.inlineStatus=YES;manager.connection.nextStatus=connect?NEVPNStatusConnected:NEVPNStatusDisconnected;}
    begin(legacy,manager,connect,20,^(NSDictionary *value){[results addObject:value];});
    if(kind<3){manager.connection.status=kind==0?(connect?NEVPNStatusConnected:NEVPNStatusDisconnected):kind==1?NEVPNStatusInvalid:NEVPNStatusDisconnected;
        [[NSNotificationCenter defaultCenter] postNotificationName:NEVPNStatusDidChangeNotification object:manager.connection];pump();}
    if(results.count==0)fire(legacy);pump();assert(results.count==1&&observers.count==0);
    if(!legacy){assert(lastTimer.cancelled);dispatch_block_t late=lastTimer.handler;late();pump();assert(results.count==1);}
    return results[0];
}
static void parityCases(){
    for(unsigned connect=0;connect<2;++connect){
        for(unsigned kind=0;kind<6;++kind){
            @autoreleasepool{
                NSDictionary *expected=scenario(YES,connect,kind);
                NSDictionary *actual=scenario(NO,connect,kind);
                assert([expected isEqual:actual]);
            }
        }
    }
    reset();
}
static void ownershipCases(){
    reset();__weak NEVPNManager *releasedManager;
    @autoreleasepool{
        NEVPNManager *manager=managerFor(YES);releasedManager=manager;NSMutableArray *results=[NSMutableArray array];
        begin(NO,manager,YES,30,^(NSDictionary *value){[results addObject:value];});
        dispatch_block_t lateTimer=lastTimer.handler;void (^lateObserver)(NSNotification *)=[lastObserverBlock copy];
        manager.connection.status=NEVPNStatusConnected;lateObserver(nil);pump();assert(results.count==1&&lastTimer.cancelled&&observers.count==0);
        const unsigned reads=statusReads;lateTimer();lateObserver(nil);pump();assert(statusReads==reads&&results.count==1);
        lateTimer=nil;lateObserver=nil;manager=nil;
    }
    reset();awaitManagers();assert(!releasedManager); // No retention until the former 30-second deadline.
    reset();registrationStatus=NEVPNStatusConnected;
    @autoreleasepool{NEVPNManager *manager=managerFor(YES);NSMutableArray *results=[NSMutableArray array];begin(NO,manager,YES,30,^(NSDictionary *value){[results addObject:value];});pump();assert(results.count==1&&observers.count==0&&lastTimer.cancelled&&manager.connection.starts==0&&lastTimer.arms==0);}
    reset();createFailure=true;
    @autoreleasepool{NEVPNManager *manager=managerFor(YES);NSMutableArray *results=[NSMutableArray array];begin(NO,manager,YES,30,^(NSDictionary *value){[results addObject:value];});pump();assert(results.count==1&&[results[0][@"code"] isEqualToString:@"vpn_transition_timer_failed"]&&manager.connection.starts==0&&observers.count==0);}
    reset();
    for(unsigned site=0;site<2;++site){
        for(unsigned kind=1;kind<=2;++kind){
            @autoreleasepool{
                NEVPNManager *manager=managerFor(YES);if(site==0)registrationFault=static_cast<int>(kind);else manager.connection.fault=static_cast<int>(kind);
                auto deliveries=std::make_shared<std::atomic<unsigned>>(0);bool caught=false;
                try{@try{begin(NO,manager,YES,30,^(__unused NSDictionary *value){++*deliveries;});}@catch(NSException *exception){(void)exception;caught=true;}}catch(...){caught=true;}
                pump();assert(caught&&deliveries->load()==0&&lastTimer.cancelled&&observers.count==0);registrationFault=0;
            }
        }
    }
    reset();
}
static void raceCases(){
    for(unsigned n=0;n<200;++n){@autoreleasepool{
        auto deliveries=std::make_shared<std::atomic<unsigned>>(0);auto state=std::make_shared<TLinkVPNTransitionState>(^(__unused NSDictionary *value){++*deliveries;});
        std::thread first([state]{@autoreleasepool{state->finish(@{});}}),second([state]{@autoreleasepool{state->finish(@{});}});first.join();second.join();
        state->abandon();assert(state->finished()&&deliveries->load()==1);
    }}
    auto weak=std::make_shared<std::weak_ptr<TLinkVPNTransitionState>>();auto deliveries=std::make_shared<std::atomic<unsigned>>(0);
    auto state=std::make_shared<TLinkVPNTransitionState>(^(__unused NSDictionary *value){++*deliveries;if(auto nested=weak->lock())nested->finish(@{});});*weak=state;
    state->finish(@{});assert(deliveries->load()==1);state.reset();assert(weak->expired());
    struct ReleaseProbe {
        std::weak_ptr<TLinkVPNTransitionState> owner;
        std::shared_ptr<std::atomic<bool>> released;
        ~ReleaseProbe(){auto state=owner.lock();assert(state&&state->finished());released->store(true);}
    };
    auto released=std::make_shared<std::atomic<bool>>(false);
    {
        auto probe=std::make_shared<ReleaseProbe>();probe->released=released;
        state=std::make_shared<TLinkVPNTransitionState>(^(__unused NSDictionary *value){(void)probe;});probe->owner=state;
    }
    state->abandon();assert(released->load());state.reset(); // Destructors may reenter after the lock is released.
}
static void realTimerCase(){
    reset();realTimer=true;NEVPNManager *manager=managerFor(YES);NSMutableArray *results=[NSMutableArray array];
    begin(NO,manager,YES,.001,^(NSDictionary *value){[results addObject:value];});
    const CFAbsoluteTime end=CFAbsoluteTimeGetCurrent()+5;
    while(results.count==0&&CFAbsoluteTimeGetCurrent()<end)pump();
    assert(results.count==1&&[results[0][@"code"] isEqualToString:@"vpn_transition_timeout"]&&lastTimer.cancelled&&observers.count==0);reset();
}
int main(){@autoreleasepool{
    timers=[NSMutableDictionary dictionary];legacyTimers=[NSMutableArray array];observers=[NSMutableSet set];
    puts("VPN transition Foundation: actual/frozen pending transition, real notification center and resumed GCD sources");
    parityCases();awaitManagers();ownershipCases();raceCases();@autoreleasepool{realTimerCase();}
    for(unsigned n=0;n<128;++n){@autoreleasepool{(void)scenario(NO,YES,5);}reset();}
    pump();awaitManagers();assert(created==cancelled&&observers.count==0);
    puts("VPN transition passed: frozen terminal/start-failure/timeout replies, early completion releases manager, late callbacks skip snapshots, registration race, allocation/setup faults, NS/C++ unwind, 200 finish races, reentry, real timer delivery and 128 balanced lifecycles. NetworkExtension/device qualification pending.");
}return 0;}
