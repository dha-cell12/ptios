#ifndef TLINK_NATIVE_IMAGE_CAPTURE_H
#define TLINK_NATIVE_IMAGE_CAPTURE_H
#include <cstddef>
#include <string>
struct TLinkNativeImageCaptureRequest {
    int x=0,y=0,width=0,height=0;
    std::string sessionId,runId,runtime="legacy";
};
struct TLinkNativeImageCrop {int x=0,y=0,width=0,height=0;};
inline bool TLinkNativeImageCaptureCrop(int x,int y,int width,int height,int screenWidth,int screenHeight,TLinkNativeImageCrop &out){
    out=TLinkNativeImageCrop{};if(screenWidth<=0||screenHeight<=0)return false;
    x=x<0?0:(x>=screenWidth?screenWidth-1:x);y=y<0?0:(y>=screenHeight?screenHeight-1:y);
    // Remaining extents are positive; avoid overflow in x+width/y+height.
    if(width<=0||width>screenWidth-x)width=screenWidth-x;
    if(height<=0||height>screenHeight-y)height=screenHeight-y;
    out.x=x;out.y=y;out.width=width;out.height=height;return true;
}
inline bool TLinkNativeImageCaptureInputFits(size_t x,size_t y,size_t width,size_t height,size_t owner,size_t limit=8192){
    if(limit<11)return false;size_t used=11;const size_t parts[]={x,y,width,height,owner};
    for(size_t part:parts){if(part>limit-used)return false;used+=part;}return true;
}
#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Keep the actual Foundation %.0f -> intValue behavior, including out-of-range scalars.
static inline int TLinkNativeImageCaptureJSInt(double value,size_t *units=nullptr){
    NSString *column=[NSString stringWithFormat:@"%.0f",value];if(units)*units=column.length;return column.intValue;
}
#endif
#endif
