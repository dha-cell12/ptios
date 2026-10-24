#ifndef TLINK_NATIVE_COLOR_POINTS_H
#define TLINK_NATIVE_COLOR_POINTS_H
#include "TLinkNativeNumber.h"
#include "TLinkColorPolicy.h"
struct TLinkNativeColorPointsRequest {
    std::vector<TLinkColorPoint> points;
    size_t pointCount=0,tableUnits=0,toleranceUnits=6;
    int mode=1;
    double tolerance=0;
    bool tableValid=true,toleranceValid=true;
    void append(double x,double y,int red,int green,int blue){
        char xs[384],ys[384];TLinkColorPoint point={0,0,red,green,blue};
        const bool xf=TLinkNativeDecimal(xs,sizeof(xs),0,x),yf=TLinkNativeDecimal(ys,sizeof(ys),0,y);
        const bool xv=xf&&TLinkColorInt(xs,point.dx),yv=yf&&TLinkColorInt(ys,point.dy);
        tableValid=tableValid&&xv&&yv&&TLinkColorRGB(red)&&TLinkColorRGB(green)&&TLinkColorRGB(blue);
        const auto integerUnits=[](int v)->size_t{char text[32];const int length=std::snprintf(text,sizeof(text),"%d",v);return size_t(length);};
        const size_t extra=(xf?std::strlen(xs):0)+(yf?std::strlen(ys):0)+8+
            integerUnits(red)+integerUnits(green)+integerUnits(blue)+(pointCount?1:0);
        tableUnits=tableUnits>131072||extra>131072-tableUnits?131073:tableUnits+extra;
        if(points.size()<512)points.push_back(point);
        if(pointCount<513)++pointCount;
    }
};
inline bool TLinkNativeColorPointsParameters(const TLinkNativeColorPointsRequest &r){return r.toleranceValid&&TLinkColorMode(r.mode,r.tolerance);}
inline bool TLinkNativeColorPointsInputFits(const TLinkNativeColorPointsRequest &r){
    // Task 28 + action 2 + three ;; separators, table, mode and tolerance. All fields are ASCII.
    char text[32];const int length=std::snprintf(text,sizeof(text),"%d",r.mode);const size_t fixed=9+size_t(length);
    return r.tableUnits<=8192-fixed&&r.toleranceUnits<=8192-fixed-r.tableUnits;
}
inline const char *TLinkNativeColorPointsTableError(const TLinkNativeColorPointsRequest &r){
    if(!r.tableUnits||r.tableUnits>131072||r.pointCount>512)return "color_point_table_limit";
    if(!r.tableValid||r.pointCount!=r.points.size())return "color_point_table_invalid";
    return r.points.empty()?"color_point_table_empty":nullptr;
}
inline bool TLinkNativeColorPointsBounds(const std::vector<TLinkColorPoint> &points,int width,int height,TLinkColorRect &crop){
    int minX=width,minY=height,maxX=0,maxY=0;
    for(const auto &p:points){
        if(p.dx<0||p.dy<0||p.dx>=width||p.dy>=height)return false;
        minX=std::min(minX,p.dx);minY=std::min(minY,p.dy);maxX=std::max(maxX,p.dx);maxY=std::max(maxY,p.dy);
    }
    crop.x=minX;crop.y=minY;crop.width=maxX-minX+1;crop.height=maxY-minY+1;return true;
}
// Geometry, full table, crop and point bounds are preflighted by the adapter.
inline bool TLinkNativeColorPointsCompare(const uint8_t *rgba,int stridePixels,const TLinkColorRect &crop,
        const std::vector<TLinkColorPoint> &points,int mode,double tolerance,TLinkColorRequest &request,bool &matched){
    matched=true;
    for(const auto &p:points){
        if(!request.consume())return false;
        const uint8_t *pixel=rgba+(size_t(p.dy-crop.y)*size_t(stridePixels)+size_t(p.dx-crop.x))*4;
        if(!TLinkColorMatch(pixel[0],pixel[1],pixel[2],p,mode,tolerance)){matched=false;return true;}
    }
    return true;
}
#endif
