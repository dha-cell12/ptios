#ifndef TOUCH_H
#define TOUCH_H

#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventData.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"
#include "headers/IOHIDEventSystem.h"

#include <mach/mach_time.h>

#define TOUCH_UP 0
#define TOUCH_DOWN 1
#define TOUCH_MOVE 2

#include "../shared/TLinkTouchPayload.h"

// Integer-pixel internal API; same frame/count/finger/coordinate domain as legacy wire.
bool performTouchFrame(const TLinkTouchPoint *points, int touchCount);

// Length excludes the NUL terminator. Invalid frames are rejected before any HID/state change.
bool performTouchFromRawData(const UInt8 *eventData, size_t eventDataLength);

static void setSenderIdCallback(void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event);
void startSetSenderIDCallBack();
void initSenderId();

void initTouchGetScreenSize();

#endif