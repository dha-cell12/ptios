#ifndef TLINK_SCHEDULER_STATE_H
#define TLINK_SCHEDULER_STATE_H

#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <string>

// Product policy: repeating script schedules are coarse timers, at least one second apart.
// One-shots retain positive subsecond delays. Conversion must fit dispatch_time's signed offset.
static inline bool TLinkSchedulerInterval(double seconds, bool repeat, uint64_t *nanoseconds)
{
    if (!nanoseconds) return false;
    *nanoseconds = 0;
    if (!std::isfinite(seconds) || seconds <= 0 || (repeat && seconds < 1.0)) return false;
    const long double ns = static_cast<long double>(seconds) * 1000000000.0L;
    if (ns < 1 || ns >= static_cast<long double>(INT64_MAX)) return false;
    *nanoseconds = static_cast<uint64_t>(ns);
    return true;
}

static inline uint64_t TLinkSchedulerLeeway(uint64_t interval)
{
    // Ten percent, capped at 100 ms; never busy-wait or replay missed timer ticks.
    const uint64_t tenth = interval / 10;
    return tenth < 100000000 ? tenth : 100000000;
}

enum class TLinkSchedulerFireResult { Stale, Busy, Launched };

// Single-owner registry. Timer is a copyable owning handle with cancel(). Every operation,
// including fire/launch, runs on the same serial queue. Callers acknowledge only after return.
// Removed generations are never reused, including remove followed by set of the same name.
template <typename Timer> class TLinkSchedulerRegistry {
    struct Entry { uint64_t generation; Timer timer; bool repeat; };
    std::map<std::string, Entry> entries_;
    uint64_t generation_ = 0;
public:
    TLinkSchedulerRegistry() = default;
    TLinkSchedulerRegistry(const TLinkSchedulerRegistry &) = delete;
    TLinkSchedulerRegistry &operator=(const TLinkSchedulerRegistry &) = delete;
    ~TLinkSchedulerRegistry() { for (auto &entry : entries_) entry.second.timer.cancel(); }

    uint64_t set(const std::string &name, const Timer &timer, bool repeat) {
        if (generation_ == UINT64_MAX) return 0; // Fail closed rather than reuse a token.
        remove(name);
        const uint64_t generation = ++generation_;
        entries_.emplace(name, Entry{generation, timer, repeat});
        return generation;
    }
    void remove(const std::string &name) {
        auto entry = entries_.find(name);
        if (entry == entries_.end()) return;
        entry->second.timer.cancel();
        entries_.erase(entry);
    }
    size_t size() const { return entries_.size(); }

    template <typename Launch> TLinkSchedulerFireResult fire(const std::string &name,
                                                             uint64_t generation,
                                                             bool busy, Launch launch) {
        auto entry = entries_.find(name);
        if (entry == entries_.end() || entry->second.generation != generation)
            return TLinkSchedulerFireResult::Stale;
        Timer timer = entry->second.timer; // Keep resources alive through a one-shot's removal.
        if (!entry->second.repeat) remove(name); // Consumed even when busy or denied, as before.
        if (busy) return TLinkSchedulerFireResult::Busy;
        launch(timer);
        return TLinkSchedulerFireResult::Launched;
    }
};
#endif
