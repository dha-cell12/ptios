#ifndef TLINK_OCR_POLICY_H
#define TLINK_OCR_POLICY_H
#include "TLinkNativeBudget.h"
#include <climits>
#include <cmath>
#include <string>
#include <vector>
static const uint64_t kTLinkOCRMaxScaledPixels = 4000000;
static const uint64_t kTLinkOCRVisibleGrayBytes = 12 * 1024 * 1024;
struct TLinkOCRImagePlan {
    int width = 0, height = 0, scale = 1;
    uint64_t pixels = 0, visibleBytes = 0;
    bool separateWork = false;
};
inline bool TLinkOCRPlanImage(uint64_t width, uint64_t height, int scale, bool mutates, TLinkOCRImagePlan &plan) {
    plan = TLinkOCRImagePlan();
    scale = std::max(1, std::min(4, scale));
    if (!width || !height || width > static_cast<uint64_t>(INT_MAX / scale) || height > static_cast<uint64_t>(INT_MAX / scale)) return false;
    const uint64_t w = width * scale, h = height * scale;
    if (w > kTLinkOCRMaxScaledPixels / h) return false;
    const uint64_t source = width * height, pixels = w * h;
    const bool separate = scale > 1 || mutates;
    const uint64_t visible = source + pixels * (separate ? 2 : 1);
    if (visible > kTLinkOCRVisibleGrayBytes) return false;
    plan.width = static_cast<int>(w); plan.height = static_cast<int>(h); plan.scale = scale;
    plan.pixels = pixels; plan.visibleBytes = visible; plan.separateWork = separate;
    return true;
}
inline bool TLinkOCRPlanImageExtent(double width, double height, int scale, bool mutates, TLinkOCRImagePlan &plan) {
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0 || width > INT_MAX || height > INT_MAX) {
        plan = TLinkOCRImagePlan(); return false;
    }
    return TLinkOCRPlanImage(static_cast<uint64_t>(std::ceil(width)), static_cast<uint64_t>(std::ceil(height)), scale, mutates, plan);
}
class TLinkOCRRequestBudget {
    TLinkNativeBudgetPtr parent_;
    uint64_t deadline_;
public:
    explicit TLinkOCRRequestBudget(TLinkNativeBudgetPtr parent, uint64_t started = TLinkNativeNowNs()) : parent_(std::move(parent)), deadline_(started + 3000000000ULL) {}
    bool stopped(uint64_t now = TLinkNativeNowNs()) const { return now >= deadline_ || (parent_ && parent_->stopped()); }
    double remainingSeconds(uint64_t now = TLinkNativeNowNs()) const {
        if (stopped(now)) return 0;
        const double remaining = static_cast<double>(deadline_ - now) / 1e9;
        return parent_ ? parent_->remainingSeconds(remaining) : remaining;
    }
};
using TLinkOCRBudgetPtr = std::shared_ptr<TLinkOCRRequestBudget>;
class TLinkOCRAdmission {
    std::atomic<unsigned> &active_;
    bool admitted_ = false;
public:
    explicit TLinkOCRAdmission(std::atomic<unsigned> &active) : active_(active) {
        unsigned count = active.load();
        while (count < 2) if (active.compare_exchange_weak(count,count+1)) { admitted_ = true; break; }
    }
    ~TLinkOCRAdmission() { if (admitted_) active_.fetch_sub(1); }
    explicit operator bool() const { return admitted_; }
    TLinkOCRAdmission(const TLinkOCRAdmission &) = delete;
    TLinkOCRAdmission &operator=(const TLinkOCRAdmission &) = delete;
};
// Serialized owner. Evict BEFORE constructing a replacement so live engine count stays bounded.
template<class Key, class Value, size_t Capacity = 2> class TLinkOCRLRU {
    struct Entry { Key key; Value value; };
    std::vector<Entry> entries_;
public:
    Value find(const Key &key) {
        for (size_t i = 0; i < entries_.size(); ++i) if (entries_[i].key == key) {
            Entry hit = entries_[i]; entries_.erase(entries_.begin() + i); entries_.push_back(hit); return hit.value;
        }
        return Value();
    }
    void prepareMiss() { if (entries_.size() >= Capacity) entries_.erase(entries_.begin()); }
    void insert(const Key &key, Value value) { remove(key); prepareMiss(); entries_.push_back(Entry{key,value}); }
    void remove(const Key &key) { for (size_t i=0;i<entries_.size();++i) if (entries_[i].key == key) { entries_.erase(entries_.begin()+i); return; } }
    void clear() { entries_.clear(); }
    size_t size() const { return entries_.size(); }
};
#endif
