#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include "../shared/TLinkHelperRPCIdentity.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
struct FixtureCancel {std::atomic<bool> stopped{false};};
@interface FixtureHelper : NSObject {
@public FixtureCancel *_cancelState;
}
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, copy) NSString *activeSessionId;
@property(nonatomic, strong) NSCondition *rpcCondition;
@property(nonatomic, copy) NSDictionary *pendingNativeRequest;
@property(nonatomic, copy) NSDictionary *nativeResponse;
@property(nonatomic, assign) NSUInteger nativeRPCCount;
@property(nonatomic, assign) NSUInteger nativeRPCFailedCount;
@property(nonatomic, assign) NSUInteger nativeRPCBlockedCount;
@property(nonatomic, assign) double nativeRPCTotalMs;
@property(nonatomic, assign) double nativeRPCMaxMs;
- (NSDictionary *)executeNativeRPCMethod:(NSString *)method arguments:(NSArray *)arguments sessionId:(NSString *)sessionId;
- (NSDictionary *)acceptNativeRPCResponse:(NSDictionary *)request;
- (void)clearNativeRPCForSessionId:(NSString *)sessionId;
- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message;
@end
@implementation FixtureHelper
- (instancetype)init {self=[super init];if(self){_cancelState=new FixtureCancel();self.rpcCondition=[[NSCondition alloc] init];self.helperInstanceId=@"helper";self.activeSessionId=@"session";}return self;}
- (void)dealloc {delete _cancelState;}
#include "HelperIdentityServerUnderTest.inc"
@end
static NSDictionary *pending(NSString *session,NSString *request){return @{@"helperInstanceId":@"helper",@"sessionId":session,@"requestId":request,@"method":@"tap",@"arguments":@[]};}
static NSDictionary *envelope(NSString *session,NSString *request,NSDictionary *result){return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdNativeRPCResponse helperInstanceId:@"helper" sessionId:session requestId:@"transport" payload:@{@"requestId":request,@"result":result}];}
static void rejection(NSDictionary *reply,NSString *error){assert([reply[@"error"][@"message"] isEqual:error]);}
static void ownerCases(){
    NSDictionary *goodPending=pending(@"session",@"native");
    NSDictionary *goodStatus=@{@"helperInstanceId":@"helper",@"sessionId":@"session",@"requestId":@"transport",@"command":@"status",@"payload":@{@"state":@"running",@"activeSessionId":@"session",@"nativeRPCRequest":goodPending}};
    assert(!TLinkHelperRPCReplyError(goodStatus,@"status",@"transport",@"session",@"helper"));
    assert(!TLinkHelperRPCStatusError(goodStatus,@"helper",@"session"));assert(!TLinkHelperRPCStartError(goodStatus));
    assert([TLinkHelperRPCReplyError(goodStatus,@"stop",@"transport",@"session",@"helper") isEqual:@"response_command_mismatch"]);
    assert([TLinkHelperRPCReplyError(goodStatus,@"status",@"wrong",@"session",@"helper") isEqual:@"response_request_mismatch"]);
    assert([TLinkHelperRPCStatusError(goodStatus,@"other",@"session") isEqual:@"helper_instance_mismatch"]);
    assert([TLinkHelperRPCStatusError(goodStatus,@"helper",@"other") isEqual:@"session_mismatch"]);
    NSMutableDictionary *changed=[goodStatus mutableCopy],*payload=[goodStatus[@"payload"] mutableCopy];changed[@"payload"]=payload;
    payload[@"activeSessionId"]=@"other";assert([TLinkHelperRPCStatusError(changed,@"helper",@"session") isEqual:@"session_mismatch"]);
    payload[@"activeSessionId"]=@"session";payload[@"nativeRPCRequest"]=pending(@"other",@"native");assert([TLinkHelperRPCStatusError(changed,@"helper",@"session") isEqual:@"session_mismatch"]);
    payload[@"nativeRPCRequest"]=goodPending;payload[@"state"]=@"stopping";assert([TLinkHelperRPCStatusError(changed,@"helper",@"session") isEqual:@"inactive_native_rpc"]);
    payload[@"state"]=@"running";NSMutableDictionary *legacy=[goodPending mutableCopy];[legacy removeObjectForKey:@"helperInstanceId"];payload[@"nativeRPCRequest"]=legacy;assert(!TLinkHelperRPCStatusError(changed,@"helper",@"session"));
    legacy[@"helperInstanceId"]=@"other";assert([TLinkHelperRPCStatusError(changed,@"helper",@"session") isEqual:@"helper_instance_mismatch"]);
    legacy[@"helperInstanceId"]=@"helper";legacy[@"requestId"]=@7;assert([TLinkHelperRPCStatusError(changed,@"helper",@"session") isEqual:@"invalid_rpc_identity"]);
    // Gate a callback exactly as runtime does: mismatched status cannot dispatch its effect.
    unsigned effects=0;if(!TLinkHelperRPCStatusError(changed,@"helper",@"session"))++effects;assert(effects==0);
    if(!TLinkHelperRPCStatusError(goodStatus,@"helper",@"session"))++effects;assert(effects==1);
}
static void responseCases(){
    FixtureHelper *server=[[FixtureHelper alloc] init];server.pendingNativeRequest=pending(@"session",@"native");
    NSDictionary *first=@{@"ok":@(true),@"value":@1},*second=@{@"ok":@(true),@"value":@2};
    rejection([server acceptNativeRPCResponse:envelope(@"other",@"native",first)],@"session_mismatch");assert(!server.nativeResponse);
    rejection([server acceptNativeRPCResponse:envelope(@"session",@"old",first)],@"native_request_mismatch");
    NSMutableDictionary *bad=[envelope(@"session",@"native",first) mutableCopy];bad[@"helperInstanceId"]=@"other";
    rejection([server acceptNativeRPCResponse:bad],@"helper_instance_mismatch");assert(!server.nativeResponse);
    NSDictionary *ack=[server acceptNativeRPCResponse:envelope(@"session",@"native",first)];assert([ack[@"payload"][@"result"][@"accepted"] boolValue]);assert([server.nativeResponse isEqual:first]);
    ack=[server acceptNativeRPCResponse:envelope(@"session",@"native",second)];assert([ack[@"payload"][@"result"][@"duplicate"] boolValue]);assert([server.nativeResponse isEqual:first]);
    [server clearNativeRPCForSessionId:@"old-session"];assert(server.pendingNativeRequest&&server.nativeResponse);
    [server clearNativeRPCForSessionId:@"session"];assert(!server.pendingNativeRequest&&!server.nativeResponse);
    rejection([server acceptNativeRPCResponse:envelope(@"session",@"native",first)],@"no_pending_native_rpc");
    server.pendingNativeRequest=pending(@"session",@"native");server->_cancelState->stopped.store(true);
    rejection([server acceptNativeRPCResponse:envelope(@"session",@"native",first)],@"native_rpc_stopped");assert(!server.nativeResponse);
    server->_cancelState->stopped.store(false);bad=[envelope(@"session",@"native",first) mutableCopy];[bad removeObjectForKey:@"helperInstanceId"];
    ack=[server acceptNativeRPCResponse:bad];assert([ack[@"payload"][@"result"][@"accepted"] boolValue]);
    [server clearNativeRPCForSessionId:@"session"];
    // All contenders observe one first response; later duplicates cannot overwrite it.
    server.pendingNativeRequest=pending(@"session",@"race");std::atomic<unsigned> initial{0},duplicates{0};std::vector<std::thread> threads;
    for(unsigned n=0;n<8;++n)threads.emplace_back([&,n]{@autoreleasepool{NSDictionary *reply=[server acceptNativeRPCResponse:envelope(@"session",@"race",@{@"ok":@(true),@"winner":@(n)})];assert([reply[@"payload"][@"result"][@"accepted"] boolValue]);if([reply[@"payload"][@"result"][@"duplicate"] boolValue])++duplicates;else ++initial;}});
    for(auto &thread:threads)thread.join();assert(initial==1&&duplicates==7&&server.nativeResponse);
    [server clearNativeRPCForSessionId:@"session"];
}
static NSDictionary *waitPending(FixtureHelper *server){
    [server.rpcCondition lock];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(!server.pendingNativeRequest){assert([server.rpcCondition waitUntilDate:deadline]);}
    NSDictionary *value=server.pendingNativeRequest;[server.rpcCondition unlock];return value;
}
static void workerCases(){
    FixtureHelper *server=[[FixtureHelper alloc] init];
    for(unsigned n=0;n<100;++n){@autoreleasepool {
        NSDictionary *__strong response=nil;server->_cancelState->stopped.store(false);
        std::thread worker([&]{@autoreleasepool{response=[server executeNativeRPCMethod:@"tap" arguments:@[] sessionId:@"session"];}});
        NSDictionary *request=waitPending(server);
        if(n%5==0){server->_cancelState->stopped.store(true);[server.rpcCondition lock];[server.rpcCondition broadcast];[server.rpcCondition unlock];}
        else{NSDictionary *ack=[server acceptNativeRPCResponse:envelope(@"session",request[@"requestId"],@{@"ok":@(true)})];assert([ack[@"payload"][@"result"][@"accepted"] boolValue]);}
        worker.join();assert(response);assert([response[@"ok"] boolValue]==(n%5!=0));assert(!server.pendingNativeRequest&&!server.nativeResponse);
        server->_cancelState->stopped.store(false);rejection([server acceptNativeRPCResponse:envelope(@"session",request[@"requestId"],@{@"ok":@(true)})],@"no_pending_native_rpc");
    }}
    NSDictionary *denied=[server executeNativeRPCMethod:@"tap" arguments:@[] sessionId:@"old-session"];assert(![denied[@"ok"] boolValue]);assert(!server.pendingNativeRequest);
}
int main(){@autoreleasepool{ownerCases();responseCases();workerCases();puts("Helper identity Foundation passed: actual response admission/condition/worker/cleanup, first response wins, stale helper/session/request rejection, legacy omission, stop wakeup, 100 worker lifecycles and pre-dispatch status gate.");}return 0;}
