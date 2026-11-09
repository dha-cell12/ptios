#pragma once
#include "TLinkConsoleDrainSchedule.h"
@protocol TLinkConsoleDrainOwner<NSObject>
- (void)drainConsoleLogsForToken:(uint64_t)token;
- (void)abandonConsoleLogsForToken:(uint64_t)token;
@end
struct TLinkConsoleDrainTicket {
    id<TLinkConsoleDrainOwner> owner;
    uint64_t token;
    TLinkConsoleDrainTicket(id<TLinkConsoleDrainOwner> value,uint64_t valueToken):owner(value),token(valueToken){}
    TLinkConsoleDrainTicket(const TLinkConsoleDrainTicket &)=delete;
    TLinkConsoleDrainTicket &operator=(const TLinkConsoleDrainTicket &)=delete;
    ~TLinkConsoleDrainTicket() noexcept {
        @autoreleasepool {@try {try {[owner abandonConsoleLogsForToken:token];}catch(...) {}}
            @catch(NSException *exception){(void)exception;}}
    }
    void run(){[owner drainConsoleLogsForToken:token];}
};
