#ifndef TLINK_VPN_TRANSITION_H
#define TLINK_VPN_TRANSITION_H
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <memory>
#include <mutex>
#include <utility>
// Resumed, initially unarmed source. All resources retire before delivery.
class TLinkVPNTransitionState {
    mutable std::mutex mutex_;
    bool finished_=false;
    id observer_=nil;
    dispatch_source_t timer_=nullptr;
    void (^completion_)(NSDictionary *);
    static void cancelTimer(dispatch_source_t timer){
        if(!timer)return;
        dispatch_source_set_event_handler(timer, ^{});
        dispatch_source_cancel(timer);
    }
    void close(NSDictionary *result,bool deliver){
        id observer=nil;dispatch_source_t timer=nullptr;void (^completion)(NSDictionary *)=nil;
        {
            std::lock_guard<std::mutex> guard(mutex_);
            if(finished_)return;
            finished_=true;observer=observer_;observer_=nil;timer=timer_;timer_=nullptr;
            completion=completion_;completion_=nil; // Release captured user objects outside the mutex, even on abandonment.
        }
        cancelTimer(timer);
        if(observer)[[NSNotificationCenter defaultCenter] removeObserver:observer];
        if(deliver&&completion)completion(result);
    }
public:
    explicit TLinkVPNTransitionState(void (^completion)(NSDictionary *)):completion_([completion copy]){}
    TLinkVPNTransitionState(const TLinkVPNTransitionState &)=delete;
    TLinkVPNTransitionState &operator=(const TLinkVPNTransitionState &)=delete;
    bool finished()const{std::lock_guard<std::mutex> guard(mutex_);return finished_;}
    void installTimer(dispatch_source_t timer){
        bool retired;
        {std::lock_guard<std::mutex> guard(mutex_);if(!finished_&&timer_==timer)return;retired=finished_||timer_!=nullptr;if(!retired)timer_=timer;}
        if(retired)cancelTimer(timer);
    }
    void installObserver(id observer){
        bool retired;
        {std::lock_guard<std::mutex> guard(mutex_);if(!finished_&&observer_==observer)return;retired=finished_||observer_!=nil;if(!retired)observer_=observer;}
        if(retired&&observer)[[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
    void arm(int64_t nanoseconds){
        std::lock_guard<std::mutex> guard(mutex_);
        if(!finished_&&timer_)dispatch_source_set_timer(timer_,dispatch_time(DISPATCH_TIME_NOW,nanoseconds),DISPATCH_TIME_FOREVER,0);
    }
    void finish(NSDictionary *result){close(result,true);}
    void abandon(){close(nil,false);}
};
struct TLinkVPNTransitionSetupScope {
    std::shared_ptr<TLinkVPNTransitionState> state;
    bool committed=false;
    explicit TLinkVPNTransitionSetupScope(std::shared_ptr<TLinkVPNTransitionState> value):state(std::move(value)){}
    ~TLinkVPNTransitionSetupScope(){if(!committed)state->abandon();}
};
#endif
