#ifndef TLINK_HELPER_CLIENT_ADMISSION_H
#define TLINK_HELPER_CLIENT_ADMISSION_H
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <utility>
class TLinkHelperClientAdmission {
public:
    enum : size_t {DefaultLimit=8};
    struct Stats {size_t active=0,peak=0,limit=0;uint64_t admitted=0,finished=0,rejected=0;bool open=true;};
private:
    struct State {std::mutex mutex;Stats stats;explicit State(size_t limit){stats.limit=limit;}};
    std::shared_ptr<State> state_;
public:
    class Lease {
        std::shared_ptr<State> state_;std::atomic<int> fd_;std::atomic<bool> finished_{false};uint64_t acceptedAt_;void (*close_)(int);
    public:
        Lease(std::shared_ptr<State> state,int fd,uint64_t acceptedAt,void (*closer)(int))noexcept
            :state_(std::move(state)),fd_(fd),acceptedAt_(acceptedAt),close_(closer){}
        ~Lease(){finish();}
        void finish(){if(finished_.exchange(true,std::memory_order_acq_rel))return;const int fd=takeDescriptor();if(fd>=0)close_(fd);std::lock_guard<std::mutex> guard(state_->mutex);--state_->stats.active;++state_->stats.finished;}
        Lease(const Lease &)=delete;Lease &operator=(const Lease &)=delete;
        int takeDescriptor(){return fd_.exchange(-1,std::memory_order_acq_rel);}
        uint64_t acceptedAt()const{return acceptedAt_;}
        bool isOpen()const{std::lock_guard<std::mutex> guard(state_->mutex);return state_->stats.open&&!finished_.load(std::memory_order_acquire);}
    };
    explicit TLinkHelperClientAdmission(size_t limit=DefaultLimit):state_(std::make_shared<State>(limit)){}
    TLinkHelperClientAdmission(const TLinkHelperClientAdmission &)=delete;
    TLinkHelperClientAdmission &operator=(const TLinkHelperClientAdmission &)=delete;
    // Success adopts fd. Failure leaves fd with the caller; closer must not throw.
    std::shared_ptr<Lease> acquire(int fd,uint64_t acceptedAt,void (*closer)(int)){
        std::lock_guard<std::mutex> guard(state_->mutex);auto &stats=state_->stats;
        if(fd<0||!closer||!stats.open||stats.active>=stats.limit){++stats.rejected;return {};}
        auto lease=std::make_shared<Lease>(state_,fd,acceptedAt,closer);
        ++stats.active;++stats.admitted;if(stats.active>stats.peak)stats.peak=stats.active;return lease;
    }
    void stop(){std::lock_guard<std::mutex> guard(state_->mutex);state_->stats.open=false;}
    bool isOpen()const{std::lock_guard<std::mutex> guard(state_->mutex);return state_->stats.open;}
    Stats stats()const{std::lock_guard<std::mutex> guard(state_->mutex);return state_->stats;}
};
#endif
