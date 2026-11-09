#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <utility>
namespace TLinkHelperConsoleQueue {
// Publication is serialized with enqueue; only the serial sink consumes batches.
template<class Entry,std::size_t Limit=64>
class State {
    std::mutex mutex_;
    std::array<std::shared_ptr<Entry>,Limit> pending_{};
    std::size_t count_=0;
    uint64_t token_=0;
    bool accepting_=true,scheduled_=false;
public:
    struct Batch {std::array<std::shared_ptr<Entry>,Limit> entries{};std::size_t count=0;};
    struct Snapshot {bool accepting,scheduled;std::size_t pending;uint64_t token;};
    class Registration {
        // Retire this reference after releasing the lock, including rollback.
        std::shared_ptr<Entry> held_;
        State *owner_;
        std::unique_lock<std::mutex> lock_;
        bool start_;
        uint64_t token_;
    public:
        Registration(State *owner,std::unique_lock<std::mutex> lock,std::shared_ptr<Entry> entry,bool start,uint64_t token)
            :held_(std::move(entry)),owner_(owner),lock_(std::move(lock)),start_(start),token_(token){}
        Registration(const Registration &)=delete;Registration &operator=(const Registration &)=delete;
        Registration(Registration &&other) noexcept
            :held_(std::move(other.held_)),owner_(other.owner_),lock_(std::move(other.lock_)),start_(other.start_),token_(other.token_){other.owner_=nullptr;}
        ~Registration(){if(owner_){owner_->pending_[--owner_->count_].reset();if(start_)owner_->scheduled_=false;}}
        explicit operator bool()const{return owner_!=nullptr;}
        bool schedule()const{return start_;}
        uint64_t token()const{return token_;}
        void commit(){owner_=nullptr;lock_.unlock();}
    };
    explicit State(uint64_t token=0):token_(token){}
    Registration insert(const std::shared_ptr<Entry> &entry){
        std::unique_lock<std::mutex> lock(mutex_);
        if(!scheduled_&&token_==UINT64_MAX)accepting_=false;
        if(!entry||!accepting_||count_==Limit)return Registration(nullptr,std::move(lock),{},false,0);
        const bool start=!scheduled_;if(start){++token_;scheduled_=true;}
        pending_[count_++]=entry;return Registration(this,std::move(lock),entry,start,token_);
    }
    Batch take(uint64_t token){
        Batch result;std::lock_guard<std::mutex> lock(mutex_);
        if(!scheduled_||token!=token_)return result;
        if(!count_){scheduled_=false;return result;}
        result.entries.swap(pending_);result.count=count_;count_=0;return result;
    }
    Batch abandon(uint64_t token){
        Batch result;
        {std::lock_guard<std::mutex> lock(mutex_);
            if(!scheduled_||token!=token_)return result;
            result.entries.swap(pending_);result.count=count_;count_=0;scheduled_=false;
        }
        return result;
    }
    void close(){std::lock_guard<std::mutex> lock(mutex_);accepting_=false;}
    Snapshot snapshot(){std::lock_guard<std::mutex> lock(mutex_);return {accepting_,scheduled_,count_,scheduled_?token_:0};}
};
}
