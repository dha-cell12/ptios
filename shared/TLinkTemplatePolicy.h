#ifndef TLINK_TEMPLATE_POLICY_H
#define TLINK_TEMPLATE_POLICY_H
#include "TLinkNativeBudget.h"
#include "TLinkImageStorage.h"
#include <cmath>
#include <climits>
#include <map>
#include <string>
#include <vector>
static const size_t kTLinkTemplatePixels = 4 * 1024 * 1024;
static const size_t kTLinkTemplateScreenPixels = 8 * 1024 * 1024;
static const size_t kTLinkTemplateEncodedBytes = 16 * 1024 * 1024;
static const size_t kTLinkTemplatePyramidBytes = 16 * 1024 * 1024;
inline bool TLinkTemplateParametersValid(int tries, double ratio, double acceptable) {
    return tries >= 0 && tries <= 8 && std::isfinite(ratio) && ratio >= 0.1 && ratio <= 1.9 &&
        std::isfinite(acceptable) && acceptable >= 0 && acceptable <= 1;
}
struct TLinkTemplateScale { float factor; int width, height; size_t bytes; };
struct TLinkTemplatePlan {
    float ratio = 1;
    int screenWidth = 0, screenHeight = 0, templateWidth = 0, templateHeight = 0;
    size_t bytes = 0;
    std::vector<TLinkTemplateScale> scales;
};
template<class Round> bool TLinkTemplateMakePlan(int iw, int ih, int tw, int th, float ratio, int tries, float sr, Round round, TLinkTemplatePlan &plan) {
    plan = TLinkTemplatePlan();
    size_t pixels;
    if (!TLinkImagePixels(iw,ih,kTLinkTemplateScreenPixels,&pixels) ||
        !TLinkImagePixels(tw,th,kTLinkTemplatePixels,&pixels) || !TLinkTemplateParametersValid(tries,sr,0.8)) return false;
    if (!std::isfinite(ratio) || ratio <= 0 || ratio > 1) return false;
    if (ratio == 1 && uint64_t(iw)*ih > 600000) ratio = .5f;
    plan.ratio = ratio; plan.screenWidth = round(iw*double(ratio)); plan.screenHeight = round(ih*double(ratio));
    plan.templateWidth = round(tw*double(ratio)); plan.templateHeight = round(th*double(ratio));
    if (plan.screenWidth <= 0 || plan.screenHeight <= 0 || plan.templateWidth <= 0 || plan.templateHeight <= 0) return false;
    auto add = [&](float factor) {
        for(const auto &entry:plan.scales)if(entry.factor==factor)return true;
        const double w=plan.templateWidth*double(factor), h=plan.templateHeight*double(factor);
        if (!std::isfinite(w) || !std::isfinite(h) || w>INT_MAX || h>INT_MAX) return false;
        int width=round(w),height=round(h);
        if (width<=0 || height<=0 || width>plan.screenWidth || height>plan.screenHeight) return true; // Never resize an unusable scale.
        const size_t bytes=size_t(std::ceil(w))*size_t(std::ceil(h));
        if (bytes>kTLinkTemplatePyramidBytes-plan.bytes) return false;
        plan.bytes+=bytes;plan.scales.push_back(TLinkTemplateScale{factor,width,height,bytes});return true;
    };
    if (!add(1)) return false;
    float increase=1,reduce=1;
    for(int i=0;i<tries;++i) { increase*=2-sr;reduce*=sr;if(!add(increase)||!add(reduce))return false; }
    return true;
}
class TLinkTemplateRequest {
    TLinkNativeBudgetPtr parent_;
    uint64_t deadline_;
    uint64_t remaining_ = 256000000;
    bool exhausted_ = false;
public:
    explicit TLinkTemplateRequest(TLinkNativeBudgetPtr parent, uint64_t started=TLinkNativeNowNs()) : parent_(std::move(parent)),deadline_(started+8000000000ULL) {}
    bool stopped(uint64_t now=TLinkNativeNowNs()) const { return exhausted_ || now>=deadline_ || (parent_&&parent_->stopped()); }
    bool consume(size_t count) { if(stopped())return false;if(count>remaining_){exhausted_=true;return false;}remaining_-=count;return true; }
    const char *error() const { return exhausted_ ? "template_work_limit" : "template_cancelled_or_timed_out"; }
};
using TLinkTemplateRequestPtr=std::shared_ptr<TLinkTemplateRequest>;
inline TLinkTemplateRequestPtr &TLinkTemplateRequestSlot(){static thread_local TLinkTemplateRequestPtr value;return value;}
inline TLinkTemplateRequestPtr TLinkTemplateCurrentRequest(){return TLinkTemplateRequestSlot();}
class TLinkTemplateRequestScope {
    TLinkTemplateRequestPtr previous_;
public:
    explicit TLinkTemplateRequestScope(TLinkTemplateRequestPtr value):previous_(TLinkTemplateRequestSlot()){TLinkTemplateRequestSlot()=std::move(value);}
    ~TLinkTemplateRequestScope(){TLinkTemplateRequestSlot()=std::move(previous_);}
    TLinkTemplateRequestScope(const TLinkTemplateRequestScope &)=delete;
    TLinkTemplateRequestScope &operator=(const TLinkTemplateRequestScope &)=delete;
};
// Caller serializes cache metadata. Payload charge follows the shared value, including active readers.
template<class Value> class TLinkTemplateLRU {
    struct Entry { Value value; uint64_t age; };
    std::map<std::string,Entry> entries_;
    uint64_t age_=0;
public:
    Value get(const std::string &key){auto it=entries_.find(key);if(it==entries_.end())return Value();it->second.age=++age_;return it->second.value;}
    bool evict(){if(entries_.empty())return false;auto oldest=entries_.begin();for(auto it=entries_.begin();it!=entries_.end();++it)if(it->second.age<oldest->second.age)oldest=it;entries_.erase(oldest);return true;}
    void put(const std::string &key,Value value,size_t limit){entries_.erase(key);while(entries_.size()>=limit)evict();entries_.emplace(key,Entry{std::move(value),++age_});}
    void clear(){entries_.clear();} size_t size()const{return entries_.size();}
};
#endif
