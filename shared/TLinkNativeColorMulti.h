#ifndef TLINK_NATIVE_COLOR_MULTI_H
#define TLINK_NATIVE_COLOR_MULTI_H
#include "TLinkNativeColorPoints.h"
struct TLinkNativeColorMultiRequest {
    TLinkNativeColorPointsRequest colors;
    int x=0,y=0,width=0,height=0,skip=0;
    size_t regionUnits=4;
    bool coordinatesValid=true;
    void setRegion(double px,double py,double w,double h){
        char text[384];const double values[]={px,py,w,h};int *dest[]={&x,&y,&width,&height};coordinatesValid=true;regionUnits=0;
        for(unsigned i=0;i<4;++i){
            const bool formatted=std::isfinite(values[i])&&TLinkNativeDecimal(text,sizeof(text),0,values[i]);
            const bool valid=formatted&&TLinkColorInt(text,*dest[i]);coordinatesValid=coordinatesValid&&valid;
            if(formatted)regionUnits+=std::strlen(text);
        }
    }
};
inline bool TLinkNativeColorMultiParameters(const TLinkNativeColorMultiRequest &r){
    return r.coordinatesValid&&r.skip>=0&&TLinkNativeColorPointsParameters(r.colors);
}
inline bool TLinkNativeColorMultiInputFits(const TLinkNativeColorMultiRequest &r){
    // Task 28 + action 3 + eight ;; separators, ROI, table, mode, tolerance, skip; all ASCII.
    char mode[32],skip[32];const int m=std::snprintf(mode,sizeof(mode),"%d",r.colors.mode),s=std::snprintf(skip,sizeof(skip),"%d",r.skip);
    size_t used=19+size_t(m)+size_t(s);
    const size_t units[]={r.regionUnits,r.colors.tableUnits,r.colors.toleranceUnits};
    for(size_t length:units){if(length>8192-used)return false;used+=length;}
    return true;
}
#endif
