#include "Touch.h"
#include "Common.h"
#include "Screen.h"
#include "AlertBox.h"
#include "Task.h"

#define TOUCH_SENDER_ID_PLIST_FILE_NAME @"senderid.plist"

#define MAX_FINGER_INDEX 20

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
}


// valid type x y
static int eventsToAppend[MAX_FINGER_INDEX][4];

/*
get count from data array by socket
*/
static int getTouchCountFromDataArray(UInt8* dataArray)
{
	if (!dataArray || dataArray[0] < '0' || dataArray[0] > '9') {
        return 0;
    }
	int count = (dataArray[0] - '0');
	if (count > MAX_FINGER_INDEX) {
        count = MAX_FINGER_INDEX;
    }
	return count;
}

static inline int zx_parseFixedDigits(UInt8 *dataArray, int start, int count)
{
    int value = 0;
    for (int i = 0; i < count; i++) {
        UInt8 ch = dataArray[start + i];
        if (ch < '0' || ch > '9') {
            return 0;
        }
        value = value * 10 + (ch - '0');
    }
    return value;
}

/*
get type from data array by socket
*/
static int getTouchTypeFromDataArray(UInt8* dataArray, int index)
{
	int type = (dataArray[1+index*TOUCH_DATA_LEN] - '0');
	return type;
}

/*
get index from data array by socket
*/
static int getTouchIndexFromDataArray(UInt8* dataArray, int index)
{
	int touchIndex = zx_parseFixedDigits(dataArray, 2 + index * TOUCH_DATA_LEN, 2);
	return touchIndex;
}

/*
get x from data array by socket
*/
static float getTouchXFromDataArray(UInt8* dataArray, int index)
{
	int x = zx_parseFixedDigits(dataArray, 4 + index * TOUCH_DATA_LEN, 5);
	return x/10.0;
}


/*
get y from data array by socket
*/
static float getTouchYFromDataArray(UInt8* dataArray, int index)
{
	int y = zx_parseFixedDigits(dataArray, 9 + index * TOUCH_DATA_LEN, 5);
	return y/10.0;
}

/*
Get the child event of touching down.
index: index of the finger
x: coordinate x of the screen (before conversion)
y: coordinate y of the screen (before conversion)
*/
static IOHIDEventRef generateChildEventTouchDown(int index, float x, float y)
{
	IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 3, x/device_screen_width, y/device_screen_height, 0.0f, 0.0f, 0.0f, 1, 1, 0);
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
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f); //set the major index
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f); //set the minor index
	return child;
}

/**
Append child event to parent
*/
static void appendChildEvent(IOHIDEventRef parent, int type, int index, float x, float y)
{
    switch (type)
    {
        case TOUCH_MOVE:
			IOHIDEventAppendEvent(parent, generateChildEventTouchMove(index, x, y));
            break;
        case TOUCH_DOWN:
            IOHIDEventAppendEvent(parent, generateChildEventTouchDown(index, x, y));
            break;
        case TOUCH_UP:
            IOHIDEventAppendEvent(parent, generateChildEventTouchUp(index, x, y));
            break;
        default:
            NSLog(@"com.tlinkauto.springboard: Unknown touch event type in appendChildEvent, type: %d", type);
    }
}


