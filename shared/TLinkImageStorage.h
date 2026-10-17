#ifndef TLINK_IMAGE_STORAGE_H
#define TLINK_IMAGE_STORAGE_H
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <limits>
#include <utility>

inline uint64_t TLinkImageNowMs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
inline double TLinkImageNowSeconds() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
inline uint64_t TLinkImageExpiry(uint64_t now, uint64_t ttl) {
    return ttl > UINT64_MAX - now ? UINT64_MAX : now + ttl;
}
inline bool TLinkImagePixels(size_t width, size_t height, size_t maximum, size_t *pixels) {
    if (!pixels || !width || !height || width > 8192 || height > 8192 || width > maximum / height) return false;
    *pixels = width * height; return true;
}
enum class TLinkImageKind { Frame, Image };
struct TLinkImageMemoryStats { size_t frames, images, total, peak; };
class TLinkImageCharge;
// Charge lifetime follows the immutable object, including readers after erase/expiry.
class TLinkImageMemory {
    friend class TLinkImageCharge;
    struct State {
        std::mutex mutex;
        size_t frames = 0, images = 0, total = 0, peak = 0;
        size_t frameLimit, imageLimit, totalLimit;
        State(size_t f, size_t i, size_t t) : frameLimit(f), imageLimit(i), totalLimit(t) {}
    };
    std::shared_ptr<State> state_;
public:
    TLinkImageMemory(size_t frames, size_t images, size_t total) : state_(std::make_shared<State>(frames, images, total)) {}
    std::shared_ptr<TLinkImageCharge> reserve(TLinkImageKind kind, size_t bytes);
    TLinkImageMemoryStats stats() const {
        std::lock_guard<std::mutex> lock(state_->mutex);
        return {state_->frames, state_->images, state_->total, state_->peak};
    }
};
class TLinkImageCharge {
    friend class TLinkImageMemory;
    std::shared_ptr<TLinkImageMemory::State> state_;
    TLinkImageKind kind_;
    size_t bytes_;
    TLinkImageCharge(std::shared_ptr<TLinkImageMemory::State> state, TLinkImageKind kind, size_t bytes)
        : state_(std::move(state)), kind_(kind), bytes_(bytes) {}
public:
    ~TLinkImageCharge() {
        std::lock_guard<std::mutex> lock(state_->mutex);
        size_t &used = kind_ == TLinkImageKind::Frame ? state_->frames : state_->images;
        used -= bytes_; state_->total -= bytes_;
    }
    size_t bytes() const { return bytes_; }
    TLinkImageCharge(const TLinkImageCharge &) = delete;
    TLinkImageCharge &operator=(const TLinkImageCharge &) = delete;
};
inline std::shared_ptr<TLinkImageCharge> TLinkImageMemory::reserve(TLinkImageKind kind, size_t bytes) {
    if (!bytes) return {};
    // Allocate the small ownership token before locking/counter mutation.
    auto charge = std::shared_ptr<TLinkImageCharge>(new TLinkImageCharge(state_, kind, 0));
    {
        std::lock_guard<std::mutex> lock(state_->mutex);
        size_t &used = kind == TLinkImageKind::Frame ? state_->frames : state_->images;
        const size_t limit = kind == TLinkImageKind::Frame ? state_->frameLimit : state_->imageLimit;
        if (bytes > limit - used || bytes > state_->totalLimit - state_->total) return {};
        used += bytes; state_->total += bytes; state_->peak = std::max(state_->peak, state_->total);
        charge->bytes_ = bytes;
    }
    return charge;
}
// IDs cross signed-int legacy adapters. Never wrap/reuse a released handle ID.
inline uint32_t TLinkImageNextId(uint32_t &next) {
    if (!next || next > 2147483647U) return 0;
    return next++;
}
class TLinkImageComputeGate {
    std::atomic<unsigned> active_{0};
public:
    bool enter() {
        unsigned active = active_.load(std::memory_order_relaxed);
        while (active < 2) if (active_.compare_exchange_weak(active, active + 1, std::memory_order_acquire)) return true;
        return false;
    }
    void leave() { active_.fetch_sub(1, std::memory_order_release); }
};
class TLinkImageWork {
    TLinkImageComputeGate &gate_;
    bool admitted_;
public:
    explicit TLinkImageWork(TLinkImageComputeGate &gate) : gate_(gate), admitted_(gate.enter()) {}
    ~TLinkImageWork() { if (admitted_) gate_.leave(); }
    explicit operator bool() const { return admitted_; }
    TLinkImageWork(const TLinkImageWork &) = delete;
    TLinkImageWork &operator=(const TLinkImageWork &) = delete;
};
#endif
