#ifndef TLINK_VISION_POLICY_H
#define TLINK_VISION_POLICY_H
#include "TLinkNativeBudget.h"
#include "TLinkImageStorage.h"
#include <cmath>
struct TLinkVisionROI { double x=0,y=0,width=0,height=0; };
inline bool TLinkVisionPlan(double iw,double ih,double x,double y,double width,double height,TLinkVisionROI &out) {
    if(!std::isfinite(iw)||!std::isfinite(ih)||iw<=0||ih<=0||iw>8192||ih>8192||std::ceil(iw)*std::ceil(ih)>8388608 ||
       !std::isfinite(x)||!std::isfinite(y)||!std::isfinite(width)||!std::isfinite(height)||
       x<0||y<0||x>=iw||y>=ih||width<0||height<0) return false;
    width=width==0?iw-x:std::min(width,iw-x);height=height==0?ih-y:std::min(height,ih-y);
    if(std::ceil(width)*std::ceil(height)>4194304)return false;
    out.x=x;out.y=y;out.width=width;out.height=height;return true;
}
inline TLinkImageComputeGate &TLinkVisionGate(){static TLinkImageComputeGate gate;return gate;}
class TLinkVisionContext {
    TLinkNativeBudgetPtr parent_;
    uint64_t started_;
    TLinkImageWork work_;
public:
    explicit TLinkVisionContext(TLinkNativeBudgetPtr parent,uint64_t now=TLinkNativeNowNs()):parent_(std::move(parent)),started_(now),work_(TLinkVisionGate()){}
    bool admitted()const{return bool(work_);}
    bool stopped(uint64_t now=TLinkNativeNowNs())const{return now-started_>=8000000000ULL||(parent_&&parent_->stopped());}
    bool outputAllowed(size_t bytes)const{return bytes<=1048576&&(!parent_||parent_->outputAllowed(bytes));}
};
using TLinkVisionContextPtr=std::shared_ptr<TLinkVisionContext>;
inline TLinkVisionContextPtr &TLinkVisionSlot(){static thread_local TLinkVisionContextPtr value;return value;}
class TLinkVisionScope {
    TLinkVisionContextPtr previous_;
public:
    explicit TLinkVisionScope(TLinkVisionContextPtr value):previous_(TLinkVisionSlot()){TLinkVisionSlot()=std::move(value);}
    ~TLinkVisionScope(){TLinkVisionSlot()=std::move(previous_);}
    TLinkVisionScope(const TLinkVisionScope &)=delete;
    TLinkVisionScope &operator=(const TLinkVisionScope &)=delete;
};
#endif
