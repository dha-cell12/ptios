#ifndef TLINK_HELPER_REQUEST_DEADLINE_H
#define TLINK_HELPER_REQUEST_DEADLINE_H
#include "TLinkHelperSocketIO.h"
namespace TLinkHelperIO {
static const uint64_t MaxWireTime=9007199254740991ULL;
static inline bool validSenderWindow(uint64_t issued,uint64_t expires){
    return issued<=MaxWireTime&&expires<=MaxWireTime&&expires>issued&&expires-issued<=30000;
}
// Same boot-local continuous clock; never restart the sender budget at accept/parse/lock.
static inline bool constrainToSender(Deadline &local,uint64_t issued,uint64_t expires,uint64_t now){
    if(!validSenderWindow(issued,expires)||issued>now||now>=expires||!local.remaining(now))return false;
    local.end=std::min(local.end,expires);return local.remaining(now)>0;
}
}
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <cmath>
static inline bool TLinkHelperWireTime(id value,uint64_t &out){
    if(![value isKindOfClass:[NSNumber class]]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return false;
    const double number=[value doubleValue];
    if(!std::isfinite(number)||number<0||number>static_cast<double>(TLinkHelperIO::MaxWireTime)||std::floor(number)!=number)return false;
    out=[value unsignedLongLongValue];return true;
}
// Absence is the explicitly supported legacy contract; malformed presence never falls back.
static inline bool TLinkHelperReadSenderDeadline(NSDictionary *request,bool &present,uint64_t &issued,uint64_t &expires){
    id window=request[@"requestDeadline"];present=window!=nil;if(!present)return true;
    if(![window isKindOfClass:[NSDictionary class]]||[window count]!=3||
       ![window[@"clock"] isKindOfClass:[NSString class]]||![window[@"clock"] isEqualToString:@"mach_continuous_ms_v1"])return false;
    return TLinkHelperWireTime(window[@"issuedMs"],issued)&&TLinkHelperWireTime(window[@"expiresMs"],expires)&&TLinkHelperIO::validSenderWindow(issued,expires);
}
static inline NSDictionary *TLinkHelperSenderDeadline(uint64_t issued,const TLinkHelperIO::Deadline &deadline){
    return @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(issued),@"expiresMs":@(deadline.end)};
}
#endif
#endif
