#ifndef RECORD_H
#define RECORD_H

#import <Foundation/Foundation.h>

#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventData.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"
#include "headers/IOHIDEventSystem.h"

#include <mach/mach_time.h>

NSString *startRecordingWithError(NSError **error);
void startRecording(CFWriteStreamRef requestClient, NSError **error);
// Completion waits for HID teardown, buffered writes and file close; propagates failure.
void stopRecordingWithError(NSError **error);
// Captures the current generation before scheduling; completion runs off main after file close.
void stopRecordingAsync(void (^completion)(NSError *error));
void stopRecording();
Boolean isRecordingStart();

#endif