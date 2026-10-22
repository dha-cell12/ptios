#ifndef TLINK_COLOR_POLICY_H
#define TLINK_COLOR_POLICY_H
#include "TLinkNativeBudget.h"
#include "TLinkImageStorage.h"
#include <cmath>
#include <climits>
#include <cstdlib>
#include <cerrno>
#include <cctype>
#include <vector>
struct TLinkColorPoint {int dx,dy,r,g,b;};
struct TLinkColorRect {int x=0,y=0,width=0,height=0;};
struct TLinkColorResult {int x=0,y=0,r=0,g=0,b=0;};
inline bool TLinkColorInt(const char *text,int &value){
    if(!text)return false;errno=0;char *end=nullptr;long long parsed=std::strtoll(text,&end,10);
    if(end==text||errno==ERANGE||parsed<INT_MIN||parsed>INT_MAX)return false;
    while(*end&&std::isspace(static_cast<unsigned char>(*end)))++end;
    if(*end)return false;value=static_cast<int>(parsed);return true;
}
inline bool TLinkColorDouble(const char *text,double &value){
    if(!text)return false;errno=0;char *end=nullptr;double parsed=std::strtod(text,&end);
    if(end==text||errno==ERANGE||!std::isfinite(parsed))return false;
    while(*end&&std::isspace(static_cast<unsigned char>(*end)))++end;
    if(*end)return false;value=parsed;return true;
}
inline bool TLinkColorMode(int mode,double value){return std::isfinite(value)&&value>=0&&((mode==0&&value<=1)||(mode==1&&value<=255));}
inline bool TLinkColorRGB(int value){return value>=0&&value<=255;}
inline bool TLinkColorMatch(int r,int g,int b,const TLinkColorPoint &target,int mode,double value){
    int dr=std::abs(r-target.r),dg=std::abs(g-target.g),db=std::abs(b-target.b);
    if(mode==1){int dev=static_cast<int>(value);return dr<=dev&&dg<=dev&&db<=dev;}
    return 1.0-(double(dr)+dg+db)/(3.0*255.0)>=value;
}
inline bool TLinkColorRegion(int sw,int sh,int x,int y,int width,int height,bool clamp,TLinkColorRect &out){
    size_t pixels=0;if(!TLinkImagePixels(sw>0?size_t(sw):0,sh>0?size_t(sh):0,8388608,&pixels))return false;
    if(clamp){x=std::max(0,std::min(x,sw-1));y=std::max(0,std::min(y,sh-1));}
    if(x<0||y<0||x>=sw||y>=sh)return false;
    out.x=x;out.y=y;out.width=width<=0?sw-x:std::min(width,sw-x);out.height=height<=0?sh-y:std::min(height,sh-y);return true;
}
inline bool TLinkColorAnchors(int sw,int sh,const TLinkColorRect &region,const std::vector<TLinkColorPoint> &points,TLinkColorRect &anchors,TLinkColorRect &crop){
    if(points.empty())return false;
    int64_t minX=INT_MAX,minY=INT_MAX,maxX=INT_MIN,maxY=INT_MIN;
    for(const auto &p:points){minX=std::min(minX,int64_t(p.dx));minY=std::min(minY,int64_t(p.dy));maxX=std::max(maxX,int64_t(p.dx));maxY=std::max(maxY,int64_t(p.dy));}
    int64_t x=std::max(int64_t(region.x),-minX),y=std::max(int64_t(region.y),-minY);
    int64_t endX=std::min(int64_t(region.x)+region.width-1,int64_t(sw)-1-maxX),endY=std::min(int64_t(region.y)+region.height-1,int64_t(sh)-1-maxY);
    if(x>endX||y>endY)return false;
    anchors.x=int(x);anchors.y=int(y);anchors.width=int(endX-x+1);anchors.height=int(endY-y+1);
    crop.x=int(x+minX);crop.y=int(y+minY);crop.width=int(endX-x+1+maxX-minX);crop.height=int(endY-y+1+maxY-minY);return true;
}
inline TLinkImageComputeGate &TLinkColorGate(){static TLinkImageComputeGate gate;return gate;}
inline TLinkImageMemory &TLinkColorMemory(){static TLinkImageMemory memory(32*1024*1024,0,32*1024*1024);return memory;}
class TLinkColorRequest {
    TLinkNativeBudgetPtr parent_;uint64_t started_;TLinkImageWork work_;uint64_t remaining_;bool exhausted_=false;
public:
    explicit TLinkColorRequest(TLinkNativeBudgetPtr parent,uint64_t start=TLinkNativeNowNs(),uint64_t comparisons=16777216):parent_(std::move(parent)),started_(start),work_(TLinkColorGate()),remaining_(comparisons){}
    bool admitted()const{return bool(work_);}
    bool stopped(uint64_t now=TLinkNativeNowNs())const{return exhausted_||now-started_>=3000000000ULL||(parent_&&parent_->stopped());}
    bool consume(){if(!remaining_){exhausted_=true;return false;}--remaining_;return (remaining_&1023)!=0||!stopped();}
    const char *error()const{return exhausted_?"color_work_limit":"color_cancelled_or_timed_out";}
};
enum class TLinkColorScan {Match,NoMatch,Stopped};
// Image, crop and point bounds are preflighted by the adapter/planner; no ObjC work here.
inline TLinkColorScan TLinkColorRangeScan(const uint8_t *rgba,int width,int height,int skip,const TLinkColorPoint &low,const TLinkColorPoint &high,TLinkColorRequest &request,TLinkColorResult &out){
    const int64_t step=int64_t(skip)+1;
    for(int64_t y=0;y<height;y+=step){if(request.stopped())return TLinkColorScan::Stopped;
        for(int64_t x=0;x<width;x+=step){if(!request.consume())return TLinkColorScan::Stopped;
            const uint8_t *p=rgba+(size_t(y)*width+size_t(x))*4;
            if(p[0]>=low.r&&p[0]<=high.r&&p[1]>=low.g&&p[1]<=high.g&&p[2]>=low.b&&p[2]<=high.b){out.x=int(x);out.y=int(y);out.r=p[0];out.g=p[1];out.b=p[2];return request.stopped()?TLinkColorScan::Stopped:TLinkColorScan::Match;}
        }
    }return request.stopped()?TLinkColorScan::Stopped:TLinkColorScan::NoMatch;
}
inline TLinkColorScan TLinkColorMultiScan(const uint8_t *rgba,int width,const TLinkColorRect &crop,const TLinkColorRect &anchors,const std::vector<TLinkColorPoint> &points,int mode,double value,int skip,TLinkColorRequest &request,TLinkColorResult &out){
    const int64_t step=int64_t(skip)+1;
    for(int64_t y=anchors.y;y<int64_t(anchors.y)+anchors.height;y+=step){if(request.stopped())return TLinkColorScan::Stopped;
        for(int64_t x=anchors.x;x<int64_t(anchors.x)+anchors.width;x+=step){bool match=true;
            for(const auto &p:points){if(!request.consume())return TLinkColorScan::Stopped;
                const size_t lx=size_t(x+p.dx-crop.x),ly=size_t(y+p.dy-crop.y);const uint8_t *pixel=rgba+(ly*width+lx)*4;
                if(!TLinkColorMatch(pixel[0],pixel[1],pixel[2],p,mode,value)){match=false;break;}
            }
            if(match){out.x=int(x);out.y=int(y);return request.stopped()?TLinkColorScan::Stopped:TLinkColorScan::Match;}
        }
    }return request.stopped()?TLinkColorScan::Stopped:TLinkColorScan::NoMatch;
}
#endif
