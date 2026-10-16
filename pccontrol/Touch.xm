#include "Touch.h"
#include "Common.h"
#include "Screen.h"
#include "AlertBox.h"
#include "Task.h"
#include <string.h>

static void postIOHIDEvent(IOHIDEventRef event);

#ifndef TLINKAUTO_TOUCH_FILE_LOG
#define TLINKAUTO_TOUCH_FILE_LOG 0
#endif

#define TOUCH_SENDER_ID_PLIST_FILE_NAME @"senderid.plist"

#define MAX_FINGER_INDEX kTLinkTouchMaxFingerCount

#define NOT_VALID 0
#define VALID 1
#define VALID_AT_NEXT_APPEND 2

#define EVENT_VALID_INDEX 0
#define EVENT_TYPE_INDEX 1
#define EVENT_X_INDEX 2
#define EVENT_Y_INDEX 3

// device screen size
static CGFloat device_screen_width = 0;
static CGFloat device_screen_height = 0;

IOHIDEventSystemClientRef ioHIDEventSystemForSenderID = NULL;

// touch event sender id
unsigned long long int senderID = 0x0;

// File logger (SpringBoard doesn't always have accessible stdout logs).
static void zx_touch_logf(const char *fmt, ...)
{
#if TLINKAUTO_TOUCH_FILE_LOG
    @autoreleasepool {
        NSString *dir = @"/var/mobile/Library/TLinkauto";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:true
                                                   attributes:nil
                                                        error:nil];
        NSString *path = @"/var/mobile/Library/TLinkauto/tlinkautod.log";
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:true];
        }

        char msg[1024];
        va_list args;
        va_start(args, fmt);
        vsnprintf(msg, sizeof(msg), fmt, args);
        va_end(args);

        NSDate *now = [NSDate date];
        static NSDateFormatter *df = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            df = [[NSDateFormatter alloc] init];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });

        NSString *line = [NSString stringWithFormat:@"%@ [Touch] %s\n", [df stringFromDate:now], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {
        }
        @try { [fh closeFile]; } @catch (__unused NSException *e) {}
    }
#else
    (void)fmt;
#endif
}

static void stopSetSenderIDCallBack(void)
{
    if (ioHIDEventSystemForSenderID == NULL) {
        return;
    }

    IOHIDEventSystemClientUnregisterEventCallback(ioHIDEventSystemForSenderID);
    IOHIDEventSystemClientUnscheduleWithRunLoop(ioHIDEventSystemForSenderID, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    CFRelease(ioHIDEventSystemForSenderID);
    ioHIDEventSystemForSenderID = NULL;
    NSLog(@"com.tlinkauto.springboard: unregister get sender id callback!");
}


// valid type x y
static int eventsToAppend[MAX_FINGER_INDEX][4];

/*
Get the child event of touching down.
index: index of the finger
x: coordinate x of the screen (before conversion)
y: coordinate y of the screen (before conversion)
*/
static IOHIDEventRef generateChildEventTouchDown(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 3, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 1, 1, 0);
    if (!child) return NULL;
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index getRandomNumberFloat(0.03, 0.05)
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}

/*
Get the child event of touching move. 
index: index of the finger
x: coordinate x of the screen (before conversion)
y: coordinate y of the screen (before conversion)
*/
static IOHIDEventRef generateChildEventTouchMove(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 4, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 1, 1, 0);
    if (!child) return NULL;
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}

/*
Get the child event of touching up.
index: index of the finger
x: coordinate x of the screen (before conversion)
y: coordinate y of the screen (before conversion)
*/
static IOHIDEventRef generateChildEventTouchUp(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 2, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 0, 0, 0);
    if (!child) return NULL;
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}

/**
Append child event to parent
*/
static bool appendChildEvent(IOHIDEventRef parent, int type, int index, float x, float y)
{
    IOHIDEventRef child = NULL;
    switch (type)
    {
        case TOUCH_MOVE:
            child = generateChildEventTouchMove(index, x, y);
            break;
        case TOUCH_DOWN:
            child = generateChildEventTouchDown(index, x, y);
            break;
        case TOUCH_UP:
            child = generateChildEventTouchUp(index, x, y);
            break;
        default:
            return false;
    }
    if (!child) return false;
    IOHIDEventAppendEvent(parent, child);
    CFRelease(child); // Append retains the child; balance our Create-rule ownership.
    return true;
}

