#ifndef TLINK_HELPER_START_RECEIPT_H
#define TLINK_HELPER_START_RECEIPT_H
#include "TLinkHelperSocketIO.h"
#include "TLinkHelperRPCIdentity.h"
// One read-only lookup, using only time left in the original start call.
class TLinkHelperStartRecoveryWindow {
    TLinkHelperIO::Deadline deadline_;
public:
    TLinkHelperStartRecoveryWindow(uint64_t now,int timeout):deadline_(now,timeout){}
    int remaining(uint64_t now)const{return deadline_.remaining(now);}
    int lookupBudget(uint64_t now)const{return std::min(remaining(now),500);}
    uint64_t end()const{return deadline_.end;}
};
#ifdef __OBJC__
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
static inline bool TLinkHelperStartRecoveryAllowed(NSDictionary *result){
    if(result[@"response"]||![result[@"error"] isKindOfClass:[NSString class]])return false;
    return [@[@"read_failed",@"write_failed",@"empty_frame",@"io_timeout"] containsObject:result[@"error"]];
}
static inline NSString *TLinkHelperStartReceiptOptInError(NSDictionary *request){
    NSDictionary *payload=[request[@"payload"] isKindOfClass:[NSDictionary class]]?request[@"payload"]:nil;
    id contract=payload[@"startReceiptContract"];
    if(!contract)return nil; // Unextended clients retain their old start behavior.
    if(![contract isEqual:@"accepted_start_v1"]||request[@"sessionId"]||
       !TLinkHelperRPCIdentity::valid(TLinkHelperRPCIdentityBytes(request[@"requestId"])))return @"invalid_start_receipt_request";
    return nil;
}
static inline NSString *TLinkHelperStartReceiptQueryError(NSDictionary *request){
    NSDictionary *payload=[request[@"payload"] isKindOfClass:[NSDictionary class]]?request[@"payload"]:nil;
    if(![payload[@"startReceiptContract"] isEqual:@"accepted_start_v1"]||request[@"sessionId"]||
       !TLinkHelperRPCIdentity::valid(TLinkHelperRPCIdentityBytes(payload[@"startRequestId"])))return @"invalid_start_receipt_query";
    return nil;
}
// Bounded metadata only: no script, manifest, native result or error/log text.
static inline NSDictionary *TLinkHelperMakeStartReceipt(NSDictionary *request,NSString *helper,NSString *session,NSString *run){
    NSDictionary *response=[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStart helperInstanceId:helper
        sessionId:session requestId:request[@"requestId"] payload:@{@"state":@"starting",@"activeSessionId":session,@"runId":run}];
    return @{@"contract":@"accepted_start_v1",@"response":response};
}
static inline NSString *TLinkHelperRecoveredStartError(NSDictionary *status,NSString *requestId,NSString *helper){
    NSDictionary *receipt=[status[@"payload"] isKindOfClass:[NSDictionary class]]?status[@"payload"]:nil;
    NSDictionary *response=[receipt[@"response"] isKindOfClass:[NSDictionary class]]?receipt[@"response"]:nil;
    NSDictionary *payload=[response[@"payload"] isKindOfClass:[NSDictionary class]]?response[@"payload"]:nil;
    if(receipt.count!=2||response.count!=6||payload.count!=3||![receipt[@"contract"] isEqual:@"accepted_start_v1"]||![response[@"command"] isEqual:kTLinkJSHelperCmdStart]||
       ![TLinkJSHelperProtocol validateEnvelope:response error:nil]||response[@"error"]||response[@"connectionLease"]||
       ![response[@"payload"] isKindOfClass:[NSDictionary class]])
        return @"invalid_start_receipt";
    NSString *error=TLinkHelperRPCReplyError(response,kTLinkJSHelperCmdStart,requestId,nil,helper);
    if(error)return error;
    if(![status[@"helperInstanceId"] isEqual:response[@"helperInstanceId"]])return @"helper_instance_mismatch";
    if(![payload[@"state"] isEqual:@"starting"]||
       !TLinkHelperRPCIdentity::valid(TLinkHelperRPCIdentityBytes(payload[@"runId"])))return @"invalid_start_receipt";
    return TLinkHelperRPCStartError(response);
}
#endif
#endif
