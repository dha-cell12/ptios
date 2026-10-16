#ifndef TLINK_RECORDER_H
#define TLINK_RECORDER_H
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <mutex>

inline uint64_t TLinkRecorderNowNs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}
struct TLinkRecordEvent { uint64_t timeNs; int type, finger, x10, y10; };
enum class TLinkRecorderPhase { Idle, Starting, Recording, Stopping };
enum class TLinkRecorderFailure { None, Overflow, InvalidEvent, Write };
// Fixed storage. A callback is admitted completely or rejected completely; never evict DOWN/UP.
class TLinkRecorderBuffer {
public:
    static constexpr size_t Capacity = 4096;
private:
    mutable std::mutex mutex_;
    std::array<TLinkRecordEvent, Capacity> events_{};
    size_t head_ = 0, size_ = 0;
    uintptr_t generation_ = 0;
    TLinkRecorderPhase phase_ = TLinkRecorderPhase::Idle;
    TLinkRecorderFailure failure_ = TLinkRecorderFailure::None;
public:
    uintptr_t reserve() {
        std::lock_guard<std::mutex> lock(mutex_);
        if (phase_ != TLinkRecorderPhase::Idle || generation_ == UINTPTR_MAX) return 0;
        ++generation_; phase_ = TLinkRecorderPhase::Starting;
        failure_ = TLinkRecorderFailure::None; head_ = size_ = 0;
        return generation_;
    }
    bool activate(uintptr_t generation) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation != generation_ || phase_ != TLinkRecorderPhase::Starting) return false;
        phase_ = TLinkRecorderPhase::Recording; return true;
    }
    uintptr_t generation() const { std::lock_guard<std::mutex> lock(mutex_); return generation_; }
    bool busy() const { std::lock_guard<std::mutex> lock(mutex_); return phase_ != TLinkRecorderPhase::Idle; }
    bool accepts(uintptr_t generation) const {
        std::lock_guard<std::mutex> lock(mutex_);
        return generation == generation_ && phase_ == TLinkRecorderPhase::Recording;
    }
    bool append(uintptr_t generation, const TLinkRecordEvent *events, size_t count) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation != generation_ || phase_ != TLinkRecorderPhase::Recording) return false;
        if (!events || count > Capacity - size_) {
            failure_ = TLinkRecorderFailure::Overflow; phase_ = TLinkRecorderPhase::Stopping; return false;
        }
        for (size_t i = 0; i < count; ++i) events_[(head_ + size_ + i) % Capacity] = events[i];
        size_ += count; return true;
    }
    void stop(uintptr_t generation, TLinkRecorderFailure failure = TLinkRecorderFailure::None) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation != generation_ || phase_ == TLinkRecorderPhase::Idle) return;
        if (failure_ == TLinkRecorderFailure::None) failure_ = failure;
        phase_ = TLinkRecorderPhase::Stopping;
    }
    size_t take(uintptr_t generation, TLinkRecordEvent *out, size_t maximum) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation != generation_ || phase_ == TLinkRecorderPhase::Idle || !out) return 0;
        const size_t count = std::min(maximum, size_);
        for (size_t i = 0; i < count; ++i) out[i] = events_[(head_ + i) % Capacity];
        head_ = (head_ + count) % Capacity; size_ -= count; return count;
    }
    size_t pending() const { std::lock_guard<std::mutex> lock(mutex_); return size_; }
    TLinkRecorderFailure failure() const { std::lock_guard<std::mutex> lock(mutex_); return failure_; }
    bool finish(uintptr_t generation, bool failed) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (generation != generation_ || phase_ != TLinkRecorderPhase::Stopping || (size_ && !failed)) return false;
        head_ = size_ = 0; phase_ = TLinkRecorderPhase::Idle; return true;
    }
};
inline bool TLinkMakeRecordEvent(uint64_t timeNs, int type, int finger, double x, double y,
                                 double width, double height, TLinkRecordEvent *out) {
    if (!out || type < 0 || type > 2 || finger < 0 || finger >= 20 ||
        !std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width) || !std::isfinite(height) ||
        x < 0 || x > 1 || y < 0 || y > 1 || width <= 0 || height <= 0 || width > 9999.9 || height > 9999.9) return false;
    // Match the old %.0f coordinate rounding under the default rounding mode; bound field width.
    const float xScaled = static_cast<float>(x * width * 10);
    const float yScaled = static_cast<float>(y * height * 10);
    const int x10 = static_cast<int>(std::nearbyint(xScaled));
    const int y10 = static_cast<int>(std::nearbyint(yScaled));
    *out = {timeNs, type, finger, std::min(x10, 99999), std::min(y10, 99999)};
    return true;
}
// Encoder belongs to the writer. Delays depend solely on captured timestamps, not write latency.
class TLinkRecorderEncoder {
    uint64_t previousNs_ = 0;
public:
    void reset(uint64_t startNs) { previousNs_ = startNs; }
    template<class Emit> bool encode(const TLinkRecordEvent &event, Emit emit) {
        const uint64_t now = std::max(previousNs_, event.timeNs);
        const uint64_t delta = now - previousNs_;
        previousNs_ = now;
        uint64_t micros = delta / 1000 + (delta % 1000 >= 500 ? 1 : 0);
        char bytes[64];
        // RAW playback accepts signed-int Task-18 delays. Preserve long idle gaps without overflow.
        while (micros > 2147483647ULL) {
            static const char delay[] = "182147483647\n";
            if (!emit(delay, sizeof(delay) - 1)) return false;
            micros -= 2147483647ULL;
        }
        const int length = std::snprintf(bytes, sizeof(bytes), "18%llu\n101%d%02d%05d%05d\n",
            static_cast<unsigned long long>(micros), event.type, event.finger, event.x10, event.y10);
        return length > 0 && static_cast<size_t>(length) < sizeof(bytes) && emit(bytes, static_cast<size_t>(length));
    }
};
template<class Write> bool TLinkRecordWriteAll(const char *bytes, size_t length, Write write) {
    while (length) {
        const auto written = write(bytes, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0 || static_cast<size_t>(written) > length) return false;
        bytes += written; length -= static_cast<size_t>(written);
    }
    return true;
}
class TLinkRecorderBytes {
    std::array<char, 16384> bytes_{};
    size_t size_ = 0;
public:
    void reset() { size_ = 0; }
    template<class Write> bool flush(Write write) {
        if (!TLinkRecordWriteAll(bytes_.data(), size_, write)) return false;
        size_ = 0; return true;
    }
    template<class Write> bool append(const char *bytes, size_t length, Write write) {
        if (!bytes || length > bytes_.size()) return false;
        if (length > bytes_.size() - size_ && !flush(write)) return false;
        std::memcpy(bytes_.data() + size_, bytes, length); size_ += length; return true;
    }
};
#endif
