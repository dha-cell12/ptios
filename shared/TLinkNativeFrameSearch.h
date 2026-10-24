#ifndef TLINK_NATIVE_FRAME_SEARCH_H
#define TLINK_NATIVE_FRAME_SEARCH_H
#include "TLinkNativeFramePick.h"
#include "TLinkModernImagePolicy.h"
struct TLinkNativeFrameSearchRequest {
    TLinkNativeFramePickRequest frame;
    double x=0,y=0,width=0,height=0;
    int redMin=0,redMax=255,greenMin=0,greenMax=255,blueMin=0,blueMax=255,skip=0;
    size_t regionUnits=4;
    void setRegion(double px,double py,double w,double h) {
        size_t units[4]={};
        x=TLinkNativeFrameJSCoordinate(px,&units[0]);y=TLinkNativeFrameJSCoordinate(py,&units[1]);
        width=TLinkNativeFrameJSCoordinate(w,&units[2]);height=TLinkNativeFrameJSCoordinate(h,&units[3]);
        regionUnits=units[0]+units[1]+units[2]+units[3];
    }
};
inline bool TLinkFrameSearchParameters(const TLinkNativeFrameSearchRequest &r) {
    return TLinkFramePickParameters(r.frame)&&std::isfinite(r.x)&&std::isfinite(r.y)&&std::isfinite(r.width)&&std::isfinite(r.height)&&
        std::fabs(r.x)<=double(INT_MAX)-1&&std::fabs(r.y)<=double(INT_MAX)-1&&std::fabs(r.width)<=double(INT_MAX)-1&&std::fabs(r.height)<=double(INT_MAX)-1&&
        TLinkColorRGB(r.redMin)&&TLinkColorRGB(r.redMax)&&r.redMin<=r.redMax&&
        TLinkColorRGB(r.greenMin)&&TLinkColorRGB(r.greenMax)&&r.greenMin<=r.greenMax&&
        TLinkColorRGB(r.blueMin)&&TLinkColorRGB(r.blueMax)&&r.blueMin<=r.blueMax&&r.skip>=0&&r.skip<=1023;
}
inline bool TLinkFrameSearchInputFits(const TLinkNativeFrameSearchRequest &r,size_t coordUnits) {
    // Task 69, mode search_single, 14 ;; separators, 4 decimal coordinates and 9 integers.
    const size_t fixed=43+TLinkFramePickIntegerBytes(r.frame.frameId)+TLinkFramePickIntegerBytes(r.frame.maxAgeMs)+
        TLinkFramePickIntegerBytes(r.redMin)+TLinkFramePickIntegerBytes(r.redMax)+TLinkFramePickIntegerBytes(r.greenMin)+TLinkFramePickIntegerBytes(r.greenMax)+
        TLinkFramePickIntegerBytes(r.blueMin)+TLinkFramePickIntegerBytes(r.blueMax)+TLinkFramePickIntegerBytes(r.skip);
    return r.regionUnits<=8192-fixed&&coordUnits<=8192-fixed-r.regionUnits;
}
struct TLinkNativeFrameSearchValue {
    int x=-1,y=-1,red=-1,green=-1,blue=-1;
    uint64_t ageMs=0;
    double totalMs=0;
};
enum class TLinkFrameSearchStatus {Done,CoordinateInvalid,Stopped};
// Call only with admitted parameters and validated immutable BGRA geometry.
inline TLinkFrameSearchStatus TLinkFrameSearchScan(const uint8_t *bgra,int sw,int sh,size_t stride,double scale,
        const TLinkNativeFrameSearchRequest &r,TLinkColorRequest &request,TLinkNativeFrameSearchValue &out) {
    int x=0,y=0,w=0,h=0;
    if(!TLinkFrameColorCoordinate(r.x,scale,r.frame.pointCoord,x)||!TLinkFrameColorCoordinate(r.y,scale,r.frame.pointCoord,y)||
       !TLinkFrameColorCoordinate(r.width,scale,r.frame.pointCoord,w)||!TLinkFrameColorCoordinate(r.height,scale,r.frame.pointCoord,h))return TLinkFrameSearchStatus::CoordinateInvalid;
    if(x<0)x=0;if(y<0)y=0;if(x>=sw)x=sw-1;if(y>=sh)y=sh-1;
    if(w<=0||w>sw-x)w=sw-x;if(h<=0||h>sh-y)h=sh-y;
    out.x=out.y=out.red=out.green=out.blue=-1;
    const int step=r.skip+1;
    for(int cy=0;cy<h;cy+=step){
        if(request.stopped())return TLinkFrameSearchStatus::Stopped;
        const uint8_t *row=bgra+size_t(y+cy)*stride;
        for(int cx=0;cx<w;cx+=step){
            if(!request.consume())return TLinkFrameSearchStatus::Stopped;
            const uint8_t *p=row+size_t(x+cx)*4;const int b=p[0],g=p[1],red=p[2];
            if(red>=r.redMin&&red<=r.redMax&&g>=r.greenMin&&g<=r.greenMax&&b>=r.blueMin&&b<=r.blueMax){
                out.x=x+cx;out.y=y+cy;out.red=red;out.green=g;out.blue=b;return TLinkFrameSearchStatus::Done;
            }
        }
    }
    return TLinkFrameSearchStatus::Done;
}
#endif
