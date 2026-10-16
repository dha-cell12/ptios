#ifndef TLINK_PLAYBACK_STATE_H
#define TLINK_PLAYBACK_STATE_H
#include <cstdint>

// Protected by ScriptPlayer's lock. Idle is published only after worker and history cleanup.
enum class TLinkPlaybackPhase { Idle, Preparing, Scheduled, Running, Waiting, Stopping, Finishing };
class TLinkPlaybackState {
    TLinkPlaybackPhase phase_ = TLinkPlaybackPhase::Idle;
    uint64_t generation_ = 0;
public:
    TLinkPlaybackPhase phase() const { return phase_; }
    bool busy() const { return phase_ != TLinkPlaybackPhase::Idle; }
    bool current(uint64_t generation) const { return generation != 0 && generation == generation_ && busy(); }
    uint64_t reserve() {
        if (busy() || generation_ == UINT64_MAX) return 0;
        phase_ = TLinkPlaybackPhase::Preparing;
        return ++generation_;
    }
    bool ready(uint64_t generation) {
        if (!current(generation) || phase_ != TLinkPlaybackPhase::Preparing) return false;
        phase_ = TLinkPlaybackPhase::Scheduled; return true;
    }
    bool enter(uint64_t generation) {
        if (!current(generation) || (phase_ != TLinkPlaybackPhase::Scheduled && phase_ != TLinkPlaybackPhase::Waiting)) return false;
        phase_ = TLinkPlaybackPhase::Running; return true;
    }
    bool wait(uint64_t generation) {
        if (!current(generation) || phase_ != TLinkPlaybackPhase::Running) return false;
        phase_ = TLinkPlaybackPhase::Waiting; return true;
    }
    bool stop(uint64_t generation) {
        if (!current(generation) || phase_ == TLinkPlaybackPhase::Finishing) return false;
        phase_ = TLinkPlaybackPhase::Stopping; return true;
    }
    bool beginFinish(uint64_t generation) {
        if (!current(generation) || phase_ == TLinkPlaybackPhase::Finishing) return false;
        phase_ = TLinkPlaybackPhase::Finishing; return true;
    }
    bool finish(uint64_t generation) {
        if (!current(generation) || phase_ != TLinkPlaybackPhase::Finishing) return false;
        phase_ = TLinkPlaybackPhase::Idle; return true;
    }
};
#endif
