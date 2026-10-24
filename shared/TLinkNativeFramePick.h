#ifndef TLINK_NATIVE_FRAME_PICK_H
#define TLINK_NATIVE_FRAME_PICK_H
#include "TLinkNativeNumber.h"
#include <cmath>
#include <climits>
#include <cstdint>
#include <cstring>
#include <cstdlib>
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
#endif
