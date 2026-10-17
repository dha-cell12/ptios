#ifndef TLINK_EVENT_POLL_CORE_H
#define TLINK_EVENT_POLL_CORE_H
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstddef>
inline uint64_t TLinkEventMonotonicMs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
}
inline bool TLinkEventPollExpired(uint64_t started, uint64_t now, uint64_t timeout) {
    return now >= started && now - started >= timeout;
}
// Cancellation releases admission immediately, independently of a queued or running provider.
class TLinkEventPollLease {
    std::atomic<int> &active_;
    std::atomic<bool> ended_{false}, cancelled_{false};
    bool admitted_ = false;
public:
    explicit TLinkEventPollLease(std::atomic<int> &active, int limit = 8) : active_(active) {
        int count = active.load();
        while (count < limit) if (active.compare_exchange_weak(count, count + 1)) { admitted_ = true; break; }
    }
    ~TLinkEventPollLease() { cancel(); }
    bool admitted() const { return admitted_; }
    bool cancelled() const { return cancelled_.load(); }
    bool finish() {
        if (ended_.exchange(true)) return false;
        if (admitted_) active_.fetch_sub(1);
        return true;
    }
    void cancel() { cancelled_.store(true); finish(); }
    TLinkEventPollLease(const TLinkEventPollLease &) = delete;
    TLinkEventPollLease &operator=(const TLinkEventPollLease &) = delete;
};
// Scan through unmatched tails, but never advance over a matching event omitted by pagination.
struct TLinkEventBatchCursor {
    enum Action { Skip, Select, Stop };
    uint64_t cursor, next;
    size_t selected = 0, limit;
    bool more = false;
    TLinkEventBatchCursor(uint64_t c, size_t n) : cursor(c), next(c), limit(n) {}
    Action scan(uint64_t sequence, bool matches) {
        if (sequence <= cursor) return Skip;
        if (matches && selected >= limit) { more = true; return Stop; }
        next = sequence;
        if (!matches) return Skip;
        ++selected; return Select;
    }
    uint64_t nextCursor(uint64_t latest) const { return more ? next : latest; }
};
inline bool TLinkEventTopicValid(const char *bytes, size_t length) {
    if (!bytes || !length || length > 64) return false;
    if (length == 1 && bytes[0] == '*') return true;
    for (size_t i = 0; i < length; ++i) {
        const unsigned char c = static_cast<unsigned char>(bytes[i]);
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-')) return false;
    }
    return true;
}
#endif
