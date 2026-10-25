#ifndef IMAGE_H
#define IMAGE_H

#import <Foundation/Foundation.h>
#import "FrameVision.h"
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
#include "../shared/TLinkNativeImageOpen.h"
#include "../shared/TLinkNativeImageValue.h"
#include "../shared/TLinkNativeImageCapture.h"
bool captureStoredImage(const TLinkNativeImageCaptureRequest &request,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error);
bool openStoredImage(const TLinkNativeImageOpenRequest &request,uint32_t &publishedId,TLinkNativeImageValue &value,NSError **error);
#include "../shared/TLinkNativeImageRelease.h"
size_t releaseStoredImages(const TLinkNativeImageReleaseRequest &request);
#include "../shared/TLinkNativeFrameCapture.h"
bool captureStoredFrame(const TLinkNativeFrameCaptureRequest &request,uint32_t &publishedId,TLinkNativeFrameCaptureValue &value,NSError **error);
#include "../shared/TLinkNativeFrameRelease.h"
size_t releaseStoredFrames(const TLinkNativeFrameReleaseRequest &request);
#include "../shared/TLinkNativeFrameImage.h"
bool matchImageInFrame(const TLinkNativeFrameImageRequest &request,TLinkNativeFrameImageValue &value,NSError **error);
#include "../shared/TLinkNativeFramePick.h"
#include "../shared/TLinkNativeFrameSearch.h"
#include "../shared/TLinkNativeFrameMulti.h"
bool findFrameColors(const TLinkNativeFrameMultiRequest &request,TLinkNativeFrameMultiValue &value,NSError **error);
#include "../shared/TLinkNativeFrameColors.h"
bool testFrameColors(const TLinkNativeFrameColorsRequest &request,TLinkNativeFrameColorsValue &value,NSError **error);
bool searchFrameColor(const TLinkNativeFrameSearchRequest &request,TLinkNativeFrameSearchValue &value,NSError **error);
bool readFramePixel(const TLinkNativeFramePickRequest &pick, TLinkNativeFramePickValue &value, NSError **error);
bool readFramePixels(const TLinkNativeFramePickManyRequest &pick, TLinkNativeFramePickManyValue &value, NSError **error);
bool zx_copyFrameGrayRegionForOCR(uint32_t frameId,
                                  int rx,
                                  int ry,
                                  int rw,
                                  int rh,
                                  NSString *coord,
                                  uint64_t maxAgeMs,
                                  cv::Mat &outGray,
                                  uint64_t *outAgeMs,
                                  NSError **error,
                                  int ocrScaleUp = 1);
#endif

#endif
