#ifndef TLINK_AX_ADMISSION_H
#define TLINK_AX_ADMISSION_H
#include <atomic>
namespace TLinkAXAdmission {
enum : unsigned {MaxPending=8};
class Lease;
class State {
    std::atomic<unsigned> pending_{0};
    friend class Lease;
    bool acquire(){
        unsigned count=pending_.load();
        while(count<MaxPending){if(pending_.compare_exchange_weak(count,count+1))return true;}
        return false;
    }
    void retire(){pending_.fetch_sub(1);}
public:
    unsigned pending()const{return pending_.load();}
};
// The state outlives all synchronous callers. No job captures the stack lease;
// it remains charged through queue residence, work and public result handling.
class Lease {
    State &state_;
    std::atomic<bool> held_;
public:
    explicit Lease(State &state):state_(state),held_(state_.acquire()){}
    ~Lease(){release();}
    bool held()const{return held_.load();}
    void release(){if(held_.exchange(false))state_.retire();}
    Lease(const Lease &)=delete;Lease &operator=(const Lease &)=delete;
};
}
#endif
