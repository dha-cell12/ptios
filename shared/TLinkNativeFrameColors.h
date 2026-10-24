#ifndef TLINK_NATIVE_FRAME_COLORS_H
#define TLINK_NATIVE_FRAME_COLORS_H
#include "TLinkNativeFramePick.h"
#include "TLinkModernImagePolicy.h"
struct TLinkNativeFrameColorsRequest {
    TLinkNativeFramePickRequest frame;
    std::vector<TLinkColorPoint> points;
    size_t pointCount=0,tableUnits=0,toleranceUnits=6;
    int mode=1;
    double tolerance=0;
    bool tableValid=true,toleranceValid=true;
    void append(double x,double y,int red,int green,int blue) {
        char xs[384],ys[384];TLinkColorPoint point={0,0,red,green,blue};
        const bool xf=TLinkNativeDecimal(xs,sizeof(xs),0,x),yf=TLinkNativeDecimal(ys,sizeof(ys),0,y);
        const bool xv=xf&&TLinkColorInt(xs,point.dx),yv=yf&&TLinkColorInt(ys,point.dy);
        tableValid=tableValid&&xv&&yv&&TLinkColorRGB(red)&&TLinkColorRGB(green)&&TLinkColorRGB(blue);
        const size_t extra=(xf?std::strlen(xs):0)+(yf?std::strlen(ys):0)+8+
            TLinkFramePickIntegerBytes(red)+TLinkFramePickIntegerBytes(green)+TLinkFramePickIntegerBytes(blue)+(pointCount?1:0);
        tableUnits=tableUnits>32768||extra>32768-tableUnits?32769:tableUnits+extra;
        if(points.size()<512)points.push_back(point);
        if(pointCount<513)++pointCount;
    }
};
inline bool TLinkFrameColorsParameters(const TLinkNativeFrameColorsRequest &r){
    return TLinkFramePickParameters(r.frame)&&r.toleranceValid&&TLinkColorMode(r.mode,r.tolerance);
}
inline bool TLinkFrameColorsInputFits(const TLinkNativeFrameColorsRequest &r,size_t coordUnits){
    // Task 69 + is_colors + six ;; separators, frame/mode/age, table/tolerance/coord.
    size_t fixed=23+TLinkFramePickIntegerBytes(r.frame.frameId)+TLinkFramePickIntegerBytes(r.mode)+TLinkFramePickIntegerBytes(r.frame.maxAgeMs);
    if(r.tableUnits>8192-fixed)return false;fixed+=r.tableUnits;
    if(r.toleranceUnits>8192-fixed)return false;fixed+=r.toleranceUnits;
    return coordUnits<=8192-fixed;
}
inline const char *TLinkFrameColorsTableError(const TLinkNativeFrameColorsRequest &r){
    if(!r.tableUnits||r.tableUnits>32768)return "point_table_limit_or_empty";
    if(r.pointCount>512)return "point_table_limit";
    if(!r.tableValid||r.pointCount!=r.points.size())return "invalid_point_table";
    return r.points.empty()?"point_table_empty":nullptr;
}
struct TLinkNativeFrameColorsValue {bool matched=false;uint64_t ageMs=0;double totalMs=0;};
// Parameters, table and immutable BGRA geometry must be validated by the adapter.
inline bool TLinkFrameColorsEvaluate(const uint8_t *bgra,int sw,int sh,size_t stride,double scale,
        const std::vector<TLinkColorPoint> &points,bool pointCoord,int mode,double tolerance,TLinkColorRequest &request,bool &matched){
    matched=true;
    for(const auto &point:points){
        int x=0,y=0;
        if(!TLinkFrameColorCoordinate(point.dx,scale,pointCoord,x)||!TLinkFrameColorCoordinate(point.dy,scale,pointCoord,y)||x<0||y<0||x>=sw||y>=sh){matched=false;return true;}
        if(!request.consume())return false;
        const uint8_t *p=bgra+size_t(y)*stride+size_t(x)*4;
        if(!TLinkColorMatch(p[2],p[1],p[0],point,mode,tolerance)){matched=false;return true;}
    }
    return true;
}
#endif
