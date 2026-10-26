#ifndef TLINK_HELPER_COMMAND_GATE_H
#define TLINK_HELPER_COMMAND_GATE_H
#include "TLinkHelperSocketIO.h"
#include <condition_variable>
#include <mutex>

// One command owner; cancellation/stop and registration share the predicate lock.
// Guards borrow this gate, which must outlive all callers and cancellation sources.
class TLinkHelperCommandGate {
    std::mutex mutex_;
    std::condition_variable changed_;
    bool held_=false,open_=true;
    size_t waiters_=0;
public:
    class Cancellation {
        friend class TLinkHelperCommandGate;
        bool cancelled_=false;
    public:
        Cancellation()=default;
        Cancellation(const Cancellation &)=delete;
        Cancellation &operator=(const Cancellation &)=delete;
    };
    using Guard=std::unique_lock<TLinkHelperCommandGate>;
    // BasicLockable support for Guard; production admission always uses acquire.
    void lock(){std::unique_lock<std::mutex> lock(mutex_);changed_.wait(lock,[this]{return !held_;});held_=true;}
    void unlock(){
        {std::lock_guard<std::mutex> lock(mutex_);held_=false;}
        changed_.notify_all();
    }
    Guard acquire(const TLinkHelperIO::Deadline &deadline,Cancellation *cancellation=nullptr){
        std::unique_lock<std::mutex> lock(mutex_);
        ++waiters_;
        struct Count {size_t &value;~Count(){--value;}} count{waiters_};
        while(held_&&open_&&!(cancellation&&cancellation->cancelled_)){
            const int remaining=deadline.remaining(TLinkHelperIO::nowMs());if(!remaining)break;
            changed_.wait_for(lock,std::chrono::milliseconds(remaining));
        }
        if(!open_||(cancellation&&cancellation->cancelled_)||!deadline.remaining(TLinkHelperIO::nowMs()))return {};
        held_=true;
        return Guard(*this,std::adopt_lock);
    }
    void cancel(Cancellation &cancellation){
        {std::lock_guard<std::mutex> lock(mutex_);cancellation.cancelled_=true;}
        changed_.notify_all();
    }
    bool cancelled(const Cancellation &cancellation){std::lock_guard<std::mutex> lock(mutex_);return cancellation.cancelled_;}
    size_t waiters(){std::lock_guard<std::mutex> lock(mutex_);return waiters_;}
    void stop(){{std::lock_guard<std::mutex> lock(mutex_);open_=false;}changed_.notify_all();}
};
#endif
