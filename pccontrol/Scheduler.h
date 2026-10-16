#ifndef SCHEDULER_H
#define SCHEDULER_H

#import <Foundation/Foundation.h>

BOOL TLinkSchedulerScriptLaunchAllowed(NSString *source);
NSDictionary *TLinkSchedulerLicenseDiagnostics(void);
NSString* setAutoLaunchFromRawData(UInt8 *eventData, NSError **error);
NSString* listAutoLaunch(NSError **error);
// In-memory timers: set/remove ACK after the serial owner commits. Repeat >= 1 second.
NSString* setTimerFromRawData(UInt8 *eventData, NSError **error);
NSString* removeTimerFromRawData(UInt8 *eventData, NSError **error);
NSString* keepAwakeFromRawData(UInt8 *eventData, NSError **error);
NSString* stopScriptFromRawData(NSError **error);

#endif
