#ifndef TESSERACT_OCR_TASK_H
#define TESSERACT_OCR_TASK_H

#import <Foundation/Foundation.h>

NSDictionary *TLinkTesseractOCRPerformance(void);
NSString *handleTesseractOCRTaskFromRawData(UInt8 *eventData, NSError **error);

#endif
