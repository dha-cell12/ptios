#pragma once
#include <array>
#include <cstddef>
#include <cmath>
#include <cstdint>
#include <climits>

namespace TLinkIndicatorPresentation {
struct Point {
    double x=0,y=0,radius=0;
    Point()=default;
    Point(double a,double b,double r):x(a),y(b),radius(r){}
    bool operator==(const Point &other)const{return x==other.x&&y==other.y&&radius==other.radius;}
};
inline bool Layout(const Point &point,double scale,double ratio,int &x,int &y){
    if(!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(point.radius)||point.radius<0||
        !std::isfinite(scale)||scale<=0||!std::isfinite(ratio)||ratio<=0)return false;
    const double a=point.x*scale,b=point.y*scale,half=point.radius*ratio/2;
    if(!std::isfinite(a)||!std::isfinite(b)||a<INT_MIN||a>INT_MAX||b<INT_MIN||b>INT_MAX||
        !std::isfinite(half)||!std::isfinite(half*2)||!std::isfinite(point.x-half)||
        !std::isfinite(point.y-half)||!std::isfinite(point.y+half)||!std::isfinite(point.x+half+5))return false;
    x=static_cast<int>(a);y=static_cast<int>(b);return true;
}
// Main-owner numeric state only: no HID event, UIKit object or callback is retained.
template<std::size_t Count>
class Slots {
    struct Slot {bool active=false,dirty=false,known=false;Point rendered,pending;uint64_t version=0;};
    std::array<Slot,Count> slots_{};
    static void advance(Slot &slot){if(++slot.version==0)++slot.version;}
    static bool valid(int index){return index>=0&&static_cast<std::size_t>(index)<Count;}
public:
    struct Ticket {Point point;uint64_t version=0;};
    void show(int index,const Point &point){if(!valid(index))return;auto &slot=slots_[index];advance(slot);slot.active=slot.known=true;slot.dirty=false;slot.rendered=point;}
    void hide(int index){if(!valid(index))return;auto &slot=slots_[index];advance(slot);slot.active=slot.dirty=false;}
    void clear(){for(std::size_t index=0;index<Count;++index)hide(static_cast<int>(index));}
    bool move(int index,const Point &point){
        if(!valid(index)||!slots_[index].active)return false;
        auto &slot=slots_[index];advance(slot);slot.dirty=!slot.known||!(slot.rendered==point);slot.pending=point;return slot.dirty;
    }
    bool peek(int index,Ticket &ticket)const{
        if(!valid(index))return false;const auto &slot=slots_[index];if(!slot.active||!slot.dirty)return false;
        ticket.point=slot.pending;ticket.version=slot.version;return true;
    }
    bool begin(int index,const Ticket &ticket){
        if(!valid(index))return false;auto &slot=slots_[index];
        if(!slot.active||!slot.dirty||slot.version!=ticket.version)return false;
        slot.known=false;return true; // A partial/throwing UIKit write cannot be treated as a committed point.
    }
    bool complete(int index,const Ticket &ticket){
        if(!valid(index))return false;auto &slot=slots_[index];
        if(!slot.active||!slot.dirty||slot.version!=ticket.version)return false;
        slot.rendered=ticket.point;slot.known=true;slot.dirty=false;return true;
    }
    bool pending()const{for(const auto &slot:slots_)if(slot.active&&slot.dirty)return true;return false;}
};
}
