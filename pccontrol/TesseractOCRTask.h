#ifndef TESSERACT_OCR_TASK_H
#define TESSERACT_OCR_TASK_H

#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
struct TLinkNativeFrameOCRRequest {
    uint32_t frameId=0;int x=0,y=0,width=0,height=0,oem=1,psm=7,scaleUp=2,thresholdMode=0;
    uint64_t maxAgeMs=1000;
    NSString *lang=@"vie",*whitelist=@"",*coord=@"pixel";
};
NSString *recognizeFrameWithTesseract(const TLinkNativeFrameOCRRequest &request,NSError **error);
#endif

NSDictionary *TLinkTesseractOCRPerformance(void);
NSString *handleTesseractOCRTaskFromRawData(UInt8 *eventData, NSError **error);

#endif
