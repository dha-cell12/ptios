#ifndef PROCESS_H
#define PROCESS_H

#import <Foundation/Foundation.h>

#include <dlfcn.h>

int switchProcessForegroundFromRawData(UInt8 *eventData);
int bringAppForeground(NSString *appIdentifier);
id getFrontMostApplication();
NSString* killAppFromRawData(UInt8 *eventData, NSError **error);
NSString* appStateFromRawData(UInt8 *eventData, NSError **error);
NSString* appInfoFromRawData(UInt8 *eventData, NSError **error);
NSString* frontMostAppId(void);
NSString* frontMostAppOrientation(void);

// App/process info extensions
NSString* appPidFromRawData(UInt8 *eventData, NSError **error);
NSString* frontMostPidFromRawData(UInt8 *eventData, NSError **error);
NSString* appPathsFromRawData(UInt8 *eventData, NSError **error);
NSString* listBundlesFromRawData(UInt8 *eventData, NSError **error);

// Open URL / URL scheme
NSString* openUrlFromRawData(UInt8 *eventData, NSError **error);

#endif