/**
Perform touch events with data received from socket
*/
void performTouchFromRawData(UInt8 *eventData)
{
    int touchCount = getTouchCountFromDataArray(eventData);
    if (touchCount <= 0) {
        return;
    }

    // generate a parent event
	IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(), 3, 99, 1, 0, 0, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0, 0, 0); 
    IOHIDEventSetIntegerValue(parent , 0xb0019, 1); //set flags of parent event   flags: 0x20001 -> 0xa0001
    IOHIDEventSetIntegerValue(parent , 0x4, 1); //set flags of parent event   flags: 0xa0001 -> 0xa0011

    for (int i = 0; i < touchCount; i++)
    {
        //NSLog(@"### com.tlinkauto.springboard: get data. index: %d. type: %d. touchIndex: %d. x: %f. y: %f", i, getTouchTypeFromDataArray(eventData, i), getTouchIndexFromDataArray(eventData, i), getTouchXFromDataArray(eventData, i), getTouchYFromDataArray(eventData, i));
        int touchType = getTouchTypeFromDataArray(eventData, i);
        int x = getTouchXFromDataArray(eventData, i);
        int y = getTouchYFromDataArray(eventData, i);
        int index = getTouchIndexFromDataArray(eventData, i);
        if (index < 0 || index >= MAX_FINGER_INDEX) {
            continue;
        }

        appendChildEvent(parent, touchType, index, x, y); // append child event to parent

        switch (touchType)
        {
            case TOUCH_MOVE:
                eventsToAppend[index][EVENT_VALID_INDEX] = VALID_AT_NEXT_APPEND;
                eventsToAppend[index][EVENT_TYPE_INDEX] = TOUCH_MOVE;
                eventsToAppend[index][EVENT_X_INDEX] = (int)x;
                eventsToAppend[index][EVENT_Y_INDEX] = (int)y;
                break;
            case TOUCH_DOWN:
                eventsToAppend[index][EVENT_VALID_INDEX] = VALID_AT_NEXT_APPEND;
                eventsToAppend[index][EVENT_TYPE_INDEX] = TOUCH_DOWN;
                eventsToAppend[index][EVENT_X_INDEX] = (int)x; //!!!!!!directly converting to int may couse some precision problems
                eventsToAppend[index][EVENT_Y_INDEX] = (int)y; //!!!
                break;
            case TOUCH_UP:
                eventsToAppend[index][EVENT_VALID_INDEX] = NOT_VALID;
                break;
        }

    }

    for (int i = 0; i < MAX_FINGER_INDEX; i++)
    {
        if (eventsToAppend[i][EVENT_VALID_INDEX] == VALID)
        {
            //NSLog(@"com.tlinkauto.springboard: appending event for finger: %d. type: %d. x: %d. y: %d", i, eventsToAppend[i][EVENT_TYPE_INDEX], eventsToAppend[i][EVENT_X_INDEX], eventsToAppend[i][EVENT_Y_INDEX]);
            appendChildEvent(parent, eventsToAppend[i][EVENT_TYPE_INDEX], i, eventsToAppend[i][EVENT_X_INDEX], eventsToAppend[i][EVENT_Y_INDEX]);
        }
        else if (eventsToAppend[i][EVENT_VALID_INDEX] == VALID_AT_NEXT_APPEND) // make it valid
        {
            //NSLog(@"com.tlinkauto.springboard:  finger: %d to become valid. type: %d. x: %d. y: %d", i, eventsToAppend[i][EVENT_TYPE_INDEX], eventsToAppend[i][EVENT_X_INDEX], eventsToAppend[i][EVENT_Y_INDEX]);
            eventsToAppend[i][EVENT_VALID_INDEX] = VALID;
        }
    }

    IOHIDEventSetIntegerValue(parent, 0xb0007, 0x23);
    IOHIDEventSetIntegerValue(parent, 0xb0008, 0x1);
    IOHIDEventSetIntegerValue(parent, 0xb0009, 0x1);

    postIOHIDEvent(parent);
    CFRelease(parent);
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

    zx_touch_logf("initSenderId: waiting for a real user touch to learn senderID");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // I know the code here is bad here, change this later.
        while (true)
        {
            [NSThread sleepForTimeInterval:2.0f];

            if (ioHIDEventSystemForSenderID != NULL && senderID != 0x0) // unregister the callback
            {
                IOHIDEventSystemClientUnregisterEventCallback(ioHIDEventSystemForSenderID);
                IOHIDEventSystemClientUnscheduleWithRunLoop(ioHIDEventSystemForSenderID, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
                NSLog(@"com.tlinkauto.springboard: unregister get sender id callback!");
                break;
            }
        }
    });

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

			senderID = IOHIDEventGetSenderID(event);

            NSInteger currentTime = [[NSDate date] timeIntervalSince1970];
            NSInteger timeSinceReboot = [NSProcessInfo processInfo].systemUptime;
            NSInteger rebootTime = currentTime - timeSinceReboot;

            NSDictionary *dict = @{@"lastReboot":@(rebootTime), @"senderID": @(senderID)};

            [dict writeToFile:[NSString stringWithFormat:@"%@/coreutils/touching/%@", getDocumentRoot(), TOUCH_SENDER_ID_PLIST_FILE_NAME] atomically: YES];

			NSLog(@"com.tlinkauto.springboard: sender id is: %qX", senderID);
			zx_touch_logf("setSenderIdCallback: senderID=%llX", senderID);
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
