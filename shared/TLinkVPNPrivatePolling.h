#ifndef TLINK_VPN_PRIVATE_POLLING_H
#define TLINK_VPN_PRIVATE_POLLING_H
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace TLinkVPNPrivatePolling {
// One private operation owns a continuous-clock window for its bounded phase.
class Window {
    uint64_t last_,end_;
    bool valid_;
public:
    Window(uint64_t now,double seconds):last_(now),end_(now),valid_(false){
        const double bounded=std::isnan(seconds)?5.0:std::min(30.0,std::max(5.0,seconds));
        const uint64_t span=static_cast<uint64_t>(bounded*1000.0);
        if(now==UINT64_MAX||now>UINT64_MAX-span)return;
        end_=now+span;valid_=true;
    }
    unsigned remaining(uint64_t now){
        if(!valid_||now<last_||now==UINT64_MAX||now>=end_){valid_=false;return 0;}
        last_=now;return static_cast<unsigned>(end_-now);
    }
};

// Preserve 100ms polling without letting an interrupted/early sleep trigger a
// probe early or reset the window. Do not probe after the final partial wait.
template<class Clock,class Pause>
bool waitNext(Window &window,Clock now,Pause pause){
    uint64_t tick=now();
    const unsigned remaining=window.remaining(tick);
    if(!remaining)return false;
    const uint64_t due=tick+std::min(remaining,100U);
    while(tick<due){
        if(!pause(static_cast<unsigned>(due-tick)))return false;
        tick=now();
        if(!window.remaining(tick))return false;
    }
    return true;
}
}
#endif
