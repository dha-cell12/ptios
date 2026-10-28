#ifndef TLINK_CONSOLE_LOG_BUDGET_H
#define TLINK_CONSOLE_LOG_BUDGET_H
#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <mutex>
#include <utility>
static const size_t TLinkConsoleLogLineBytes=16*1024;
static const size_t TLinkConsoleLogMaxPending=64;
static const size_t TLinkConsoleLogMessageUnits=4096;
static const size_t TLinkConsoleLogLevelUnits=64;
struct TLinkConsoleLogStats {
    uint64_t accepted=0,dropped=0,truncated=0,writeFailures=0;
    size_t pending=0,peakPending=0;
};
class TLinkConsoleLogBudget {
    std::mutex mutex_;TLinkConsoleLogStats stats_;
    static void increment(uint64_t &value){if(value!=std::numeric_limits<uint64_t>::max())++value;}
public:
    bool reserve(){std::lock_guard<std::mutex> guard(mutex_);if(stats_.pending>=TLinkConsoleLogMaxPending){increment(stats_.dropped);return false;}++stats_.pending;stats_.peakPending=std::max(stats_.peakPending,stats_.pending);return true;}
    void release(){std::lock_guard<std::mutex> guard(mutex_);if(stats_.pending)--stats_.pending;}
    void accepted(bool truncated){std::lock_guard<std::mutex> guard(mutex_);increment(stats_.accepted);if(truncated)increment(stats_.truncated);}
    void dropped(){std::lock_guard<std::mutex> guard(mutex_);increment(stats_.dropped);}
    void failed(){std::lock_guard<std::mutex> guard(mutex_);increment(stats_.writeFailures);}
    TLinkConsoleLogStats snapshot(){std::lock_guard<std::mutex> guard(mutex_);return stats_;}
};
class TLinkConsoleLogPermit {
    std::shared_ptr<TLinkConsoleLogBudget> budget_;std::atomic<bool> armed_{false};
public:
    explicit TLinkConsoleLogPermit(std::shared_ptr<TLinkConsoleLogBudget> budget):budget_(std::move(budget)){}
    ~TLinkConsoleLogPermit(){finish();}
    void finish(){if(armed_.exchange(false,std::memory_order_acq_rel))budget_->release();}
    static std::shared_ptr<TLinkConsoleLogPermit> acquire(const std::shared_ptr<TLinkConsoleLogBudget> &budget){
        if(!budget)return nullptr;
        // Allocate before reserving so allocation failure cannot leak a charge.
        auto permit=std::make_shared<TLinkConsoleLogPermit>(budget);
        if(!budget->reserve())return nullptr;
        permit->armed_.store(true,std::memory_order_release);return permit;
    }
};
template<class Character>
size_t TLinkConsoleLogPrefix(size_t length,size_t limit,Character at){
    size_t count=std::min(length,limit);
    if(count&&count<length&&at(count-1)>=0xd800&&at(count-1)<=0xdbff&&at(count)>=0xdc00&&at(count)<=0xdfff)--count;
    return count;
}
#endif
