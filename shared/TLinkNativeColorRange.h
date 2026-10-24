#ifndef TLINK_NATIVE_COLOR_RANGE_H
#define TLINK_NATIVE_COLOR_RANGE_H
#include "TLinkNativeNumber.h"
#include "TLinkColorPolicy.h"
struct TLinkNativeColorRangeRequest {
    int x=0,y=0,width=0,height=0;
    int redMin=0,redMax=255,greenMin=0,greenMax=255,blueMin=0,blueMax=255,skip=0;
    bool coordinatesValid=true;
    void setRegion(double px,double py,double w,double h){
        char text[384];const double values[]={px,py,w,h};int *dest[]={&x,&y,&width,&height};coordinatesValid=true;
        for(unsigned i=0;i<4;++i){
            const bool valid=std::isfinite(values[i])&&TLinkNativeDecimal(text,sizeof(text),0,values[i])&&TLinkColorInt(text,*dest[i]);
            coordinatesValid=coordinatesValid&&valid;
        }
    }
};
inline bool TLinkNativeColorRangeParameters(const TLinkNativeColorRangeRequest &r){
    return r.coordinatesValid&&r.x>=0&&r.y>=0&&r.x<8192&&r.y<8192&&r.skip>=0&&
        TLinkColorRGB(r.redMin)&&TLinkColorRGB(r.redMax)&&r.redMin<=r.redMax&&
        TLinkColorRGB(r.greenMin)&&TLinkColorRGB(r.greenMax)&&r.greenMin<=r.greenMax&&
        TLinkColorRGB(r.blueMin)&&TLinkColorRGB(r.blueMax)&&r.blueMin<=r.blueMax;
}
#endif
