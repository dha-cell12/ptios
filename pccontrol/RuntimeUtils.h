#ifndef RUNTIME_UTILS_H
#define RUNTIME_UTILS_H

#import <Foundation/Foundation.h>

NSString* dialogFromRawData(UInt8 *eventData, NSError **error);
NSString* clearDialogValues(NSError **error);
NSString* rootDirValue(void);
NSString* currentDirValue(void);
NSString* botPathValue(void);

// Script status (last error)
void setLastScriptError(NSString *message);
NSString* getLastScriptError(void);
long long getLastScriptErrorTs(void);

#endif
