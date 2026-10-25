#ifndef TLINK_NATIVE_OCR_INPUT_H
#define TLINK_NATIVE_OCR_INPUT_H
#include <cstdio>
#include <cstddef>
inline bool TLinkNativeOCRInputFits(int frameId,int oem,int psm,int scale,int threshold,int age,size_t regionUnits,size_t langUnits,size_t whitelistUnits,size_t coordUnits){
    char text[160];const int count=std::snprintf(text,sizeof(text),"%d%d%d%d%d%d",frameId,oem,psm,scale,threshold,age);
    size_t used=26+size_t(count);const size_t parts[]={regionUnits,langUnits,whitelistUnits,coordUnits};
    for(size_t units:parts){if(units>8192-used)return false;used+=units;}return true;
}
#endif
