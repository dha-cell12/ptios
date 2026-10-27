#import <Foundation/Foundation.h>
#include <os/lock.h>
#import "../pccontrol/TLinkTaskContext.h"
#import "../pccontrol/jsruntime/TLinkJSHelperClient.h"
#include "../shared/TLinkHelperRPCReplay.h"
#include "../shared/TLinkHelperRPCIdentity.h"
#include "../shared/TLinkHelperRuntimeWait.h"
#include <atomic>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <stdexcept>
@interface Script : NSObject
@property(nonatomic,strong) NSMutableArray *statuses;
@property(nonatomic,strong) NSMutableArray *hints;
@property(nonatomic,strong) NSMutableArray *cursors;
@property(nonatomic,strong) NSMutableArray *statusBudgets;
@property(nonatomic,strong) NSDictionary *startError;
@property(nonatomic,copy) void (^onStatus)(void);
@property(nonatomic,copy) void (^onWait)(void);
@property(nonatomic,copy) void (^onPolicy)(void);
@property(nonatomic,copy) void (^onNative)(void);
@property(nonatomic,copy) void (^onStart)(void);
@property(nonatomic,assign) unsigned starts;
@property(nonatomic,assign) unsigned statusCalls;
@property(nonatomic,assign) unsigned waits;
@property(nonatomic,assign) unsigned acks;
@property(nonatomic,assign) unsigned stops;
@property(nonatomic,assign) unsigned effects;
@property(nonatomic,assign) unsigned releases;
@property(nonatomic,assign) BOOL lostAck;
@property(nonatomic,assign) BOOL throwStatus;
@property(nonatomic,assign) BOOL cppStatus;
@property(nonatomic,assign) BOOL statusCancellationObserved;
@property(nonatomic,assign) BOOL reuseEnabled;
@end
@implementation Script
- (instancetype)init {self=[super init];if(self){self.statuses=[NSMutableArray array];self.hints=[NSMutableArray array];self.cursors=[NSMutableArray array];self.statusBudgets=[NSMutableArray array];}return self;}
@end
static Script *script;
@interface TLinkJSHelperClient ()
@property(nonatomic,copy) TLinkJSHelperCancellationCheck cancellationCheck;
@end
@implementation TLinkJSHelperClient
- (void)setConnectionReuseEnabled:(BOOL)enabled {assert(script.starts==1);script.reuseEnabled=enabled;}
- (NSDictionary *)startScriptAtPath:(NSString *)path bundlePath:(NSString *)bundle manifest:(NSDictionary *)manifest timeoutMs:(int)timeout {
    (void)path;(void)bundle;(void)manifest;assert(timeout>0&&timeout<=1000);++script.starts;
    assert(self.cancellationCheck);if(script.onStart)script.onStart();
    if(self.cancellationCheck())return @{@"ok":@(false),@"error":@"cancelled"};
    return script.startError ?: @{@"ok":@(true),@"response":@{@"helperInstanceId":@"helper",@"sessionId":@"session",@"payload":@{@"runId":@"run"}}};
}
- (NSDictionary *)statusForSessionId:(NSString *)session timeoutMs:(int)timeout {
    assert(script.reuseEnabled&&[session isEqual:@"session"]&&timeout>0&&timeout<=500);++script.statusCalls;
    [script.statusBudgets addObject:@(timeout)];
    if(script.cppStatus)throw std::runtime_error("injected transport failure");
    if(script.throwStatus)[NSException raise:@"fixture_transport" format:@"injected"];
    if(script.onStatus)script.onStatus();
    script.statusCancellationObserved=self.cancellationCheck&&self.cancellationCheck();
    assert(script.statuses.count);NSDictionary *reply=script.statuses.firstObject;[script.statuses removeObjectAtIndex:0];return reply;
}
- (NSDictionary *)waitForChangeAfterSequence:(uint64_t)sequence sessionId:(NSString *)session waitMs:(int)waitMs timeoutMs:(int)timeout {
    assert([session isEqual:@"session"]&&waitMs==750&&timeout>25&&timeout<=1000);++script.waits;[script.cursors addObject:@(sequence)];
    if(script.onWait)script.onWait();assert(script.hints.count);NSDictionary *reply=script.hints.firstObject;[script.hints removeObjectAtIndex:0];return reply;
}
- (NSDictionary *)sendNativeRPCResponse:(NSDictionary *)result requestId:(NSString *)request sessionId:(NSString *)session timeoutMs:(int)timeout {
    (void)result;assert([request isEqual:@"native"]&&[session isEqual:@"session"]&&timeout>0&&timeout<=500);++script.acks;
    if(script.lostAck){script.lostAck=false;return @{@"ok":@(false),@"error":@"read_failed"};}return @{@"ok":@(true)};
}
- (NSDictionary *)stopSessionId:(NSString *)session timeoutMs:(int)timeout {(void)session;assert(timeout==250&&!self.cancellationCheck&&!script.reuseEnabled);++script.stops;return @{@"ok":@(true)};}
- (NSDictionary *)handshakeWithTimeoutMs:(int)timeout {(void)timeout;return @{};}
- (NSDictionary *)statusWithTimeoutMs:(int)timeout {(void)timeout;return @{};}
@end
static NSDictionary *TLinkautoJSHelperConfigSnapshot(){return @{};}
static NSDictionary *TLinkautoJSHelperRPCPolicy(NSString *method,NSArray *arguments,NSDictionary *config){(void)method;(void)arguments;(void)config;if(script.onPolicy)script.onPolicy();return @{@"allowed":@(true)};}
static BOOL TLinkautoJSIsFiniteNumber(double value){return std::isfinite(value);}
struct TLinkautoJSCancelState {std::atomic<bool> aborted{false};};
@interface RuntimeFixture : NSObject {
@public TLinkautoJSCancelState *_cancelState;
    BOOL _helperRunning;
    NSString *_helperSessionId,*_helperRunId,*_helperConsoleLogPath,*_helperConsoleLatestLogPath;
    TLinkHelperRPCReplay _helperNativeRPCReplay;
    NSUInteger _helperRPCCount,_helperDuplicateRPCCount,_helperBlockedRPCCount,_helperAutoReleasedFrameCount,_helperAutoReleasedImageCount;
    TLinkTaskExecutionContext *_taskContext;
    os_unfair_lock _handlesLock;
    NSMutableSet *_ownedFrameIds,*_ownedImageIds;
}
- (BOOL)runScriptInHelperAtPath:(NSString *)path bundlePath:(NSString *)bundle manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
- (void)beginOwnedHandleTracking;
- (void)releaseOwnedHandles;
- (NSDictionary *)executeNativeRequest:(NSString *)method arguments:(NSArray *)arguments;
@end
@implementation RuntimeFixture
- (instancetype)init {self=[super init];if(self){_cancelState=new TLinkautoJSCancelState();_handlesLock=OS_UNFAIR_LOCK_INIT;_ownedFrameIds=[NSMutableSet set];_ownedImageIds=[NSMutableSet set];}return self;}
- (void)dealloc {delete _cancelState;}
- (void)beginOwnedHandleTracking {[_ownedFrameIds removeAllObjects];[_ownedImageIds removeAllObjects];}
- (void)releaseOwnedHandles {++script.releases;assert(_taskContext&&[_taskContext.ownerRuntime isEqual:@"helper"]);}
- (NSDictionary *)executeNativeRequest:(NSString *)method arguments:(NSArray *)arguments {
    (void)method;(void)arguments;assert([_taskContext.ownerSessionId isEqual:@"session"]&&[_taskContext nativeBudget]);++script.effects;
    if(script.onNative)script.onNative();return @{@"ok":@(true),@"value":@7};
}
#include "HelperRuntimeWaitUnderTest.inc"
@end
static NSDictionary *status(NSString *state,uint64_t sequence,bool pending=false,int capability=2){
    NSMutableDictionary *payload=[@{@"state":state,@"activeSessionId":@"session",@"runId":@"run"} mutableCopy];
    if(capability>=1){payload[@"changeWaitContract"]=@"session_native_rpc_v1";payload[@"changeSequence"]=@(sequence);}
    if(capability==2)payload[@"sessionSnapshotContract"]=@"lifecycle_rpc_owner_v1";
    if(pending)payload[@"nativeRPCRequest"]=@{@"helperInstanceId":@"helper",@"sessionId":@"session",@"requestId":@"native",@"method":@"tap",@"arguments":@[@1,@2]};
    return @{@"ok":@(true),@"response":@{@"command":@"status",@"helperInstanceId":@"helper",@"sessionId":@"session",@"payload":payload}};
}
static NSDictionary *hint(uint64_t sequence,bool changed){return @{@"ok":@(true),@"response":@{@"payload":@{@"sequence":@(sequence),@"changed":@(changed),@"reason":changed?@"changed":@"timeout"}}};}
static NSDictionary *failure(NSString *code){return @{@"ok":@(false),@"error":code};}
static TLinkTaskExecutionContext *context(){TLinkTaskExecutionContext *ctx=[[TLinkTaskExecutionContext alloc] init];ctx.cancellationToken=[[TLinkCancellationToken alloc] init];ctx.defaultTimeoutSeconds=30;ctx.defaultMaxOutputBytes=1024*1024;ctx.ownerSessionId=@"caller";return ctx;}
static bool run(RuntimeFixture *runtime,TLinkTaskExecutionContext *ctx,NSDictionary *manifest,NSError **error){return [runtime runScriptInHelperAtPath:@"/script" bundlePath:@"/bundle" manifest:manifest context:ctx error:error];}
static void cleaned(RuntimeFixture *runtime,TLinkTaskExecutionContext *ctx){assert(!runtime->_helperRunning&&!runtime->_helperSessionId&&!runtime->_taskContext&&runtime->_helperNativeRPCReplay.identities()==0&&!script.reuseEnabled);assert([ctx.ownerSessionId isEqual:@"caller"]);}
static void successCases(){
    script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
    [script.statuses addObjectsFromArray:@[status(@"running",1),status(@"running",2,true),status(@"running",2,true),status(@"completed",3)]];
    [script.hints addObjectsFromArray:@[hint(200,true),hint(3,true)]];script.lostAck=true;
    assert(run(runtime,ctx,@{},nil));assert(script.effects==1&&script.acks==2&&script.starts==1&&runtime->_helperDuplicateRPCCount==1);
    assert(([script.cursors isEqual:@[@1,@2]]));assert(script.statusCalls==4&&script.waits==2&&script.releases==1&&script.stops==0);cleaned(runtime,ctx);
    for(int capability : {0,1,2}){
        script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
        [script.statuses addObjectsFromArray:@[status(@"running",1,false,capability),status(@"completed",2,false,capability)]];
        if(capability==2)[script.hints addObject:hint(1,false)];
        assert(run(runtime,ctx,@{},nil));assert(script.waits==(capability==2?1U:0U));cleaned(runtime,ctx);
    }
    for(NSString *code in @[@"unsupported_command",@"change_wait_busy",@"read_failed",@"empty_frame",@"io_timeout"]){
        script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
        [script.statuses addObjectsFromArray:@[status(@"running",1),status(@"completed",2)]];[script.hints addObject:failure(code)];
        assert(run(runtime,ctx,@{},nil));assert(script.starts==1&&script.statusCalls==2&&script.waits==1);cleaned(runtime,ctx);
    }
}
static void rejectionCases(){
    for(unsigned kind=0;kind<4;++kind){
        script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
        NSMutableDictionary *bad=[status(@"running",1,true) mutableCopy],*response=[bad[@"response"] mutableCopy],*payload=[response[@"payload"] mutableCopy];
        response[@"payload"]=payload;bad[@"response"]=response;
        if(kind==0)response[@"helperInstanceId"]=@"other";
        if(kind==1)payload[@"changeSequence"]=@(true);
        if(kind==2)payload[@"nativeRPCRequest"]=@{@"sessionId":@"other",@"requestId":@"native"};
        if(kind==3){[script.statuses addObject:status(@"running",2)];[script.hints addObject:hint(3,true)];}
        [script.statuses addObject:bad];assert(!run(runtime,ctx,@{},nil));assert(script.effects==0&&script.stops==1);cleaned(runtime,ctx);
    }
    script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
    [script.statuses addObject:status(@"running",1)];[script.hints addObject:hint(1,true)];assert(!run(runtime,ctx,@{},nil));assert(script.effects==0&&script.stops==1);cleaned(runtime,ctx);
}
static void cancellationCases(){
    for(unsigned phase=0;phase<4;++phase){
        script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
        void (^cancel)(void)=^{[ctx.cancellationToken cancel];};
        if(phase==0)script.onStatus=cancel;if(phase==1)script.onPolicy=cancel;if(phase==2)script.onWait=cancel;if(phase==3)script.onNative=cancel;
        [script.statuses addObject:status(@"running",1,phase!=2)];if(phase==2)[script.hints addObject:hint(2,true)];
        assert(!run(runtime,ctx,@{},nil));assert(script.effects==(phase==3?1U:0U)&&script.acks==0&&script.stops==1);cleaned(runtime,ctx);
    }
    script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
    [ctx setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    assert(!run(runtime,ctx,@{},nil)&&script.starts==0);
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();[ctx.cancellationToken cancel];
    assert(!run(runtime,ctx,@{},nil)&&script.starts==0);
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
    auto output=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,1,false,true);
    const uint8_t bytes[]={'a','b',0};assert(output->appendCString(bytes)<0);[ctx setNativeBudget:output];assert(!run(runtime,ctx,@{},nil)&&script.starts==0);
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();[script.statuses addObject:status(@"running",1,true)];
    script.onStatus=^{[NSThread sleepForTimeInterval:0.01];};assert(!run(runtime,ctx,@{@"helperTimeoutMs":@1},nil)&&script.effects==0);cleaned(runtime,ctx);
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();script.throwStatus=true;
    BOOL caught=false;@try{run(runtime,ctx,@{},nil);}@catch(NSException *exception){(void)exception;caught=true;}
    assert(caught&&script.stops==1);cleaned(runtime,ctx);
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();script.cppStatus=true;
    bool cppCaught=false;try{run(runtime,ctx,@{},nil);}catch(const std::runtime_error &exception){(void)exception;cppCaught=true;}
    assert(cppCaught&&script.stops==1);cleaned(runtime,ctx);
}
static void startCases(){
    script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();NSError *error=nil;
    script.onStart=^{[ctx.cancellationToken cancel];};
    assert(!run(runtime,ctx,@{},&error)&&script.starts==1&&script.statusCalls==0&&!runtime->_helperRunning);
    assert(![error.userInfo[@"helperFallbackSafe"] boolValue]);
    for(NSString *code in @[@"helper_busy",@"connect_failed",@"socket_setup_failed",@"io_timeout",@"read_failed",@"write_failed",@"helper_instance_mismatch",@"license_required",@"frame_too_large",@"serialize_failed"]){
        script=[[Script alloc] init];script.startError=failure(code);RuntimeFixture *runtime=[[RuntimeFixture alloc] init];NSError *error=nil;
        assert(!run(runtime,context(),@{},&error));const bool safe=[code isEqual:@"helper_busy"]||[code isEqual:@"connect_failed"]||[code isEqual:@"socket_setup_failed"];
        assert([error.userInfo[@"helperFallbackSafe"] boolValue]==safe&&script.starts==1&&script.statusCalls==0);
    }
}
static void recoveryCases(){
    for(NSString *code in @[@"io_timeout",@"empty_frame",@"connect_failed",@"read_failed",@"write_failed"]){
        assert(TLinkHelperRuntimeRetryStatus(failure(code)));
        for(bool exhaust : {false,true}){
            script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();NSError *error=nil;
            [script.statuses addObjectsFromArray:@[failure(code),failure(code)]];
            if(exhaust)[script.statuses addObject:failure(code)];
            [script.statuses addObject:status(@"completed",1)];
            assert(run(runtime,ctx,@{},&error)==!exhaust);
            assert(script.starts==1&&script.statusCalls==3&&script.effects==0&&script.waits==0&&script.stops==(exhaust?1U:0U));
            if(exhaust){assert(script.statuses.count==1);assert([error.localizedDescription containsString:code]);}
            cleaned(runtime,ctx);
        }
    }
    // A successful snapshot resets both attempt count and outage window.
    script=[[Script alloc] init];RuntimeFixture *runtime=[[RuntimeFixture alloc] init];TLinkTaskExecutionContext *ctx=context();
    [script.statuses addObjectsFromArray:@[failure(@"read_failed"),failure(@"read_failed"),status(@"running",1),failure(@"connect_failed"),failure(@"empty_frame"),status(@"completed",2)]];
    [script.hints addObject:hint(2,true)];assert(run(runtime,ctx,@{},nil));assert(script.statusCalls==6&&script.starts==1&&script.waits==1);cleaned(runtime,ctx);

    // Lost ACK plus status outage must keep the replay ledger, cursor and pinned owner.
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();script.lostAck=true;
    [script.statuses addObjectsFromArray:@[status(@"running",2,true),failure(@"read_failed"),failure(@"io_timeout"),status(@"running",2,true),status(@"completed",3)]];
    [script.hints addObject:hint(3,true)];assert(run(runtime,ctx,@{},nil));
    assert(script.effects==1&&script.acks==2&&script.starts==1&&script.statusCalls==5&&runtime->_helperDuplicateRPCCount==1);
    assert(([script.cursors isEqual:@[@2]]));cleaned(runtime,ctx);

    // Local-looking remote errors, malformed/ownership/cancel errors stay fatal.
    NSArray *fatal=@[failure(@"cancelled"),failure(@"helper_instance_mismatch"),failure(@"session_mismatch"),failure(@"invalid_rpc_response"),failure(@"frame_too_large"),failure(@"change_wait_busy"),failure(@"socket_setup_failed"),
        @{@"ok":@(false),@"error":@{@"message":@"read_failed"}},@{@"ok":@(false),@"error":@"read_failed",@"response":@{}},@{@"ok":@0,@"error":@"read_failed"}];
    for(NSDictionary *reply in fatal){
        assert(!TLinkHelperRuntimeRetryStatus(reply));script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
        [script.statuses addObjectsFromArray:@[reply,status(@"running",1,true)]];
        assert(!run(runtime,ctx,@{},nil));assert(script.statusCalls==1&&script.effects==0&&script.stops==1);cleaned(runtime,ctx);
    }
    // Reconnect still checks helper/session ownership before accepting native work.
    for(bool replacementHelper : {false,true}){
        script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
        NSMutableDictionary *bad=[status(@"running",1,true) mutableCopy],*response=[bad[@"response"] mutableCopy];
        response[replacementHelper?@"helperInstanceId":@"sessionId"]=@"replacement";bad[@"response"]=response;
        [script.statuses addObjectsFromArray:@[failure(@"read_failed"),bad]];
        assert(!run(runtime,ctx,@{},nil));assert(script.statusCalls==2&&script.effects==0&&script.acks==0&&script.stops==1);cleaned(runtime,ctx);
    }
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
    [script.statuses addObjectsFromArray:@[status(@"running",2),failure(@"empty_frame"),status(@"running",1,true)]];[script.hints addObject:hint(3,true)];
    assert(!run(runtime,ctx,@{},nil));assert(script.effects==0&&script.acks==0&&script.statusCalls==3);cleaned(runtime,ctx);

    // Cancellation/output stop after a retry reply cannot dispatch the pending effect.
    for(bool outputStop : {false,true}){
        script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
        auto output=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,1,false,true);[ctx setNativeBudget:output];
        script.onStatus=^{if(script.statusCalls==2){if(outputStop){const uint8_t bytes[]={'a','b',0};assert(output->appendCString(bytes)<0);}else [ctx.cancellationToken cancel];}};
        [script.statuses addObjectsFromArray:@[failure(@"read_failed"),status(@"running",1,true)]];
        assert(!run(runtime,ctx,@{},nil));assert(script.statusCalls==2&&script.effects==0&&script.acks==0&&script.stops==1);cleaned(runtime,ctx);
    }
    // A shorter caller deadline bounds the first attempt and blocks retry/native work.
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
    [ctx setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeDeadline(0.25),1024)];
    script.onStatus=^{[NSThread sleepForTimeInterval:0.3];};[script.statuses addObject:failure(@"read_failed")];
    assert(!run(runtime,ctx,@{},nil));assert(script.statusCalls<=1&&script.effects==0&&script.stops==1);
    if(script.statusCalls)assert([script.statusBudgets[0] intValue]<=250);cleaned(runtime,ctx);

    // A syntactically good reply arriving after the episode window is not admitted.
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();NSError *lateError=nil;
    script.onStatus=^{[NSThread sleepForTimeInterval:1.6];};[script.statuses addObject:status(@"running",1,true)];
    assert(!run(runtime,ctx,@{},&lateError));assert(script.statusCalls==1&&script.effects==0&&script.acks==0&&script.stops==1);
    assert(script.statusCancellationObserved&&[lateError.localizedDescription containsString:@"helper_status_recovery_timeout"]);cleaned(runtime,ctx);

    // Old capability peers can recover status without enabling waitForChange.
    script=[[Script alloc] init];runtime=[[RuntimeFixture alloc] init];ctx=context();
    [script.statuses addObjectsFromArray:@[failure(@"read_failed"),status(@"running",1,false,0),failure(@"empty_frame"),status(@"completed",2,false,0)]];
    assert(run(runtime,ctx,@{},nil));assert(script.starts==1&&script.statusCalls==4&&script.waits==0);cleaned(runtime,ctx);
    puts("Helper status reconciliation Foundation passed: bounded retries/exhaustion/reset, fatal error classification, pinned ownership/cursor rejection, lost ACK replay with one effect, cancellation/output/caller deadline and legacy peers.");
}
int main(){@autoreleasepool{successCases();rejectionCases();cancellationCases();startCases();recoveryCases();puts("Helper runtime Foundation passed: actual loop capability/legacy paths, fresh status after hints, lost ACK replay without repeated effects, transport/busy recovery, cursor/identity gates, cancellation/deadline before native work, owned-context cleanup and uncertain-start fallback fence.");}return 0;}
