#ifndef TLINK_FRAME_VISION_POLICY_H
#define TLINK_FRAME_VISION_POLICY_H
#include "TLinkVisionPolicy.h"
#include <cctype>
inline bool TLinkFrameVisionUnsigned(const char *text,uint32_t maximum,uint32_t &out){
    if(!text)return false;
    while(std::isspace(static_cast<unsigned char>(*text)))++text;
    if(*text<'0'||*text>'9')return false;
    uint32_t value=0;
    while(*text>='0'&&*text<='9'){unsigned digit=unsigned(*text-'0');if(value>maximum/10||(value==maximum/10&&digit>maximum%10))return false;value=value*10+digit;++text;}
    while(std::isspace(static_cast<unsigned char>(*text)))++text;
    if(*text)return false;out=value;return true;
}
inline bool TLinkFrameVisionRegion(int width,int height,double scale,bool points,double x,double y,double w,double h,TLinkVisionROI &out){
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(w)||!std::isfinite(h)||x<0||y<0||w<0||h<0)return false;
    const double factor=points?scale:1.0;
    if(!std::isfinite(factor)||factor<=0||factor>16)return false;
    x*=factor;y*=factor;w*=factor;h*=factor;
    if(!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(w)||!std::isfinite(h)||x>8192||y>8192)return false;
    return TLinkVisionPlan(width,height,std::round(x),std::round(y),std::round(std::min(w,8192.0)),std::round(std::min(h,8192.0)),out);
}
#endif
