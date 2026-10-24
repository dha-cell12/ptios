#ifndef TLINK_NATIVE_FRAME_MULTI_H
#define TLINK_NATIVE_FRAME_MULTI_H
#include "TLinkNativeFrameColors.h"
struct TLinkNativeFrameMultiRequest {
    TLinkNativeFrameColorsRequest colors;
    double x=0,y=0,width=0,height=0;
    size_t regionUnits=4;
    int skip=0;
    void setRegion(double px,double py,double w,double h){
        size_t units[4]={};
        x=TLinkNativeFrameJSCoordinate(px,&units[0]);y=TLinkNativeFrameJSCoordinate(py,&units[1]);
        width=TLinkNativeFrameJSCoordinate(w,&units[2]);height=TLinkNativeFrameJSCoordinate(h,&units[3]);
        regionUnits=units[0]+units[1]+units[2]+units[3];
    }
};
inline bool TLinkFrameMultiParameters(const TLinkNativeFrameMultiRequest &r){
    return TLinkFrameColorsParameters(r.colors)&&std::isfinite(r.x)&&std::isfinite(r.y)&&std::isfinite(r.width)&&std::isfinite(r.height)&&
        std::fabs(r.x)<=double(INT_MAX)-1&&std::fabs(r.y)<=double(INT_MAX)-1&&std::fabs(r.width)<=double(INT_MAX)-1&&std::fabs(r.height)<=double(INT_MAX)-1&&r.skip>=0&&r.skip<=1023;
}
inline bool TLinkFrameMultiInputFits(const TLinkNativeFrameMultiRequest &r,size_t coordUnits){
    // Task 69 + find_multi_point + eleven ;; separators, four integers, ROI, table, tolerance and coord.
    size_t fixed=40+TLinkFramePickIntegerBytes(r.colors.frame.frameId)+TLinkFramePickIntegerBytes(r.colors.frame.maxAgeMs)+TLinkFramePickIntegerBytes(r.colors.mode)+TLinkFramePickIntegerBytes(r.skip);
    for(size_t units:{r.regionUnits,r.colors.tableUnits,r.colors.toleranceUnits,coordUnits}){
        if(units>8192-fixed)return false;fixed+=units;
    }
    return true;
}
struct TLinkNativeFrameMultiValue {int x=-1,y=-1;uint64_t ageMs=0;double totalMs=0;};
// ROI conversion precedes table errors; offset conversion follows full table validation.
inline bool TLinkFrameMultiRegion(int sw,int sh,double scale,const TLinkNativeFrameMultiRequest &r,TLinkColorRect &region){
    int x=0,y=0,w=0,h=0;const bool point=r.colors.frame.pointCoord;
    return TLinkFrameColorCoordinate(r.x,scale,point,x)&&TLinkFrameColorCoordinate(r.y,scale,point,y)&&
        TLinkFrameColorCoordinate(r.width,scale,point,w)&&TLinkFrameColorCoordinate(r.height,scale,point,h)&&TLinkColorRegion(sw,sh,x,y,w,h,true,region);
}
inline bool TLinkFrameMultiOffsets(std::vector<TLinkColorPoint> &points,double scale,bool pointCoord){
    for(auto &p:points){int x=0,y=0;
        if(!TLinkFrameColorCoordinate(p.dx,scale,pointCoord,x)||!TLinkFrameColorCoordinate(p.dy,scale,pointCoord,y))return false;
        p.dx=x;p.dy=y;
    }
    return true;
}
// Adapters validate immutable BGRA geometry, parameters, ROI, table and all scaled offsets.
inline bool TLinkFrameMultiScan(const uint8_t *bgra,int sw,int sh,size_t stride,const TLinkColorRect &region,
        const std::vector<TLinkColorPoint> &points,int mode,double tolerance,int skip,TLinkColorRequest &request,TLinkNativeFrameMultiValue &out){
    out.x=out.y=-1;TLinkColorRect anchors,crop;
    if(!TLinkColorAnchors(sw,sh,region,points,anchors,crop))return true;
    const int step=skip+1;
    for(int y=anchors.y;y<anchors.y+anchors.height;y+=step){
        if(request.stopped())return false;
        for(int x=anchors.x;x<anchors.x+anchors.width;x+=step){bool matched=true;
            for(const auto &point:points){
                if(!request.consume())return false;
                const uint8_t *p=bgra+size_t(y+point.dy)*stride+size_t(x+point.dx)*4;
                if(!TLinkColorMatch(p[2],p[1],p[0],point,mode,tolerance)){matched=false;break;}
            }
            if(matched){out.x=x;out.y=y;return true;}
        }
    }
    return true;
}
#endif
