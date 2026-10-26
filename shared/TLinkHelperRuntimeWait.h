#ifndef TLINK_HELPER_RUNTIME_WAIT_H
#define TLINK_HELPER_RUNTIME_WAIT_H
#include "TLinkHelperChangeWait.h"
class TLinkHelperRuntimeWindow {
    uint64_t end_;
public:
    TLinkHelperRuntimeWindow(uint64_t now,uint64_t duration){duration=std::min<uint64_t>(300000,duration);end_=now>UINT64_MAX-duration?UINT64_MAX:now+duration;}
    int budget(uint64_t now,int maximum)const{return maximum<=0||now>=end_?0:static_cast<int>(std::min<uint64_t>(static_cast<uint64_t>(maximum),end_-now));}
    bool expired(uint64_t now)const{return now>=end_;}
};
#ifdef __OBJC__
#import <CoreFoundation/CoreFoundation.h>
// Negotiation is session-local. Unknown/missing contracts use the legacy path; malformed
// cursors after both contracts match are errors rather than permission to lose wakeups.
static inline int TLinkHelperRuntimeCursor(NSDictionary *payload,uint64_t &sequence){
    if(![payload[@"changeWaitContract"] isEqual:@"session_native_rpc_v1"]||
       ![payload[@"sessionSnapshotContract"] isEqual:@"lifecycle_rpc_owner_v1"])return 0;
    return TLinkHelperWireTime(payload[@"changeSequence"],sequence)&&sequence>0?1:-1;
}
static inline NSString *TLinkHelperRuntimeHintError(NSDictionary *reply,uint64_t after){
    id payload=reply[@"payload"];uint64_t sequence=0;
    if(![payload isKindOfClass:[NSDictionary class]]||[payload count]!=3||!TLinkHelperWireTime(payload[@"sequence"],sequence)||sequence<after||
        ![payload[@"changed"] isKindOfClass:[NSNumber class]]||CFGetTypeID((__bridge CFTypeRef)payload[@"changed"])!=CFBooleanGetTypeID())return @"invalid_change_hint";
    const bool changed=[payload[@"changed"] boolValue];
    if(changed!=(sequence>after)||![payload[@"reason"] isEqual:changed?@"changed":@"timeout"])return @"invalid_change_hint";
    return nil;
}
static inline NSString *TLinkHelperRuntimeErrorCode(NSDictionary *reply){
    id error=reply[@"error"];return [error isKindOfClass:[NSString class]]?error:([error isKindOfClass:[NSDictionary class]]&&[error[@"message"] isKindOfClass:[NSString class]]?error[@"message"]:@"helper_transport_failed");
}
static inline bool TLinkHelperRuntimeRetryWait(NSString *error){
    return [@[@"change_wait_busy",@"io_timeout",@"empty_frame",@"connect_failed",@"read_failed",@"write_failed"] containsObject:error];
}
#endif
#endif
