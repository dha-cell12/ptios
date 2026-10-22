#ifndef TEXT_RECOGNIZER_H
#define TEXT_RECOGNIZER_H

#import <Foundation/Foundation.h>

#define TASK_TEXT_FROM_AREA 1
#define TASK_GET_SUPPORTED_LANGUAGE_LIST 2
#define TASK_TEXT_FROM_FRAME 6

NSString* performTextRecognizerTextFromRawData(UInt8* eventData, NSError** error);

#endif

