#ifndef TLINK_AX_SNAPSHOT_WINDOW_H
#define TLINK_AX_SNAPSHOT_WINDOW_H
#include <algorithm>
#include <cstdint>

class TLinkAXSnapshotWindow {
    uint64_t started_,last_,end_;
    bool valid_;
    bool observe(uint64_t now){
        if(!valid_||now<last_||now==UINT64_MAX){valid_=false;return false;}
        last_=now;return true;
    }
public:
    TLinkAXSnapshotWindow(uint64_t now,unsigned milliseconds):started_(now),last_(now),end_(now),valid_(false){
        const uint64_t span=static_cast<uint64_t>(milliseconds)*1000000ULL;
        if(milliseconds<100||milliseconds>3000||now==UINT64_MAX||now>UINT64_MAX-span)return;
        end_=now+span;valid_=true;
    }
    double remainingSeconds(uint64_t now,double maximum){
        if(!observe(now)||now>=end_||!(maximum>0))return 0;
        return std::min(maximum,static_cast<double>(end_-now)/1e9);
    }
    double elapsedMilliseconds(uint64_t now){
        observe(now); // Invalid/regressed clocks retain the last known elapsed time.
        return static_cast<double>(last_-started_)/1e6;
    }
};
#endif
