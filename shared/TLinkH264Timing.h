#ifndef TLINK_H264_TIMING_H
#define TLINK_H264_TIMING_H
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <thread>
inline uint64_t TLinkH264NowNs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
}
class TLinkH264SendWindow {
    uint64_t start_ = 0, progress_ = 0;
    uint64_t idle_, whole_;
public:
    explicit TLinkH264SendWindow(uint64_t idle = 2000000000ULL, uint64_t whole = 5000000000ULL) : idle_(idle), whole_(whole) {}
    void begin(uint64_t now) { start_ = progress_ = now; }
    uint64_t remaining(uint64_t now) const {
        const uint64_t idleAge = now - progress_, wholeAge = now - start_;
        if (idleAge >= idle_ || wholeAge >= whole_) return 0;
        return std::min(idle_ - idleAge, whole_ - wholeAge);
    }
    void progress(uint64_t now) { progress_ = now; }
};
// writer returns -1 fatal, -2 retry (EAGAIN/EINTR); wait returns false on fatal
// socket readiness. Caller begins once per complete access unit, not per chunk.
template<class Clock, class Writer, class Wait>
bool TLinkH264Send(TLinkH264SendWindow &window, const uint8_t *bytes, size_t length, Clock now, Writer write, Wait wait) {
    if (!bytes && length) return false;
    size_t offset = 0;
    while (offset < length) {
        if (!window.remaining(now())) return false;
        const long long count = write(bytes + offset, length - offset);
        if (count > 0 && static_cast<unsigned long long>(count) <= length - offset) {
            offset += static_cast<size_t>(count); window.progress(now());
        } else if (count == -2) {
            const uint64_t remaining = window.remaining(now());
            if (!remaining || !wait(std::min(remaining, uint64_t(50000000)))) return false;
        } else return false;
    }
    return true;
}
class TLinkH264Pacer {
    uint64_t next_;
public:
    explicit TLinkH264Pacer(uint64_t now) : next_(now) {}
    uint64_t advance(uint64_t now, unsigned fps) {
        const uint64_t period = 1000000000ULL / std::min(120U, std::max(1U, fps));
        next_ += period;
        if (next_ <= now) {
            // Drop missed wall-clock slots. Never burst through an old backlog.
            const uint64_t missed = (now - next_) / period;
            next_ += missed * period;
            if (next_ < now) next_ += period;
        }
        return next_ > now ? next_ - now : 0;
    }
    uint64_t next() const { return next_; }
};
inline void TLinkH264WaitFrame(TLinkH264Pacer &pacer, unsigned fps) {
    const uint64_t now = TLinkH264NowNs();
    (void)pacer.advance(now, fps);
    std::this_thread::sleep_until(std::chrono::steady_clock::time_point(std::chrono::nanoseconds(pacer.next())));
}
#endif