/**
Perform touch events with data received from socket
*/
bool performTouchFromRawData(const UInt8 *eventData, size_t eventDataLength)
{
    TLinkTouchPoint points[kTLinkTouchMaxCount];
    int touchCount = 0;
    if (!TLinkParseTouchPayload(eventData, eventDataLength, points, &touchCount)) return false;

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(), 3, 99, 1, 0, 0, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0, 0, 0);
    if (!parent) return false;
    IOHIDEventSetIntegerValue(parent, 0xb0019, 1);
    IOHIDEventSetIntegerValue(parent, 0x4, 1);

    // Commit active-finger state only after the entire parent has been built successfully.
    int nextEventsToAppend[MAX_FINGER_INDEX][4];
    memcpy(nextEventsToAppend, eventsToAppend, sizeof(nextEventsToAppend));
    for (int i = 0; i < touchCount; i++)
    {
        const TLinkTouchPoint &point = points[i];
        if (!appendChildEvent(parent, point.type, point.index, (float)point.x, (float)point.y)) {
            CFRelease(parent);
            return false;
        }
        int *next = nextEventsToAppend[point.index];
        if (point.type == TOUCH_UP) {
            next[EVENT_VALID_INDEX] = NOT_VALID;
        } else {
            next[EVENT_VALID_INDEX] = VALID_AT_NEXT_APPEND;
            next[EVENT_TYPE_INDEX] = point.type;
            next[EVENT_X_INDEX] = point.x;
            next[EVENT_Y_INDEX] = point.y;
        }
    }

    for (int i = 0; i < MAX_FINGER_INDEX; i++)
    {
        int *next = nextEventsToAppend[i];
        if (next[EVENT_VALID_INDEX] == VALID) {
            if (!appendChildEvent(parent, next[EVENT_TYPE_INDEX], i, (float)next[EVENT_X_INDEX], (float)next[EVENT_Y_INDEX])) {
                CFRelease(parent);
                return false;
            }
        } else if (next[EVENT_VALID_INDEX] == VALID_AT_NEXT_APPEND) {
            next[EVENT_VALID_INDEX] = VALID;
        }
    }

    IOHIDEventSetIntegerValue(parent, 0xb0007, 0x23);
    IOHIDEventSetIntegerValue(parent, 0xb0008, 0x1);
    IOHIDEventSetIntegerValue(parent, 0xb0009, 0x1);
    memcpy(eventsToAppend, nextEventsToAppend, sizeof(eventsToAppend));
    postIOHIDEvent(parent);
    CFRelease(parent);
    return true;
}

/**
Post the parent event
*/
static void postIOHIDEvent(IOHIDEventRef event)
{
    static IOHIDEventSystemClientRef ioSystemClient = NULL;
    if (!ioSystemClient){
        ioSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    }

    // Historically this code required a non-zero senderID.
    // On some devices / after reboot, senderID may not be available immediately.
    // Fallback: dispatch the event without setting senderID so touch still works.
    if (senderID != 0) {
        IOHIDEventSetSenderID(event, senderID);
    } else {
        static CFAbsoluteTime lastSenderWarning = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastSenderWarning > 5.0) {
            lastSenderWarning = now;
            zx_touch_logf("senderID is 0; dispatching touch without senderID. screen=%.0fx%.0f", device_screen_width, device_screen_height);
        }
    }
    IOHIDEventSystemClientDispatchEvent(ioSystemClient, event);
}

