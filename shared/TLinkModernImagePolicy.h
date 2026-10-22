#ifndef TLINK_MODERN_IMAGE_POLICY_H
#define TLINK_MODERN_IMAGE_POLICY_H
#include "TLinkTemplatePolicy.h"
#include "TLinkColorPolicy.h"
inline TLinkImageMemory &TLinkModernImageMemory();
// Modern image tasks share a request across every batch operation.
class TLinkModernImageRequest {
    TLinkTemplateRequest budget_;
    const char *failure_ = nullptr;
    std::shared_ptr<TLinkImageCharge> scratch_;
public:
    explicit TLinkModernImageRequest(TLinkNativeBudgetPtr parent) : budget_(std::move(parent)) {}
    bool stopped() const { return failure_ || budget_.stopped(); }
    bool consume(size_t count) { return !failure_ && budget_.consume(count); }
    bool reserve(size_t bytes) {
        if(scratch_&&scratch_->bytes()>=bytes)return true;
        // Batch operations release prior Mats before requesting the next scratch size.
        scratch_.reset();scratch_=TLinkModernImageMemory().reserve(TLinkImageKind::Frame,bytes);
        return scratch_ ? true : fail("image_scratch_budget");
    }
    bool fail(const char *code) { failure_ = code; return false; }
    const char *error() const { return failure_ ? failure_ : budget_.error(); }
};
using TLinkModernImageRequestPtr = std::shared_ptr<TLinkModernImageRequest>;
inline TLinkModernImageRequestPtr &TLinkModernImageSlot() { static thread_local TLinkModernImageRequestPtr value; return value; }
class TLinkModernImageScope {
    TLinkModernImageRequestPtr previous_;
public:
    explicit TLinkModernImageScope(TLinkModernImageRequestPtr value) : previous_(TLinkModernImageSlot()) { TLinkModernImageSlot()=std::move(value); }
    ~TLinkModernImageScope() { TLinkModernImageSlot()=std::move(previous_); }
    TLinkModernImageScope(const TLinkModernImageScope &)=delete;
    TLinkModernImageScope &operator=(const TLinkModernImageScope &)=delete;
};
inline TLinkImageMemory &TLinkModernImageMemory() { static TLinkImageMemory memory(64*1024*1024,0,64*1024*1024); return memory; }
inline bool TLinkModernImageParameters(double acceptable,float low,float high,float step,int skip) {
    return std::isfinite(acceptable)&&acceptable>=0&&acceptable<=1&&std::isfinite(low)&&std::isfinite(high)&&
        std::isfinite(step)&&low>=0.01f&&low<=16&&high>=0.01f&&high<=16&&step>0&&skip>=0&&skip<=1023;
}
struct TLinkModernImageScale { float factor; int width,height,workWidth,workHeight; };
struct TLinkModernImagePlan { float ratio=1; size_t bytes=0; std::vector<TLinkModernImageScale> scales; };
// Keep the historical float subtraction and OpenCV rounding, but preflight every
// resize before allocating. Never resize a scale that cannot fit the source.
template<class Round> bool TLinkModernImageMakePlan(int iw,int ih,int tw,int th,float low,float high,float step,Round round,TLinkModernImagePlan &plan) {
    plan=TLinkModernImagePlan();size_t pixels=0,templatePixels=0;
    if(!TLinkImagePixels(iw>0?size_t(iw):0,ih>0?size_t(ih):0,8388608,&pixels)||
       !TLinkImagePixels(tw>0?size_t(tw):0,th>0?size_t(th):0,4194304,&templatePixels)||
       !TLinkModernImageParameters(.8,low,high,step,0))return false;
    if(high<low)std::swap(high,low);
    plan.ratio=pixels>600000?.5f:1.f;
    const int workW=round(iw*double(plan.ratio)),workH=round(ih*double(plan.ratio));
    if(workW<=0||workH<=0)return false;
    size_t extra=0;unsigned count=0;
    for(float s=high;s>=low-.0001f;) {
        if(++count>64)return false;
        const bool unit=std::fabs(s-1.f)<.0001f;
        const double w=unit?tw:tw*double(s),h=unit?th:th*double(s);
        const int width=round(w),height=round(h);
        const int ww=round(width*double(plan.ratio)),wh=round(height*double(plan.ratio));
        if(width>0&&height>0&&ww>0&&wh>0&&ww<=workW&&wh<=workH) {
            // Reserve a conservative ceil for implementation-specific resize rounding.
            const size_t scaled=unit?0:size_t(std::ceil(w))*size_t(std::ceil(h));
            const size_t work=plan.ratio==1?0:size_t(std::ceil(width*double(plan.ratio)))*size_t(std::ceil(height*double(plan.ratio)));
            extra=std::max(extra,scaled+work);
            plan.scales.push_back(TLinkModernImageScale{s,width,height,ww,wh});
        }
        const float next=s-step;if(next==s)return false;s=next;
    }
    // Includes fresh capture conversion RGBA+gray even for frame-backed callers.
    plan.bytes=pixels*5+(plan.ratio==1?0:size_t(workW)*size_t(workH))+extra;
    return plan.bytes<=32*1024*1024;
}
inline bool TLinkFrameColorGeometry(int width,int height,int stride,size_t bytes) {
    size_t pixels=0;return TLinkImagePixels(width>0?size_t(width):0,height>0?size_t(height):0,8388608,&pixels)&&
        stride>=int64_t(width)*4&&size_t(stride)<=bytes/size_t(height);
}
inline bool TLinkFrameColorCoordinate(double value,double scale,bool point,int &out) {
    if(!std::isfinite(value)||(point&&(!std::isfinite(scale)||scale<=0||scale>16)))return false;
    const double pixel=point?value*scale:value;
    if(!std::isfinite(pixel)||pixel<double(INT_MIN)+1||pixel>double(INT_MAX)-1)return false;
    out=int(std::round(pixel));return true;
}
#endif
