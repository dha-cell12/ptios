#ifndef TLINK_GESTURE_TIMING_H
#define TLINK_GESTURE_TIMING_H
#include "TLinkNativeBudget.h"
// Anchor once before DOWN. Frame work/oversleep consumes the interval rather
// than shifting every later target. Late frames remain ordered; none are skipped.
class TLinkGestureTimeline {
    uint64_t start_, duration_;
public:
    TLinkGestureTimeline(uint64_t start, uint64_t duration):start_(start),duration_(duration){}
    uint64_t target(unsigned step, unsigned intervals) const {
        if (!intervals) return start_;
        const uint64_t index = std::min(step, intervals);
        const uint64_t offset = (duration_ / intervals) * index + (duration_ % intervals) * index / intervals;
        return offset > UINT64_MAX - start_ ? UINT64_MAX : start_ + offset;
    }
    uint64_t remaining(uint64_t now, unsigned step, unsigned intervals) const {
        const uint64_t at = target(step, intervals);return now < at ? at - now : 0;
    }
    bool wait(unsigned step, unsigned intervals) const {
        if (TLinkNativeStopped()) return false;
        const uint64_t delay = remaining(TLinkNativeNowNs(), step, intervals);
        return (!delay || TLinkNativeWaitNs(delay)) && !TLinkNativeStopped();
    }
};
#endif
