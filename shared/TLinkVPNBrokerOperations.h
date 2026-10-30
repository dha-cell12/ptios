#ifndef TLINK_VPN_BROKER_OPERATIONS_H
#define TLINK_VPN_BROKER_OPERATIONS_H
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <utility>

// Process-local pending manager work. Waiter timeout is not completion evidence.
class TLinkVPNBrokerOperations {
public:
    enum : size_t {Limit=8};
    struct Stats {size_t active=0,peak=0;uint64_t admitted=0,completed=0,cancelled=0,rejected=0;};
private:
    struct Slot {uint64_t id=0;bool started=false,returned=false,completed=false;};
    struct State {
        std::mutex mutex;std::array<Slot,Limit> slots{};Stats stats;uint64_t lastId;
        explicit State(uint64_t cursor):lastId(cursor){}
        static void bump(uint64_t &value){if(value!=UINT64_MAX)++value;}
        void retire(Slot &slot,bool completed){slot=Slot{};--stats.active;bump(completed?stats.completed:stats.cancelled);}
    };
    std::shared_ptr<State> state_;
public:
    class Ticket {
        std::shared_ptr<State> state_;size_t index_;uint64_t id_;
        Slot *current(){Slot &slot=state_->slots[index_];return slot.id==id_?&slot:nullptr;}
    public:
        Ticket(std::shared_ptr<State> state,size_t index,uint64_t id)noexcept:state_(std::move(state)),index_(index),id_(id){}
        Ticket(const Ticket &)=delete;Ticket &operator=(const Ticket &)=delete;
        ~Ticket(){cancel();}
        bool cancel(){
            std::lock_guard<std::mutex> guard(state_->mutex);Slot *slot=current();
            if(!slot||slot->started)return false;
            state_->retire(*slot,false);return true;
        }
        bool start(){
            std::lock_guard<std::mutex> guard(state_->mutex);Slot *slot=current();
            if(!slot||slot->started)return false;
            slot->started=true;return true;
        }
        bool complete(){
            std::lock_guard<std::mutex> guard(state_->mutex);Slot *slot=current();
            if(!slot||!slot->started||slot->completed)return false;
            slot->completed=true;if(slot->returned)state_->retire(*slot,true);return true;
        }
        bool returned(){
            std::lock_guard<std::mutex> guard(state_->mutex);Slot *slot=current();
            if(!slot||!slot->started||slot->returned)return false;
            slot->returned=true;if(slot->completed)state_->retire(*slot,true);return true;
        }
    };
    // Cursor permits deterministic identity-exhaustion qualification; normal start is zero.
    explicit TLinkVPNBrokerOperations(uint64_t lastTicket=0):state_(std::make_shared<State>(lastTicket)){}
    TLinkVPNBrokerOperations(const TLinkVPNBrokerOperations &)=delete;
    TLinkVPNBrokerOperations &operator=(const TLinkVPNBrokerOperations &)=delete;
    std::shared_ptr<Ticket> acquire(){
        std::lock_guard<std::mutex> guard(state_->mutex);
        if(state_->stats.active<Limit&&state_->lastId!=UINT64_MAX){
            for(size_t i=0;i<Limit;++i)if(!state_->slots[i].id){
                const uint64_t id=state_->lastId+1;
                auto ticket=std::make_shared<Ticket>(state_,i,id); // Allocate before publication.
                state_->lastId=id;state_->slots[i].id=id;++state_->stats.active;State::bump(state_->stats.admitted);
                if(state_->stats.active>state_->stats.peak)state_->stats.peak=state_->stats.active;
                return ticket;
            }
        }
        State::bump(state_->stats.rejected);return {};
    }
    Stats stats()const{std::lock_guard<std::mutex> guard(state_->mutex);return state_->stats;}
};
struct TLinkVPNBrokerStarterScope {
    std::shared_ptr<TLinkVPNBrokerOperations::Ticket> ticket;
    ~TLinkVPNBrokerStarterScope(){ticket->returned();}
};
#endif
