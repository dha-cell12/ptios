#ifndef TLINK_HELPER_RPC_IDENTITY_H
#define TLINK_HELPER_RPC_IDENTITY_H
#include <string>
struct TLinkHelperRPCIdentity {
    std::string helper,session,request;
    static bool valid(const std::string &value){return !value.empty()&&value.size()<=64;}
    enum class Error { None, Invalid, Helper, Session, Request };
    static Error owner(const TLinkHelperRPCIdentity &expected,const TLinkHelperRPCIdentity &actual,bool legacyHelper=false){
        if(!valid(expected.helper)||!valid(expected.session)||!valid(actual.session)||
           (!legacyHelper&&!valid(actual.helper))||(!actual.helper.empty()&&!valid(actual.helper)))return Error::Invalid;
        if((!legacyHelper||!actual.helper.empty())&&expected.helper!=actual.helper)return Error::Helper;
        if(expected.session!=actual.session)return Error::Session;
        return Error::None;
    }
    static Error reply(const TLinkHelperRPCIdentity &expected,const TLinkHelperRPCIdentity &actual,bool legacyHelper=false){
        const Error error=owner(expected,actual,legacyHelper);if(error!=Error::None)return error;
        if(!valid(expected.request)||!valid(actual.request))return Error::Invalid;
        return expected.request==actual.request?Error::None:Error::Request;
    }
};
#ifdef __OBJC__
#import <Foundation/Foundation.h>
static inline std::string TLinkHelperRPCIdentityBytes(id value){
    if(![value isKindOfClass:[NSString class]]||[value length]==0||[value length]>64)return {};
    NSData *data=[value dataUsingEncoding:NSUTF8StringEncoding];
    if(!data||data.length==0||data.length>64)return {};
    return std::string(static_cast<const char *>(data.bytes),data.length);
}
static inline TLinkHelperRPCIdentity TLinkHelperRPCIdentityFrom(id helper,id session,id request){
    return {TLinkHelperRPCIdentityBytes(helper),TLinkHelperRPCIdentityBytes(session),TLinkHelperRPCIdentityBytes(request)};
}
static inline NSString *TLinkHelperRPCIdentityError(TLinkHelperRPCIdentity::Error error){
    using E=TLinkHelperRPCIdentity::Error;
    switch(error){case E::None:return nil;case E::Helper:return @"helper_instance_mismatch";case E::Session:return @"session_mismatch";
        case E::Request:return @"native_request_mismatch";case E::Invalid:return @"invalid_rpc_identity";}
    return @"invalid_rpc_identity";
}
// Correlate before exposing a parsed socket response to any caller.
static inline NSString *TLinkHelperRPCReplyError(NSDictionary *response,NSString *command,NSString *requestId,NSString *sessionId,NSString *helperId){
    if(![response isKindOfClass:[NSDictionary class]])return @"invalid_rpc_response";
    if(![response[@"command"] isEqual:command]&&![response[@"command"] isEqual:@"error"])return @"response_command_mismatch";
    if(!TLinkHelperRPCIdentity::valid(TLinkHelperRPCIdentityBytes(response[@"helperInstanceId"])))return @"invalid_rpc_identity";
    if(![response[@"requestId"] isEqual:requestId])return @"response_request_mismatch";
    if(sessionId&&![response[@"sessionId"] isEqual:sessionId])return @"session_mismatch";
    if(helperId&&![response[@"helperInstanceId"] isEqual:helperId])return @"helper_instance_mismatch";
    return nil;
}
static inline NSString *TLinkHelperRPCStartError(NSDictionary *response){
    NSDictionary *payload=[response[@"payload"] isKindOfClass:[NSDictionary class]]?response[@"payload"]:nil;
    const auto expected=TLinkHelperRPCIdentityFrom(response[@"helperInstanceId"],response[@"sessionId"],nil);
    const auto actual=TLinkHelperRPCIdentityFrom(response[@"helperInstanceId"],payload[@"activeSessionId"],nil);
    return TLinkHelperRPCIdentityError(TLinkHelperRPCIdentity::owner(expected,actual));
}
// Must run before dispatching a native effect from a polled status snapshot.
static inline NSString *TLinkHelperRPCStatusError(NSDictionary *response,NSString *helperId,NSString *sessionId){
    if(![response isKindOfClass:[NSDictionary class]])return @"invalid_rpc_response";
    NSDictionary *payload=[response[@"payload"] isKindOfClass:[NSDictionary class]]?response[@"payload"]:nil;
    const auto expected=TLinkHelperRPCIdentityFrom(helperId,sessionId,nil);
    auto actual=TLinkHelperRPCIdentityFrom(response[@"helperInstanceId"],response[@"sessionId"],nil);
    auto error=TLinkHelperRPCIdentity::owner(expected,actual);if(error!=TLinkHelperRPCIdentity::Error::None)return TLinkHelperRPCIdentityError(error);
    actual.session=TLinkHelperRPCIdentityBytes(payload[@"activeSessionId"]);
    error=TLinkHelperRPCIdentity::owner(expected,actual);if(error!=TLinkHelperRPCIdentity::Error::None)return TLinkHelperRPCIdentityError(error);
    id pending=payload[@"nativeRPCRequest"];
    if(pending){
        if(![payload[@"state"] isEqual:@"running"])return @"inactive_native_rpc";
        if(![pending isKindOfClass:[NSDictionary class]])return @"invalid_native_request";
        // Older helpers have no nested helperInstanceId; their outer response is still pinned.
        id nestedHelper=pending[@"helperInstanceId"]?:helperId;
        actual=TLinkHelperRPCIdentityFrom(nestedHelper,pending[@"sessionId"],pending[@"requestId"]);
        error=TLinkHelperRPCIdentity::owner(expected,actual);
        if(error!=TLinkHelperRPCIdentity::Error::None)return TLinkHelperRPCIdentityError(error);
        if(!TLinkHelperRPCIdentity::valid(actual.request))return @"invalid_rpc_identity";
    }
    return nil;
}
// Caller holds rpcCondition across this check and the first-response publication.
static inline NSString *TLinkHelperRPCResponseError(NSString *helperId,NSString *sessionId,NSDictionary *pending,
                                                    NSDictionary *envelope,bool stopped){
    if(stopped)return @"native_rpc_stopped";
    if(!pending)return @"no_pending_native_rpc";
    NSDictionary *payload=[envelope[@"payload"] isKindOfClass:[NSDictionary class]]?envelope[@"payload"]:nil;
    if(![payload[@"result"] isKindOfClass:[NSDictionary class]])return @"invalid_native_result";
    auto expected=TLinkHelperRPCIdentityFrom(helperId,sessionId,pending[@"requestId"]);
    auto current=TLinkHelperRPCIdentityFrom(pending[@"helperInstanceId"]?:helperId,pending[@"sessionId"],pending[@"requestId"]);
    auto error=TLinkHelperRPCIdentity::reply(expected,current);if(error!=TLinkHelperRPCIdentity::Error::None)return TLinkHelperRPCIdentityError(error);
    const auto actual=TLinkHelperRPCIdentityFrom(envelope[@"helperInstanceId"],envelope[@"sessionId"],payload[@"requestId"]);
    // Legacy callers may omit helperInstanceId, but cannot omit session/request identity.
    if(envelope[@"helperInstanceId"]&&actual.helper.empty())return @"invalid_rpc_identity";
    return TLinkHelperRPCIdentityError(TLinkHelperRPCIdentity::reply(expected,actual,envelope[@"helperInstanceId"]==nil));
}
#endif
#endif
