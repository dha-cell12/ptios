#ifndef TLINK_VPN_BROKER_BUDGET_H
#define TLINK_VPN_BROKER_BUDGET_H
#include "TLinkVPNBrokerIngress.h"
#include <algorithm>
#include <cmath>

namespace TLinkVPNBrokerBudget {
struct WaitWindow {
    TLinkVPNBrokerIngress::Window request;
    uint64_t startedAt;
    bool valid;
    TLinkHelperIO::Deadline phase;
    WaitWindow(const TLinkVPNBrokerIngress::Window &outer,uint64_t started,int limitMs)
        :request(outer),startedAt(started),valid(outer.remaining(started)>0&&limitMs>0),phase(started,limitMs){
        phase.end=std::min(phase.end,request.deadline.end);
    }
    int remaining(uint64_t now)const{
        return !valid||now<startedAt?0:std::min(request.remaining(now),phase.remaining(now));
    }
};
static inline TLinkHelperIO::Result writeResponse(
    const TLinkHelperIO::Ops &ops,int fd,const uint8_t *bytes,size_t count,
    const TLinkVPNBrokerIngress::Window &request)
{
    if(!request.remaining(ops.now(ops.context)))return {TLinkHelperIO::Code::Timeout};
    return TLinkHelperIO::writeBytes(ops,fd,bytes,count,request.deadline);
}
#if !defined(_WIN32)
static inline TLinkHelperIO::Ops posixWriteOps(){
    auto ops=TLinkHelperIO::posixOps();
    ops.send=[](void *,int fd,const uint8_t *bytes,size_t count,int &error)->ptrdiff_t{
        int flags=MSG_DONTWAIT;
#ifdef MSG_NOSIGNAL
        flags|=MSG_NOSIGNAL;
#endif
        const ssize_t sent=::send(fd,bytes,count,flags);
        if(sent<0)error=errno;
        return sent;
    };
    return ops;
}
#endif
}

#ifdef __OBJC__
#include <memory>
#include <mutex>
// Callback owns only this state, never the client socket or admission slot.
class TLinkVPNBrokerCompletion {
    std::mutex mutex_;
    bool ready_=false,closed_=false;
    NSDictionary *value_=nil;
    dispatch_semaphore_t signal_=dispatch_semaphore_create(0);
public:
    bool valid()const{return signal_!=nullptr;}
    void complete(NSDictionary *value){
        std::lock_guard<std::mutex> guard(mutex_);
        if(closed_||ready_)return;
        value_=value;ready_=true;
        dispatch_semaphore_signal(signal_);
    }
    bool wait(int milliseconds){
        return dispatch_semaphore_wait(signal_,dispatch_time(DISPATCH_TIME_NOW,
            static_cast<int64_t>(milliseconds)*NSEC_PER_MSEC))==0;
    }
    template<class Check> NSDictionary *finishChecked(Check timely){
        std::lock_guard<std::mutex> guard(mutex_);
        if(closed_)return nil;
        const bool accepted=timely(); // Sample the deadline after acquiring the result lock.
        closed_=true;
        NSDictionary *result=accepted&&ready_?value_:nil;
        value_=nil;
        return result;
    }
    NSDictionary *finish(bool timely){return finishChecked([timely]{return timely;});}
    void abandon(){(void)finish(false);}
};
struct TLinkVPNBrokerCompletionScope {
    std::shared_ptr<TLinkVPNBrokerCompletion> state;
    ~TLinkVPNBrokerCompletionScope(){state->abandon();}
};
#endif
#endif
