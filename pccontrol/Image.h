#ifndef IMAGE_H
#define IMAGE_H

#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
#undef NO
#undef YES
#import <opencv.hpp>
#endif

using namespace cv;
using namespace std;


@interface Image : NSObject
{

}


@end

// Image object tasks
NSString* handleImageObjectTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleFindImageTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleFrameCaptureTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleFrameReleaseTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleFindImageInFrameTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleColorInFrameTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* handleFrameBatchTaskFromRawData(UInt8 *eventData, NSError **error);

#ifdef __cplusplus
bool zx_copyFrameGrayRegionForOCR(uint32_t frameId,
                                  int rx,
                                  int ry,
                                  int rw,
                                  int rh,
                                  NSString *coord,
                                  uint64_t maxAgeMs,
                                  cv::Mat &outGray,
                                  uint64_t *outAgeMs,
                                  NSError **error);
#endif

#endif
