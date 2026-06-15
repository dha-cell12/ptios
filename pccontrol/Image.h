#ifndef IMAGE_H
#define IMAGE_H

#import <Foundation/Foundation.h>

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

#endif
