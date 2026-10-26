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
// One status reconciliation episode, including its first I/O attempt and backoffs.
// A valid, ownership-checked snapshot ends the episode; transport faults cannot
// renew it. This policy never authorizes repeating start or native effects.
class TLinkHelperStatusRecovery {
    TLinkHelperIO::Deadline deadline_{0,0};
    unsigned attempts_=0;
public:
    enum : int {MaxAttempts=3,WindowMs=1500,AttemptMs=500,BackoffMs=100};
    int begin(uint64_t now,int callerBudget){
        if(callerBudget<=0||attempts_>=MaxAttempts)return 0;
        if(!attempts_)deadline_=TLinkHelperIO::Deadline(now,WindowMs);
        const int budget=std::min(std::min(callerBudget,static_cast<int>(AttemptMs)),deadline_.remaining(now));
        if(budget>0)++attempts_;
        return budget;
    }
    int remaining(uint64_t now)const{return attempts_?deadline_.remaining(now):0;}
    bool expired(uint64_t now)const{return attempts_&&!remaining(now);}
    int retryDelay(uint64_t now)const{
        return attempts_&&attempts_<MaxAttempts?std::min(static_cast<int>(BackoffMs),remaining(now)):0;
    }
    void reset(){attempts_=0;deadline_=TLinkHelperIO::Deadline(0,0);}
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
static inline bool TLinkHelperRuntimeRetryStatus(NSDictionary *reply){
    // Local transport errors have no correlated response. A remote application
    // rejection, invalid response or ownership failure is never a reconnect hint.
    id ok=reply[@"ok"],error=reply[@"error"];
    return !reply[@"response"]&&[ok isKindOfClass:[NSNumber class]]&&CFGetTypeID((__bridge CFTypeRef)ok)==CFBooleanGetTypeID()&&![ok boolValue]&&
        [error isKindOfClass:[NSString class]]&&
        [@[@"io_timeout",@"empty_frame",@"connect_failed",@"read_failed",@"write_failed"] containsObject:error];
}
#endif
#endif
