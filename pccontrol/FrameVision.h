#ifndef TLINK_FRAME_VISION_H
#define TLINK_FRAME_VISION_H
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
// Returns an owned image over an immutable admitted frame, with no pixel copy.
// Caller releases it. Provider ownership keeps the frame and byte charge alive.
CGImageRef TLinkCreateVisionImageFromFrame(uint32_t frameId,CGRect region,NSString *coord,uint64_t maxAgeMs,
                                          CGRect *pixelRegion,uint64_t *ageMs,NSError **error) CF_RETURNS_RETAINED;
#endif
