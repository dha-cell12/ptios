#ifndef TLINK_SUPERVISOR_ENSURE_ADMISSION_H
#define TLINK_SUPERVISOR_ENSURE_ADMISSION_H
#include <atomic>
#include <memory>
#include <utility>
namespace TLinkSupervisorEnsureAdmission {
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
class Lease {
    const std::shared_ptr<State> state_;
    std::atomic<bool> held_;
public:
    explicit Lease(std::shared_ptr<State> state):state_(std::move(state)),held_(state_&&state_->acquire()){}
    ~Lease(){release();}
    bool held()const{return held_.load();}
    void release(){if(held_.exchange(false))state_->retire();}
    Lease(const Lease &)=delete;Lease &operator=(const Lease &)=delete;
};
struct Scope {
    std::shared_ptr<Lease> lease;
    ~Scope(){if(lease)lease->release();}
};
}
#endif
