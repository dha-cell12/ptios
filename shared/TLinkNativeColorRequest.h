#ifndef TLINK_NATIVE_COLOR_REQUEST_H
#define TLINK_NATIVE_COLOR_REQUEST_H
#include "TLinkNativeNumber.h"
#include <cmath>
#include <cstdlib>
#include <cerrno>
// Preserve JS %.0f followed by strict integer parsing and the legacy [0,8192)
// coordinate domain. -1 retains an invalid parameter until after authorization
// and compute admission; never clamp an invalid coordinate into the image.
inline int TLinkNativeColorJSCoordinate(double value) {
    if(!std::isfinite(value))return -1;
    char text[384];if(!TLinkNativeDecimal(text,sizeof(text),0,value))return -1;
    errno=0;char *end=nullptr;const long long parsed=std::strtoll(text,&end,10);
    if(errno==ERANGE||end==text||*end||parsed<0||parsed>=8192)return -1;
    return int(parsed);
}
struct TLinkNativeColorPickRequest {
    int x,y;
    TLinkNativeColorPickRequest(double px,double py):x(TLinkNativeColorJSCoordinate(px)),y(TLinkNativeColorJSCoordinate(py)){}
};
#endif
