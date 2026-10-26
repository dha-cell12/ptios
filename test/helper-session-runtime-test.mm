#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include "../shared/TLinkHelperChangeWait.h"
#include "../shared/TLinkHelperRPCIdentity.h"
#include "../shared/TLinkHelperClientAdmission.h"
#include "../shared/TLinkHelperConnection.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>
@class TLinkJSFileHandle;
struct FixtureCancel {std::atomic<bool> stopped{false};};
@interface SessionFixture : NSObject {
@public FixtureCancel *_cancelState;
    TLinkHelperChangeWait _statusChanges;
    TLinkHelperClientAdmission _clientAdmission;
    TLinkHelperConnectionAdmission _connectionAdmission;
    std::atomic<unsigned> mode,closed,evaluated;
}
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, strong) NSDate *startedAt;
@property(nonatomic, strong) dispatch_queue_t executionQueue;
@property(nonatomic, strong) dispatch_queue_t clientQueue;
@property(nonatomic, strong) NSCondition *sleepCondition;
@property(nonatomic, assign) BOOL sessionCompletionCommitted;
@property(nonatomic, assign) BOOL sessionWorkerActive; // rpcCondition owns lifecycle + RPC slot
@property(nonatomic, copy) NSString *activeSessionId;
@property(nonatomic, copy) NSString *activeRunId;
@property(nonatomic, copy) NSString *activeState;
@property(nonatomic, strong) NSDate *activeStartedAt;
@property(nonatomic, strong) NSDate *activeEndedAt;
@property(nonatomic, copy) NSString *activeExitReason;
@property(atomic, assign) NSUInteger nativeRPCCount;
@property(atomic, assign) NSUInteger nativeRPCFailedCount;
@property(atomic, assign) NSUInteger nativeRPCBlockedCount;
@property(atomic, assign) NSUInteger storageOpsCount;
@property(atomic, assign) double nativeRPCTotalMs;
@property(atomic, assign) double nativeRPCMaxMs;
@property(nonatomic, assign) double evalDurationMs;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lastConsoleLogPath;
@property(nonatomic, copy) NSString *lastConsoleLatestLogPath;
@property(nonatomic, strong) NSCondition *rpcCondition;
@property(nonatomic, copy) NSDictionary *pendingNativeRequest;
@property(nonatomic, copy) NSDictionary *nativeResponse;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, TLinkJSFileHandle *> *activeFileHandles;
@property(nonatomic, assign) NSUInteger nextFileHandleId;
@property(nonatomic, strong) dispatch_source_t licenseHeartbeat;
@property(nonatomic, copy) NSString *licenseHeartbeatSessionId;
@property(atomic, assign) NSUInteger licenseHeartbeatCheckCount;
@property(atomic, assign) NSUInteger licenseRevocationCount;

