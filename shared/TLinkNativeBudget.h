#ifndef TLINK_NATIVE_BUDGET_H
#define TLINK_NATIVE_BUDGET_H
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include <utility>

using TLinkNativeClock = std::chrono::steady_clock;
inline uint64_t TLinkNativeNowNs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(TLinkNativeClock::now().time_since_epoch()).count());
}
inline uint64_t TLinkNativeDeadline(double seconds) {
    if (!(seconds > 0)) return 0;
    const long double duration = static_cast<long double>(seconds) * 1000000000.0L;
    const uint64_t now = TLinkNativeNowNs();
    const uint64_t room = static_cast<uint64_t>(INT64_MAX) - std::min(now, static_cast<uint64_t>(INT64_MAX));
    return now + (duration >= room ? room : static_cast<uint64_t>(duration));
}
class TLinkNativeCancellation {
    std::atomic_bool cancelled_{false};
    std::mutex mutex_;
    std::condition_variable changed_;
public:
    void cancel() {
        { std::lock_guard<std::mutex> lock(mutex_); cancelled_.store(true, std::memory_order_release); }
        changed_.notify_all();
    }
    bool cancelled() const { return cancelled_.load(std::memory_order_acquire); }
    void waitUntil(uint64_t end) {
        std::unique_lock<std::mutex> lock(mutex_);
        changed_.wait_until(lock, TLinkNativeClock::time_point(std::chrono::nanoseconds(end)), [&] { return cancelled(); });
    }
};
enum class TLinkNativeStop { None, Cancelled, Deadline, OutputLimit };
class TLinkNativeBudget {
    std::shared_ptr<TLinkNativeCancellation> cancellation_;
    std::shared_ptr<TLinkNativeBudget> parent_;
    uint64_t deadline_;
    size_t outputLimit_;
    bool cleanup_, capture_;
    std::atomic_bool overflow_{false};
    mutable std::mutex responseMutex_;
    std::vector<uint8_t> response_;
public:
    TLinkNativeBudget(std::shared_ptr<TLinkNativeCancellation> cancellation, uint64_t deadline,
                      size_t outputLimit, bool cleanup = false, bool capture = false)
      : cancellation_(std::move(cancellation)), deadline_(deadline), outputLimit_(outputLimit), cleanup_(cleanup), capture_(capture) {}
    // A task-local deadline shares cancellation/output with its caller without
    // shortening the caller or moving its response into a different sink.
    TLinkNativeBudget(uint64_t deadline, std::shared_ptr<TLinkNativeBudget> parent)
      : cancellation_(parent ? parent->cancellation_ : std::shared_ptr<TLinkNativeCancellation>{}), parent_(std::move(parent)),
        deadline_(deadline), outputLimit_(parent_ ? parent_->outputLimit() : 1024*1024), cleanup_(false), capture_(parent_ && parent_->capturesResponse()) {
        if (parent_ && parent_->deadline()) deadline_ = deadline_ ? std::min(deadline_, parent_->deadline()) : parent_->deadline();
    }
    uint64_t deadline() const { return deadline_; }
    bool cleanup() const { return cleanup_; }
    bool capturesResponse() const { return capture_; }
    size_t outputLimit() const { return outputLimit_; }
    TLinkNativeStop reason() const {
        if (parent_) { const auto inherited=parent_->reason(); if(inherited!=TLinkNativeStop::None)return inherited; }
        if (overflow_.load(std::memory_order_acquire)) return TLinkNativeStop::OutputLimit;
        if (!cleanup_) {
            if (cancellation_ && cancellation_->cancelled()) return TLinkNativeStop::Cancelled;
            if (deadline_ && TLinkNativeNowNs() >= deadline_) return TLinkNativeStop::Deadline;
        }
        return TLinkNativeStop::None;
    }
    bool stopped() const { return reason() != TLinkNativeStop::None; }
    bool outputAllowed(size_t bytes) {
        if (parent_) return parent_->outputAllowed(bytes);
        std::lock_guard<std::mutex> lock(responseMutex_);
        if (outputLimit_ && (response_.size() > outputLimit_ || bytes > outputLimit_ - response_.size())) {
            overflow_.store(true, std::memory_order_release); return false;
        }
        return !overflow_.load(std::memory_order_acquire);
    }
    // The caller owns a NUL-terminated message. Scan at most remaining+1 bytes, and admit
    // the complete chunk before appending. Never return a silently truncated success.
    int appendCString(const uint8_t *bytes) {
        if (parent_) return parent_->appendCString(bytes);
        if (!bytes || !capture_ || !outputLimit_) return -1;
        std::lock_guard<std::mutex> lock(responseMutex_);
        if (overflow_.load(std::memory_order_acquire)) return -1;
        const size_t remaining = outputLimit_ - response_.size();
        size_t length = 0;
        while (length <= remaining && bytes[length]) ++length;
        if (length > remaining || overflow_.load(std::memory_order_acquire)) {
            overflow_.store(true, std::memory_order_release); return -1;
        }
        const size_t required = response_.size() + length;
        if (response_.capacity() < required)
            response_.reserve(std::min(outputLimit_, std::max(required, std::max(size_t(128), response_.capacity() * 2))));
        response_.insert(response_.end(), bytes, bytes + length);
        return static_cast<int>(length);
    }
    // Read only after all synchronous producers have returned. The scope owns the buffer.
    const std::vector<uint8_t> &response() const { return parent_ ? parent_->response() : response_; }
    bool waitNs(uint64_t duration) {
        if (stopped()) return false;
        const uint64_t now = TLinkNativeNowNs();
        const uint64_t room = static_cast<uint64_t>(INT64_MAX) - now;
        uint64_t end = now + std::min(duration, room);
        if (!cleanup_ && deadline_) end = std::min(end, deadline_);
        if (cancellation_ && !cleanup_) cancellation_->waitUntil(end);
        else std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(end)));
        return !stopped();
    }
    double remainingSeconds(double maximum) const {
        if (stopped()) return 0;
        if (!deadline_ || cleanup_) return maximum;
        const uint64_t now = TLinkNativeNowNs();
        return now >= deadline_ ? 0 : std::min(maximum, static_cast<double>(deadline_ - now) / 1e9);
    }
};
using TLinkNativeBudgetPtr = std::shared_ptr<TLinkNativeBudget>;
// One TLS slot across translation units (external inline function's local static).
inline TLinkNativeBudgetPtr &TLinkNativeBudgetSlot() { static thread_local TLinkNativeBudgetPtr budget; return budget; }
inline TLinkNativeBudgetPtr TLinkCurrentNativeBudget() { return TLinkNativeBudgetSlot(); }
class TLinkNativeBudgetScope {
    TLinkNativeBudgetPtr previous_;
public:
    explicit TLinkNativeBudgetScope(TLinkNativeBudgetPtr budget) : previous_(TLinkNativeBudgetSlot()) { TLinkNativeBudgetSlot() = std::move(budget); }
    ~TLinkNativeBudgetScope() { TLinkNativeBudgetSlot() = std::move(previous_); }
    TLinkNativeBudgetScope(const TLinkNativeBudgetScope &) = delete;
    TLinkNativeBudgetScope &operator=(const TLinkNativeBudgetScope &) = delete;
};
inline bool TLinkNativeStopped() { auto budget = TLinkCurrentNativeBudget(); return budget && budget->stopped(); }
inline bool TLinkNativeOutputAllowed(size_t bytes) { auto budget = TLinkCurrentNativeBudget(); return !budget || budget->outputAllowed(bytes); }
inline bool TLinkNativeWaitNs(uint64_t ns) {
    auto budget = TLinkCurrentNativeBudget();
    if (budget) return budget->waitNs(ns);
    std::this_thread::sleep_for(std::chrono::nanoseconds(std::min(ns, static_cast<uint64_t>(INT64_MAX)))); return true;
}
#endif
