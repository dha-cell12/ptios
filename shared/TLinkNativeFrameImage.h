#ifndef TLINK_NATIVE_FRAME_IMAGE_H
#define TLINK_NATIVE_FRAME_IMAGE_H
#include "TLinkModernImagePolicy.h"
#include <cstdio>
struct TLinkNativeFrameImageRequest {
    int frameId=0,imageId=0,x=0,y=0,width=0,height=0,pixelSkip=0,maxAgeMs=1000;
    double acceptable=.95,low=1,high=1,step=1;
    float scaleMin=1,scaleMax=1,scaleStep=1;
    size_t regionUnits=0,scalarUnits=0;
    bool pointCoord=false,validCoord=true,coordinatesValid=true,scalarsValid=true;
    void regionPart(unsigned i,const char *text,size_t units){
        int *dest[]={&x,&y,&width,&height};regionUnits=units>8192||regionUnits>8192-units?8193:regionUnits+units;
        const bool valid=i<4&&TLinkColorInt(text,*dest[i]);coordinatesValid=coordinatesValid&&valid;
    }
    void scalarPart(unsigned i,const char *text,size_t units){
        double parsed=0;scalarUnits=units>8192||scalarUnits>8192-units?8193:scalarUnits+units;
        const bool valid=TLinkColorDouble(text,parsed);scalarsValid=scalarsValid&&valid;
        if(i==0)acceptable=parsed;
        else if(i==1){low=parsed;scaleMin=(valid?std::strtof(text,nullptr):0);}
        else if(i==2){high=parsed;scaleMax=(valid?std::strtof(text,nullptr):0);}
        else {step=parsed;scaleStep=(valid?std::strtof(text,nullptr):0);}
    }
};
inline bool TLinkNativeFrameImageParameters(const TLinkNativeFrameImageRequest &r){
    return r.frameId>0&&r.imageId>0&&r.coordinatesValid&&r.scalarsValid&&r.validCoord&&r.maxAgeMs>=0&&r.maxAgeMs<=5000&&
        TLinkModernImageParameters(r.acceptable,r.scaleMin,r.scaleMax,r.scaleStep,r.pixelSkip)&&std::fabs(r.high-r.low)/r.step<=63;
}
inline bool TLinkNativeFrameImageInputFits(const TLinkNativeFrameImageRequest &r,size_t coordUnits){
    char text[160];const int count=std::snprintf(text,sizeof(text),"%d%d%d%d",r.frameId,r.imageId,r.pixelSkip,r.maxAgeMs);
    size_t used=26+size_t(count);const size_t parts[]={r.regionUnits,r.scalarUnits,coordUnits};
    for(size_t units:parts){if(units>8192-used)return false;used+=units;}return true;
}
struct TLinkNativeFrameImageValue {
    int x=-1,y=-1,width=0,height=0;double centerX=-1,centerY=-1,score=0,totalMs=0;uint64_t ageMs=0;
};
#endif