/*
Get sender id. If the device has not been rebooted, read senderid from file. Otherwise start set sender id callback
*/
void initSenderId()
{
    NSString *plistPath = [NSString stringWithFormat:@"%@/coreutils/touching/%@", getDocumentRoot(), TOUCH_SENDER_ID_PLIST_FILE_NAME];
    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath])
    {
        // check start time
        NSInteger currentTime = [[NSDate date] timeIntervalSince1970];
        NSInteger timeSinceReboot = [NSProcessInfo processInfo].systemUptime;
        NSInteger thisRebootTime = currentTime - timeSinceReboot;
        NSLog(@"com.tlinkauto.springboard: currentTime: %ld, time since reboot: %ld, last reboot time: %ld", currentTime, timeSinceReboot, thisRebootTime);
        
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSInteger lastRebootTime = [data[@"lastReboot"] longValue];
        
        if (abs(lastRebootTime - thisRebootTime) <= 3)
        {
            senderID = [data[@"senderID"] longLongValue];
            NSLog(@"com.tlinkauto.springboard: since the device has not been rebooted. Read sender id from the file. SenderID get: %qX", senderID);
            zx_touch_logf("initSenderId: loaded senderID=%llX", senderID);
            return;
        }
    }
    
    NSLog(@"com.tlinkauto.springboard: cannot read the sender id from file because the file doesn't exist or the device has restarted. Start set senderid callback.");
    zx_touch_logf("initSenderId: senderID not ready; start callback");
    startSetSenderIDCallBack();
}


/*
Get the sender id and unregister itself.
*/
static void setSenderIdCallback(void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event)
{
    if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer){
		if (senderID == 0x0)
        {
            NSError *err = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:[NSString stringWithFormat:@"%@/coreutils/touching/", getDocumentRoot()] withIntermediateDirectories:YES attributes:nil error:&err];
            if (err)
            {
                NSLog(@"Cannot save senderid for future use, but the tweak should work fine. Error: %@", err);
            }

			unsigned long long int capturedSenderID = IOHIDEventGetSenderID(event);
            if (capturedSenderID == 0x0) {
                return;
            }
            senderID = capturedSenderID;

            NSInteger currentTime = [[NSDate date] timeIntervalSince1970];
            NSInteger timeSinceReboot = [NSProcessInfo processInfo].systemUptime;
            NSInteger rebootTime = currentTime - timeSinceReboot;

            NSDictionary *dict = @{@"lastReboot":@(rebootTime), @"senderID": @(senderID)};

            [dict writeToFile:[NSString stringWithFormat:@"%@/coreutils/touching/%@", getDocumentRoot(), TOUCH_SENDER_ID_PLIST_FILE_NAME] atomically: YES];

			NSLog(@"com.tlinkauto.springboard: sender id is: %qX", senderID);
			zx_touch_logf("setSenderIdCallback: senderID=%llX", senderID);
            dispatch_async(dispatch_get_main_queue(), ^{
                stopSetSenderIDCallBack();
            });
        }
    }
}

/**
Start the callback for setting sender id
*/
void startSetSenderIDCallBack()
{
    // IMPORTANT: the callback needs an active runloop. Schedule it on the main runloop
    // to ensure it continues to receive digitizer events.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ioHIDEventSystemForSenderID != NULL) {
            return;
        }
        ioHIDEventSystemForSenderID = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (ioHIDEventSystemForSenderID == NULL) {
            zx_touch_logf("startSetSenderIDCallBack: failed to create IOHIDEventSystemClient");
            return;
        }
        IOHIDEventSystemClientScheduleWithRunLoop(ioHIDEventSystemForSenderID, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        IOHIDEventSystemClientRegisterEventCallback(ioHIDEventSystemForSenderID, (IOHIDEventSystemClientEventCallback)setSenderIdCallback, NULL, NULL);
        zx_touch_logf("startSetSenderIDCallBack: scheduled on main runloop");
    });
}

/*!!!!!!!!! Here, all the functions here will be moved to a class instance. This function is just for temporary use.*/
void initTouchGetScreenSize()
{
    device_screen_width = [Screen getScreenWidth];
    device_screen_height = [Screen getScreenHeight];
    zx_touch_logf("initTouchGetScreenSize: screen=%.0fx%.0f", device_screen_width, device_screen_height);
}
