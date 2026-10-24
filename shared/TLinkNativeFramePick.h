#ifndef TLINK_NATIVE_FRAME_PICK_H
#define TLINK_NATIVE_FRAME_PICK_H
#include "TLinkNativeNumber.h"
#include <cmath>
#include <climits>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>
// Same JS %.0f -> strict double value, without an aggregate request string.
inline double TLinkNativeFrameJSCoordinate(double value,size_t *bytes=nullptr) {
    if(bytes)*bytes=0;
    if(!std::isfinite(value))return NAN;
    char text[384];if(!TLinkNativeDecimal(text,sizeof(text),0,value))return NAN;
    if(bytes)*bytes=std::strlen(text);
#ifdef _WIN32
    return _strtod_l(text,nullptr,TLinkNativeNumberLocale());
#elif defined(__APPLE__)
    return strtod_l(text,nullptr,TLinkNativeNumberLocale());
#else
    return std::strtod(text,nullptr);
#endif
}
inline size_t TLinkFramePickIntegerBytes(int value) {
    uint32_t magnitude=value<0?0U-uint32_t(value):uint32_t(value);size_t bytes=value<0?2:1;
    while(magnitude>=10){magnitude/=10;++bytes;}return bytes;
}
inline bool TLinkFramePickInputFits(int frame,int age,size_t xBytes,size_t yBytes,size_t coordUnits) {
    // 69 + frame;;pick;;x;;y;;coord;;age
    const size_t fixed=16+TLinkFramePickIntegerBytes(frame)+TLinkFramePickIntegerBytes(age);
    if(xBytes>8192-fixed||yBytes>8192-fixed-xBytes)return false;
    return coordUnits<=8192-fixed-xBytes-yBytes;
}
struct TLinkNativeFramePickRequest {
    int frameId=0,maxAgeMs=1000;
    double x=0,y=0;
    bool pointCoord=false,validCoord=true;
};
inline bool TLinkFramePickParameters(const TLinkNativeFramePickRequest &value) {
    return value.frameId>0&&value.validCoord&&value.maxAgeMs>=0&&value.maxAgeMs<=5000&&
        std::isfinite(value.x)&&std::isfinite(value.y)&&std::fabs(value.x)<=double(INT_MAX)-1&&std::fabs(value.y)<=double(INT_MAX)-1;
}
struct TLinkNativeFramePickValue {
    int red=0,green=0,blue=0;
    uint64_t ageMs=0;
    double totalMs=0;
};
struct TLinkNativeFramePoint { double x=0,y=0; };
struct TLinkNativeFrameColor { int x=0,y=0,red=0,green=0,blue=0; };
struct TLinkNativeFramePickManyRequest {
    TLinkNativeFramePickRequest frame;
    std::vector<TLinkNativeFramePoint> points;
    size_t pointCount=0,tableUnits=0;
    void append(double x,double y) {
        if(pointCount==513&&tableUnits==32769)return;
        size_t xBytes=0,yBytes=0;
        TLinkNativeFramePoint point;point.x=TLinkNativeFrameJSCoordinate(x,&xBytes);point.y=TLinkNativeFrameJSCoordinate(y,&yBytes);
        // Keep complete JS validation outside this bounded plan. Count/byte failures remain lazy.
        size_t extra=xBytes+1+yBytes+(pointCount?1:0);
        tableUnits=tableUnits>32768||extra>32768-tableUnits?32769:tableUnits+extra;
        if(points.size()<512)points.push_back(point);
        if(pointCount<513)++pointCount;
    }
};
inline bool TLinkFramePickManyInputFits(int frame,int age,size_t tableUnits,size_t coordUnits) {
    // 69 + frame;;pick_many;;table;;coord;;age
    const size_t fixed=19+TLinkFramePickIntegerBytes(frame)+TLinkFramePickIntegerBytes(age);
    return tableUnits<=8192-fixed&&coordUnits<=8192-fixed-tableUnits;
}
struct TLinkNativeFramePickManyValue {
    std::vector<TLinkNativeFrameColor> colors;
    uint64_t ageMs=0;
    double totalMs=0;
};
#endif
