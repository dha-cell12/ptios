#pragma once
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>
namespace TLinkProductionLogBatch {
struct Group {std::size_t count=0,bytes=0;bool reset=false;};
// Match sequential reset-before-record decisions, including exact/zero lengths.
template<class Length>
Group Plan(uint64_t size,std::size_t limit,std::size_t remaining,Length length){
    Group result;if(!remaining)return result;
    const std::size_t first=length(0);if(first>limit)return result;
    result.reset=size>limit||first>limit-size;
    const uint64_t initial=result.reset?0:size;
    while(result.count<remaining){
        const std::size_t next=length(result.count);
        if(next>limit-initial-result.bytes)break;
        result.bytes+=next;++result.count;
    }
    return result;
}
// Entries are owned by admitted queue blocks, not by this registry. A discarded
// block retires its payload/permit; expired weak metadata is pruned on insertion
// or drain. Registration holds the mutex across asynchronous block submission.
template<class Entry,std::size_t Limit>
class Registry {
    std::mutex mutex_;
    std::vector<std::weak_ptr<Entry>> pending_;
public:
    struct Batch {std::array<std::shared_ptr<Entry>,Limit> entries{};std::size_t count=0;};
    class Registration {
        Registry *owner_=nullptr;
        std::unique_lock<std::mutex> lock_;
        std::size_t index_=0;
    public:
        Registration(Registry *owner,std::unique_lock<std::mutex> lock,std::size_t index)
            :owner_(owner),lock_(std::move(lock)),index_(index){}
        Registration(const Registration &)=delete;
        Registration &operator=(const Registration &)=delete;
        Registration(Registration &&other) noexcept
            :owner_(other.owner_),lock_(std::move(other.lock_)),index_(other.index_){other.owner_=nullptr;}
        ~Registration(){if(owner_)owner_->pending_.erase(owner_->pending_.begin()+index_);}
        explicit operator bool()const{return owner_!=nullptr;}
        void commit(){owner_=nullptr;lock_.unlock();}
    };
    Registry(){pending_.reserve(Limit);}
    Registration insert(const std::shared_ptr<Entry> &entry){
        std::unique_lock<std::mutex> lock(mutex_);
        pending_.erase(std::remove_if(pending_.begin(),pending_.end(),[](const std::weak_ptr<Entry> &p){return p.expired();}),pending_.end());
        if(!entry||pending_.size()>=Limit)return Registration(nullptr,std::move(lock),0);
        pending_.push_back(entry);return Registration(this,std::move(lock),pending_.size()-1);
    }
    Batch take(){
        Batch result;std::lock_guard<std::mutex> lock(mutex_);
        for(const auto &weak:pending_){auto entry=weak.lock();if(entry)result.entries[result.count++]=std::move(entry);}
        pending_.clear();return result;
    }
};
}
