#ifndef TLINK_LICENSE_HOT_STATE_H
#define TLINK_LICENSE_HOT_STATE_H
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cmath>
inline uint64_t TLinkLicenseHotNowNs() {
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
}
inline bool TLinkLicenseSnapshotTimeAllowed(double wall, double verifiedWall, double offline, double expiry) {
    return std::isfinite(wall) && std::isfinite(verifiedWall) && std::isfinite(offline) && std::isfinite(expiry) &&
        wall + 300.0 >= verifiedWall && offline > 0 && wall <= offline && (expiry <= 0 || wall <= expiry);
}
// Caller owns synchronization. No file, crypto, Foundation or dispatch dependency.
class TLinkLicenseHotState {
    uint64_t epoch_ = 1, generation_ = 0, probeAt_ = 0, snapshotAt_ = 0, nextRefresh_ = 0;
    bool known_ = false, snapshot_ = false, refreshing_ = false;
public:
    struct Ticket { uint64_t epoch, started; };
    uint64_t epoch() const { return epoch_; }
    void invalidate() { ++epoch_; snapshot_ = false; known_ = false; nextRefresh_ = 0; }
    void observe(uint64_t generation, uint64_t now) {
        if (known_ && generation_ != generation) invalidate();
        generation_ = generation; known_ = true; probeAt_ = now;
    }
    bool usable(uint64_t now) const {
        return snapshot_ && known_ && now >= snapshotAt_ && now - snapshotAt_ < 5000000000ULL &&
            now >= probeAt_ && now - probeAt_ <= 500000000ULL;
    }
    bool begin(uint64_t now, Ticket &ticket) {
        if (refreshing_ || now < nextRefresh_ || (snapshot_ && now >= snapshotAt_ && now - snapshotAt_ < 4000000000ULL)) return false;
        refreshing_ = true; ticket = Ticket{epoch_, now}; return true;
    }
    bool finish(Ticket ticket, uint64_t before, uint64_t after, uint64_t now, bool hasStatus) {
        observe(after, now);
        refreshing_ = false; nextRefresh_ = now + 250000000ULL;
        if (!hasStatus || ticket.epoch != epoch_ || before != after || now < ticket.started || now - ticket.started >= 5000000000ULL) return false;
        snapshotAt_ = ticket.started; snapshot_ = true; return true;
    }
};
struct TLinkLicenseAutomationView {
    uint64_t epoch = 0, started = 0;
    double verifiedWall = 0, offline = 0, expiry = 0;
    bool observe = false, automation = false;
};
inline bool TLinkLicenseAutomationViewAllows(const TLinkLicenseAutomationView &view, uint64_t epoch,
    uint64_t probeAt, uint64_t now, double wall) {
    if (view.epoch != epoch || now < view.started || now - view.started >= 5000000000ULL ||
        !probeAt || now < probeAt || now - probeAt > 500000000ULL) return false;
    return view.observe || (view.automation && TLinkLicenseSnapshotTimeAllowed(wall, view.verifiedWall, view.offline, view.expiry));
}
class TLinkLicenseAuthorityAdmission {
    std::atomic<unsigned> active_{0};
public:
    bool acquire() {
        unsigned value = active_.load();
        while (value < 8) if (active_.compare_exchange_weak(value, value + 1)) return true;
        return false;
    }
    void release() { active_.fetch_sub(1); }
    unsigned active() const { return active_.load(); }
};
#endif
