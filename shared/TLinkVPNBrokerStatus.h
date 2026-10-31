#ifndef TLINK_VPN_BROKER_STATUS_H
#define TLINK_VPN_BROKER_STATUS_H
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <type_traits>
#include <utility>
#include <vector>

// Pending reads only: no retained result or deadline renewal for their waiters.
// Caller supplies pending-work admission; detached flights still own callbacks.
// Caller supplies pending-work admission; detached flights still own callbacks.
template<class Callback> class TLinkVPNBrokerStatus {
    static_assert(std::is_nothrow_move_constructible<Callback>::value,"callback moves must not throw");
    struct Flight {
        uint64_t startedAt;
        bool completed=false;
        std::vector<Callback> callbacks;
        explicit Flight(uint64_t now):startedAt(now){callbacks.reserve(8);}
    };
    struct State {std::mutex mutex;std::shared_ptr<Flight> current;};
    std::shared_ptr<State> state_=std::make_shared<State>();
public:
    enum : size_t {WaiterLimit=8};
    enum : uint64_t {JoinWindowMs=8000};
    class Join {
        std::shared_ptr<State> state_;
        std::shared_ptr<Flight> flight_;
        bool leader_=false;
    public:
        Join()=default;
        Join(std::shared_ptr<State> state,std::shared_ptr<Flight> flight,bool leader)
            :state_(std::move(state)),flight_(std::move(flight)),leader_(leader){}
        explicit operator bool()const{return static_cast<bool>(flight_);}
        bool leader()const{return leader_;}
        std::vector<Callback> take()const{
            std::vector<Callback> callbacks;
            if(!state_||!leader_)return callbacks;
            {
                std::lock_guard<std::mutex> guard(state_->mutex);
                if(flight_->completed)return callbacks;
                flight_->completed=true;
                callbacks.swap(flight_->callbacks);
                if(state_->current==flight_)state_->current.reset();
            }
            return callbacks;
        }
        // Starter unwind removes joinability, not evidence of backend completion.
        void detach()const{
            if(!state_||!leader_)return;
            std::shared_ptr<Flight> retired;
            {
                std::lock_guard<std::mutex> guard(state_->mutex);
                if(state_->current==flight_)retired=std::move(state_->current);
            }
        }
    };
    TLinkVPNBrokerStatus()=default;
    TLinkVPNBrokerStatus(const TLinkVPNBrokerStatus &)=delete;
    TLinkVPNBrokerStatus &operator=(const TLinkVPNBrokerStatus &)=delete;
    Join join(Callback callback,uint64_t now){
        Join result;
        std::shared_ptr<Flight> retired;
        {
            std::lock_guard<std::mutex> guard(state_->mutex);
            if(now==UINT64_MAX||(state_->current&&now<state_->current->startedAt))return result;
            if(state_->current&&now-state_->current->startedAt>=JoinWindowMs)
                retired=std::move(state_->current);
            bool leader=false;
            if(!state_->current){state_->current=std::make_shared<Flight>(now);leader=true;}
            if(state_->current->callbacks.size()>=WaiterLimit)return result;
            state_->current->callbacks.push_back(std::move(callback));
            result=Join(state_,state_->current,leader);
        }
        return result;
    }
    void invalidate(){
        std::shared_ptr<Flight> retired;
        {
            std::lock_guard<std::mutex> guard(state_->mutex);
            retired=std::move(state_->current);
        }
    }
    size_t waiting()const{
        std::lock_guard<std::mutex> guard(state_->mutex);
        return state_->current?state_->current->callbacks.size():0;
    }
};

#ifdef __OBJC__
#import <Foundation/Foundation.h>
typedef void (^TLinkVPNBrokerStatusReply)(NSDictionary *);
typedef void (^TLinkVPNBrokerStatusStart)(TLinkVPNBrokerStatusReply);
using TLinkVPNBrokerStatusOwner=TLinkVPNBrokerStatus<std::function<void(NSDictionary *)>>;
static inline void TLinkVPNBrokerReadStatus(TLinkVPNBrokerStatusOwner &owner,uint64_t now,
    TLinkVPNBrokerStatusStart starter,TLinkVPNBrokerStatusReply completion)
{
    if(!completion)return;
    TLinkVPNBrokerStatusReply copied=[completion copy];
    auto joined=owner.join([copied](NSDictionary *value){copied(value);},now);
    if(!joined){completion(@{@"ok":@0,@"code":@"vpn_broker_busy"});return;}
    if(!joined.leader())return;
    @try {
        try {
            starter(^(NSDictionary *value){
                auto callbacks=joined.take();
                for(auto &callback:callbacks){
                    @try {try {callback(value);}catch(...) {}}
                    @catch(NSException *exception){(void)exception;}
                }
            });
        }catch(...){joined.detach();throw;}
    }@catch(NSException *exception){joined.detach();@throw exception;}
}
#endif
#endif
