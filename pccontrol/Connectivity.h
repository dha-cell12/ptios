#ifndef CONNECTIVITY_H
#define CONNECTIVITY_H

#import <Foundation/Foundation.h>

// action=0: get state -> returns "0" or "1"
// action=1: set state; expects value (0/1) -> returns "0" or "1" (new state)

NSString* wifiTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* bluetoothTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* airplaneTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* cellularDataTaskFromRawData(UInt8 *eventData, NSError **error);
NSString* vpnTaskFromRawData(UInt8 *eventData, NSError **error);

#endif