@property(nonatomic, strong) dispatch_semaphore_t inLog;
@property(nonatomic, strong) dispatch_semaphore_t releaseLog;
- (NSDictionary *)executeNativeRPCMethod:(NSString *)method arguments:(NSArray *)arguments sessionId:(NSString *)sessionId;
- (NSDictionary *)acceptNativeRPCResponse:(NSDictionary *)request;
- (void)clearNativeRPCForSessionId:(NSString *)sessionId;
- (void)publishStatusChange;
- (BOOL)sessionIsBusy;
- (BOOL)ownsSessionId:(NSString *)sessionId;
- (BOOL)beginSessionId:(NSString *)sessionId runId:(NSString *)runId;
- (BOOL)markRunningSessionId:(NSString *)sessionId logPath:(NSString *)logPath latestPath:(NSString *)latestPath;
- (void)recordSessionId:(NSString *)sessionId error:(NSString *)text durationMs:(double)duration;
- (NSString *)requestStopForSessionId:(NSString *)sessionId reason:(NSString *)reason errorText:(NSString *)errorText;
- (NSDictionary *)completeSessionId:(NSString *)sessionId state:(NSString *)state reason:(NSString *)reason errorText:(NSString *)errorText;
- (void)retireSessionId:(NSString *)sessionId;
- (NSDictionary *)statusPayload;
- (NSDictionary *)startWithRequest:(NSDictionary *)request;
- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message;
- (void)runOwnedSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId;
- (void)runSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId;
- (void)finishSessionId:(NSString *)sessionId state:(NSString *)state reason:(NSString *)reason errorText:(NSString *)errorText logPath:(NSString *)logPath latestPath:(NSString *)latestPath;
- (void)stopLicenseHeartbeatForSessionId:(NSString *)sessionId;
- (void)closeActiveFileHandles;
- (void)appendLine:(NSString *)line toPath:(NSString *)path;
- (NSString *)licenseDenialForComponent:(NSString *)component;
@end
@implementation SessionFixture
- (instancetype)init {self=[super init];if(self){
    _cancelState=new FixtureCancel();mode=0;closed=0;evaluated=0;
    self.helperInstanceId=@"helper";self.startedAt=[NSDate date];self.activeState=kTLinkJSHelperStateIdle;
    self.rpcCondition=[[NSCondition alloc] init];self.sleepCondition=[[NSCondition alloc] init];
    self.activeFileHandles=[NSMutableDictionary dictionary];self.executionQueue=dispatch_queue_create("fixture.session.execution",DISPATCH_QUEUE_SERIAL);
    self.inLog=dispatch_semaphore_create(0);self.releaseLog=dispatch_semaphore_create(0);
}return self;}
- (void)dealloc {delete _cancelState;}
- (NSString *)licenseDenialForComponent:(NSString *)component {(void)component;return nil;}
- (void)stopLicenseHeartbeatForSessionId:(NSString *)sessionId {(void)sessionId;}
- (void)closeActiveFileHandles {++closed;assert([self statusPayload]);}
- (void)appendLine:(NSString *)line toPath:(NSString *)path {
    (void)line;(void)path;assert([self statusPayload]);
    if(mode==3){dispatch_semaphore_signal(self.inLog);assert(dispatch_semaphore_wait(self.releaseLog,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
}
- (void)runSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId {
    (void)scriptPath;(void)bundlePath;(void)manifest;(void)runId;
    if(mode==1)[NSException raise:@"fixture_session" format:@"injected"];
    if(mode==2)throw std::runtime_error("injected C++ exception");
    if([self markRunningSessionId:sessionId logPath:@"log" latestPath:@"latest"]){
        ++evaluated;if(mode==4)[self executeNativeRPCMethod:@"tap" arguments:@[] sessionId:sessionId];
        [self finishSessionId:sessionId state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:nil logPath:@"log" latestPath:nil];
    }else [self finishSessionId:sessionId state:kTLinkJSHelperStateCancelled reason:@"cancelled" errorText:nil logPath:nil latestPath:nil];
}
#include "HelperSessionUnderTest.inc"
@end
static NSDictionary *request(){return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStart helperInstanceId:@"helper" sessionId:nil requestId:@"transport" payload:@{@"scriptPath":@"/script.js",@"bundlePath":@"/bundle"}];}
static void busy(NSDictionary *reply){assert([reply[@"error"][@"message"] isEqual:@"helper_busy"]);}
static void lifecycleCases(){
    SessionFixture *server=[[SessionFixture alloc] init];assert([[server statusPayload][@"sessionSnapshotContract"] isEqual:@"lifecycle_rpc_owner_v1"]);assert([server beginSessionId:@"one" runId:@"run-one"]);
    assert(![server beginSessionId:@"other" runId:@"other"]);
    assert(![server requestStopForSessionId:@"one" reason:nil errorText:nil]);
    assert(![server markRunningSessionId:@"one" logPath:@"log" latestPath:@"latest"]);
    NSDictionary *summary=[server completeSessionId:@"one" state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:nil];
    assert([summary[@"state"] isEqual:@"cancelled"]&&[summary[@"exitReason"] isEqual:@"cancelled"]);busy([server startWithRequest:request()]);
    [server recordSessionId:@"one" error:@"late" durationMs:999];assert([[server statusPayload][@"lastError"] isEqual:@""]);
    [server retireSessionId:@"one"];assert([server beginSessionId:@"two" runId:@"run-two"]);
    [server recordSessionId:@"one" error:@"stale" durationMs:999];[server retireSessionId:@"one"];
    assert([[server requestStopForSessionId:@"one" reason:@"license_revoked_during_execution" errorText:@"stale"] isEqual:@"session_mismatch"]);
    assert(![server completeSessionId:@"one" state:kTLinkJSHelperStateFailed reason:@"stale" errorText:@"stale"]);
    const unsigned before=server->closed;[server finishSessionId:@"one" state:kTLinkJSHelperStateFailed reason:@"stale" errorText:nil logPath:nil latestPath:nil];assert(server->closed==before);
    assert([server sessionIsBusy]&&[[server statusPayload][@"activeSessionId"] isEqual:@"two"]);
    assert([server markRunningSessionId:@"two" logPath:@"log" latestPath:@"latest"]);
    [server.rpcCondition lock];server.pendingNativeRequest=@{@"sessionId":@"two",@"requestId":@"native",@"helperInstanceId":@"helper"};[server.rpcCondition unlock];
    NSDictionary *snapshot=[server statusPayload];assert([snapshot[@"pendingNativeRPC"] boolValue]);
    [server requestStopForSessionId:@"two" reason:@"license_revoked_during_execution" errorText:@"license_required"];
    NSDictionary *stopped=[server statusPayload];assert(!stopped[@"nativeRPCRequest"]&&![stopped[@"pendingNativeRPC"] boolValue]);
    assert([snapshot[@"state"] isEqual:@"running"]&&snapshot[@"nativeRPCRequest"]); // retained immutable snapshot
    summary=[server completeSessionId:@"two" state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:@"overwrite"];
    assert([summary[@"lastError"] isEqual:@"license_required"]&&[summary[@"exitReason"] isEqual:@"license_revoked_during_execution"]);
    assert(![server completeSessionId:@"two" state:kTLinkJSHelperStateFailed reason:@"late" errorText:@"late"]);
    [server retireSessionId:@"two"];assert(![server sessionIsBusy]);
}
static void executionCases(){
    for(unsigned mode=0;mode<3;++mode){
        SessionFixture *server=[[SessionFixture alloc] init];server->mode=mode;
        NSDictionary *reply=[server startWithRequest:request()];assert(!reply[@"error"]);
        dispatch_sync(server.executionQueue,^{});NSDictionary *status=[server statusPayload];
        assert(![server sessionIsBusy]&&![status[@"pendingNativeRPC"] boolValue]&&server->closed>0);
        assert([status[@"state"] isEqual:mode==0?@"completed":@"failed"]);
    }
    {
        SessionFixture *server=[[SessionFixture alloc] init];server->mode=4;
        NSDictionary *started=[server startWithRequest:request()];NSString *session=started[@"sessionId"];
        [server.rpcCondition lock];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
        while(!server.pendingNativeRequest){assert([server.rpcCondition waitUntilDate:deadline]);}
        NSString *nativeId=server.pendingNativeRequest[@"requestId"];[server.rpcCondition unlock];
        // A malformed result throws while the worker owns the condition; finally must unlock it.
        NSDictionary *reply=[server acceptNativeRPCResponse:[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdNativeRPCResponse helperInstanceId:@"helper" sessionId:session requestId:@"transport" payload:@{@"requestId":nativeId,@"result":@{@"ok":@[]}}]];
        assert(!reply[@"error"]);dispatch_sync(server.executionQueue,^{});
        assert(![server sessionIsBusy]&&[[server statusPayload][@"state"] isEqual:@"failed"]&&!server.pendingNativeRequest);
    }
    {
        SessionFixture *server=[[SessionFixture alloc] init];dispatch_suspend(server.executionQueue);
        NSDictionary *reply=[server startWithRequest:request()];NSString *session=reply[@"sessionId"];
        [server requestStopForSessionId:session reason:nil errorText:nil];dispatch_resume(server.executionQueue);dispatch_sync(server.executionQueue,^{});
        assert(server->evaluated==0&&[[server statusPayload][@"state"] isEqual:@"cancelled"]&&![server sessionIsBusy]);
    }
    {
        SessionFixture *server=[[SessionFixture alloc] init];server->mode=3;[server startWithRequest:request()];
        assert(dispatch_semaphore_wait(server.inLog,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        NSDictionary *status=[server statusPayload];assert([status[@"state"] isEqual:@"completed"]&&[status[@"sessionWorkerActive"] boolValue]);
        busy([server startWithRequest:request()]);dispatch_semaphore_signal(server.releaseLog);dispatch_sync(server.executionQueue,^{});assert(![server sessionIsBusy]);
    }
}
static void admissionRaceCases(){
    SessionFixture *server=[[SessionFixture alloc] init];std::atomic<unsigned> winners{0};std::vector<std::thread> contenders;
    for(unsigned n=0;n<8;++n)contenders.emplace_back([&,n]{@autoreleasepool{
        NSString *session=[NSString stringWithFormat:@"contender-%u",n];if([server beginSessionId:session runId:session])++winners;
    }});
    for(auto &thread:contenders)thread.join();assert(winners==1);
    NSString *winner=[server statusPayload][@"activeSessionId"];
    [server completeSessionId:winner state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:nil];[server retireSessionId:winner];
    for(unsigned n=0;n<100;++n){@autoreleasepool{
        NSString *session=[NSString stringWithFormat:@"race-%u",n];assert([server beginSessionId:session runId:session]);
        std::thread run([&]{@autoreleasepool{[server markRunningSessionId:session logPath:@"log" latestPath:@"latest"];}});
        std::thread stop([&]{@autoreleasepool{[server requestStopForSessionId:session reason:nil errorText:nil];}});
        run.join();stop.join();assert([[server statusPayload][@"state"] isEqual:@"stopping"]);
        assert(![server markRunningSessionId:session logPath:@"late" latestPath:@"late"]);
        [server completeSessionId:session state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:nil];[server retireSessionId:session];
    }}
}
static void snapshotCases(){
    SessionFixture *server=[[SessionFixture alloc] init];std::atomic<bool> done{false};std::atomic<unsigned> reads{0},ready{0};std::vector<std::thread> readers;
    for(unsigned n=0;n<4;++n)readers.emplace_back([&]{@autoreleasepool{++ready;while(!done.load()){@autoreleasepool{
        NSDictionary *status=[server statusPayload];NSString *session=status[@"activeSessionId"],*state=status[@"state"];
        if(![state isEqual:@"idle"])assert([status[@"runId"] isEqual:session]);
        NSDictionary *pending=status[@"nativeRPCRequest"];
        if(pending)assert([state isEqual:@"running"]&&[pending[@"sessionId"] isEqual:session]&&[status[@"pendingNativeRPC"] boolValue]);
        if([state isEqual:@"starting"]||[state isEqual:@"running"])assert([status[@"endedAtMs"] longLongValue]==0);
        ++reads;
    }}}});
    const TLinkHelperIO::Deadline readyDeadline(TLinkHelperIO::nowMs(),5000);
    while(ready<4){assert(readyDeadline.remaining(TLinkHelperIO::nowMs()));std::this_thread::yield();}
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        NSString *session=[NSString stringWithFormat:@"session-%u",n];assert([server beginSessionId:session runId:session]);
        assert([server markRunningSessionId:session logPath:@"log" latestPath:@"latest"]);
        [server.rpcCondition lock];server.pendingNativeRequest=@{@"sessionId":session,@"requestId":@"native"};[server.rpcCondition unlock];
        [server requestStopForSessionId:session reason:nil errorText:nil];
        [server completeSessionId:session state:kTLinkJSHelperStateCompleted reason:@"normal" errorText:nil];[server retireSessionId:session];
    }}
    done=true;for(auto &reader:readers)reader.join();assert(reads>0&&!server.pendingNativeRequest&&![server sessionIsBusy]);
}
int main(){@autoreleasepool{lifecycleCases();executionCases();admissionRaceCases();snapshotCases();puts("Helper session Foundation passed: owned start/stop/terminal/retire, stopped-before-eval, stale callbacks, immutable lifecycle/RPC snapshots with four readers and 1000 replacements, busy through blocked logging, and NS/C++ exception cleanup.");}return 0;}
