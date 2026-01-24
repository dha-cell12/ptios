// TODO: multiple client write back support

#include "SocketServer.h"
#include "IPCConstants.h"
#include <string.h>
#include <ctype.h>
#include <dispatch/dispatch.h>

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#ifdef ZX_DAEMON
#import "../pccontrol/TemplateMatch.h"
// Needed for TextRecognizer subtask constants (e.g. TASK_TEXT_FROM_AREA, TASK_GET_SUPPORTED_LANGUAGE_LIST)
#import "../pccontrol/TextRecognization/TextRecognizer.h"
#import "../pccontrol/TextRecognization/VKOcrManager.h"
#endif

#import "../pccontrol/Common.h"

CFSocketRef socketRef;
CFWriteStreamRef writeStreamRef = NULL;
CFReadStreamRef readStreamRef = NULL;
static NSMutableDictionary *socketClients = NULL;

static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo);
static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

// Reference: https://www.jianshu.com/p/9353105a9129

static dispatch_queue_t ipcQueue()
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.zjx.zxtouchd.ipc", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static int getTaskTypeFromBuffer(const char *buffer)
{
    if (!buffer || !isdigit(buffer[0]) || !isdigit(buffer[1])) {
        return -1;
    }
    return (buffer[0] - '0') * 10 + (buffer[1] - '0');
}

static bool shouldRouteToSpringBoard(int taskType)
{
    switch (taskType) {
        case 10: // TASK_PERFORM_TOUCH
        case 11: // TASK_PROCESS_BRING_FOREGROUND
        case 12: // TASK_SHOW_ALERT_BOX
        case 14: // TASK_TOUCH_RECORDING_START
        case 15: // TASK_TOUCH_RECORDING_STOP
        case 16: // TASK_CRAZY_TAP
        case 17: // TASK_RAPID_FIRE_TAP
        case 19: // TASK_PLAY_SCRIPT
        case 20: // TASK_PLAY_SCRIPT_FORCE_STOP
        #ifndef ZX_DAEMON
        case 21: // TASK_TEMPLATE_MATCH
#endif
        case 22: // TASK_SHOW_TOAST
        case 23: // TASK_COLOR_PICKER
        case 24: // TASK_TEXT_INPUT
        case 25: // TASK_GET_DEVICE_INFO
        case 26: // TASK_TOUCH_INDICATOR
        #ifndef ZX_DAEMON
        case 27: // TASK_TEXT_RECOGNIZER
#endif
        case 28: // TASK_COLOR_SEARCHER
        case 29: // TASK_SCREENSHOT
        case 30: // TASK_HARDWARE_KEY
        case 31: // TASK_APP_KILL
        case 32: // TASK_APP_STATE
        case 33: // TASK_APP_INFO
        case 34: // TASK_FRONTMOST_APP_ID
        case 35: // TASK_FRONTMOST_APP_ORIENTATION
        case 36: // TASK_SET_AUTO_LAUNCH
        case 37: // TASK_LIST_AUTO_LAUNCH
        case 38: // TASK_SET_TIMER
        case 39: // TASK_REMOVE_TIMER
        case 40: // TASK_KEEP_AWAKE
        case 41: // TASK_STOP_SCRIPT
        case 42: // TASK_DIALOG
        case 43: // TASK_CLEAR_DIALOG
        case 44: // TASK_ROOT_DIR
        case 45: // TASK_CURRENT_DIR
        case 46: // TASK_BOT_PATH
        case 90: // TASK_UPDATE_CACHE
            return true;
        default:
            return false;
    }
}

static bool shouldWaitForResponse(int taskType)
{
    switch (taskType) {
        case 14: // TASK_TOUCH_RECORDING_START
        case 15: // TASK_TOUCH_RECORDING_STOP
        case 16: // TASK_CRAZY_TAP
        case 17: // TASK_RAPID_FIRE_TAP
        case 19: // TASK_PLAY_SCRIPT
        case 20: // TASK_PLAY_SCRIPT_FORCE_STOP
        case 36: // TASK_SET_AUTO_LAUNCH
        case 38: // TASK_SET_TIMER
        case 39: // TASK_REMOVE_TIMER
        case 40: // TASK_KEEP_AWAKE
            return false;
        default:
            return true;
    }
}

static CFDataRef sendIPCMessage(const char *payload, bool waitForResponse)
{
    CFDataRef responseData = NULL;
    if (access(kZXTouchIPCReadyMarkerPath, F_OK) != 0) {
        NSLog(@"### com.zjx.zxtouchd: IPC ready marker missing.");
        return NULL;
    }
    CFMessagePortRef remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, kZXTouchIPCPortName);
    if (!remotePort) {
        NSLog(@"### com.zjx.zxtouchd: unable to find SpringBoard IPC port.");
        return NULL;
    }

    bool pingRequired = waitForResponse && strcmp(payload, kZXTouchIPCCommandPing) != 0;
    if (pingRequired) {
        static CFAbsoluteTime lastPingSuccess = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastPingSuccess > 1.0) {
            CFDataRef pingData = CFDataCreate(kCFAllocatorDefault,
                                              (const UInt8 *)kZXTouchIPCCommandPing,
                                              strlen(kZXTouchIPCCommandPing));
            SInt32 pingResult = CFMessagePortSendRequest(remotePort,
                                                         1,
                                                         pingData,
                                                         2.0,
                                                         2.0,
                                                         kCFRunLoopDefaultMode,
                                                         NULL);
            if (pingData) {
                CFRelease(pingData);
            }
            if (pingResult != kCFMessagePortSuccess) {
                NSLog(@"### com.zjx.zxtouchd: IPC ping failed with code %d", (int)pingResult);
                CFRelease(remotePort);
                return NULL;
            } else {
                lastPingSuccess = now;
            }
        }
    }

    CFDataRef messageData = CFDataCreate(kCFAllocatorDefault, (const UInt8 *)payload, strlen(payload));
    NSLog(@"### com.zjx.zxtouchd: IPC send payload: %s", payload);
    CFDataRef *responseTarget = waitForResponse ? &responseData : NULL;
    const CFTimeInterval sendTimeout = waitForResponse ? 5.0 : 1.5;
    SInt32 result = CFMessagePortSendRequest(remotePort,
                                             1,
                                             messageData,
                                             sendTimeout,
                                             sendTimeout,
                                             kCFRunLoopDefaultMode,
                                             responseTarget);
    if (result != kCFMessagePortSuccess) {
        NSLog(@"### com.zjx.zxtouchd: IPC send failed with code %d", (int)result);
    } else {
        NSLog(@"### com.zjx.zxtouchd: IPC send success");
    }

    if (messageData) {
        CFRelease(messageData);
    }
    CFRelease(remotePort);
    return responseData;
}

// ------------------------------
// Daemon-side handlers for heavy tasks (21/27)
// Strategy: ask SpringBoard to capture a screenshot via task 29, then process locally.
// NOTE: Return value is a malloc'ed C-string that caller must free().

#ifdef ZX_DAEMON
static char *handleTemplateMatchTaskInDaemon(const char *buffer);
static char *handleTextRecognizerTaskInDaemon(const char *buffer);
#endif

static char *zx_strdup_nsstring(NSString *s)
{
    if (!s) {
        const char *fallback = "1;;nil_response\r\n";
        return (char *)strdup(fallback);
    }
    const char *utf8 = [s UTF8String];
    if (!utf8) {
        const char *fallback = "1;;utf8_encode_failed\r\n";
        return (char *)strdup(fallback);
    }
    return (char *)strdup(utf8);
}

static NSString *zx_ipcResponseToString(CFDataRef responseData)
{
    if (!responseData) return nil;
    const UInt8 *bytes = CFDataGetBytePtr(responseData);
    CFIndex len = CFDataGetLength(responseData);
    if (!bytes || len <= 0) return nil;
    NSData *d = [NSData dataWithBytes:bytes length:(NSUInteger)len];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

// Ask SpringBoard to capture screenshot to a given path.
// On success returns the path (may be same as requested), on failure returns nil and sets errString (already formatted for client).
static NSString *zx_ipcCaptureScreenshotToPath(NSString *path, NSString **errString)
{
    if (!path || [path length] == 0) {
        if (errString) *errString = @"-1;;Screenshot path is empty.\r\n";
        return nil;
    }

    // Build a screenshot task payload: 29 + "1;;<path>" (SCREENSHOT_TASK_CAPTURE)
    NSString *taskPayload = [NSString stringWithFormat:@"%s29%s1;;%@", kZXTouchIPCCommandTaskPrefix, "", path];
    __block CFDataRef responseData = NULL;
    dispatch_sync(ipcQueue(), ^{
        responseData = sendIPCMessage([taskPayload UTF8String], true);
    });
    NSString *resp = zx_ipcResponseToString(responseData);
    if (responseData) CFRelease(responseData);
    if (!resp) {
        if (errString) *errString = @"1;;ipc_screenshot_no_response\r\n";
        return nil;
    }
    // Success format: "0;;<path>\r\n". Error format typically: "-1;;...\r\n".
    if ([resp hasPrefix:@"0;;"]) {
        NSString *p = [resp substringFromIndex:3];
        // trim CRLF
        p = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([p length] == 0) {
            // If SB returns empty path, use requested
            return path;
        }
        return p;
    }

    // Forward error as-is
    if (errString) *errString = resp;
    return nil;
}

static int zx_ipcGetFrontmostOrientation(void)
{
    NSString *taskPayload = [NSString stringWithFormat:@"%s35", kZXTouchIPCCommandTaskPrefix];
    __block CFDataRef responseData = NULL;
    dispatch_sync(ipcQueue(), ^{
        responseData = sendIPCMessage([taskPayload UTF8String], true);
    });
    NSString *resp = zx_ipcResponseToString(responseData);
    if (responseData) CFRelease(responseData);
    if (!resp || ![resp hasPrefix:@"0;;"]) {
        return 1; // default Up
    }
    NSString *val = [[resp substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [val intValue] ?: 1;
}

static NSString *zx_makeTempScreenshotPath(void)
{
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"/tmp/zxtouchd_capture_%@.png", uuid];
}

static void zx_safeUnlink(NSString *path)
{
    if (!path) return;
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

#ifdef ZX_DAEMON
static char *handleTemplateMatchTaskInDaemon(const char *buffer)
{
    // buffer begins with "21..."; SpringBoard passes eventData = buff + 2
    const char *eventC = buffer ? buffer + 2 : NULL;
    if (!eventC) return (char *)strdup("-1;;Empty task payload.\r\n");
    NSString *eventData = [NSString stringWithUTF8String:eventC] ?: @"";
    NSArray *parts = [eventData componentsSeparatedByString:@";;"];
    NSString *templatePath = (parts.count >= 1) ? parts[0] : @"";
    int maxTryTimes = 2;
    float acceptableValue = 0.8f;
    float scaleRation = 0.8f;
    if (parts.count == 4) {
        maxTryTimes = [parts[1] intValue];
        acceptableValue = [parts[2] floatValue];
        scaleRation = [parts[3] floatValue];
    } else if (parts.count != 1) {
        return (char *)strdup("-1;;The data format should be \"template_path[;;max_try_times;;acceptable_value;;scaleRation]\"\r\n");
    }
    if ([templatePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:templatePath]) {
        NSString *err = [NSString stringWithFormat:@"-1;;Template image not found for image matching. Template path: %@\r\n", templatePath];
        return zx_strdup_nsstring(err);
    }

    NSString *tmpPath = zx_makeTempScreenshotPath();
    NSString *errString = nil;
    NSString *shotPath = zx_ipcCaptureScreenshotToPath(tmpPath, &errString);
    if (!shotPath) {
        zx_safeUnlink(tmpPath);
        return zx_strdup_nsstring(errString ?: @"-1;;Failed to capture screenshot.\r\n");
    }

    NSError *err = nil;
    TemplateMatch *tm = [[TemplateMatch alloc] init];
    [tm setAcceptableValue:acceptableValue];
    [tm setMaxTryTimes:maxTryTimes];
    [tm setScaleRation:scaleRation];
    CGRect r = [tm templateMatchWithPath:shotPath templatePath:templatePath error:&err];
    zx_safeUnlink(shotPath);

    if (err) {
        return zx_strdup_nsstring([err localizedDescription]);
    }
    NSString *resp = [NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", r.origin.x, r.origin.y, r.size.width, r.size.height];
    return zx_strdup_nsstring(resp);
}
#endif


#ifdef ZX_DAEMON
static char *handleTextRecognizerTaskInDaemon(const char *buffer)
{
    const char *eventC = buffer ? buffer + 2 : NULL;
    if (!eventC) return (char *)strdup("-1;;Empty task payload.\r\n");

    if (SYSTEM_VERSION_LESS_THAN(@"13.0")) {
        return (char *)strdup("-1;;OCR only supports iOS13 or newer version of iOS.\r\n");
    }

    NSString *eventData = [NSString stringWithUTF8String:eventC] ?: @"";
    NSArray *data = [eventData componentsSeparatedByString:@";;"];
    if (data.count == 0) {
        return (char *)strdup("-1;;Data not in good format.\r\n");
    }

    int subtask = [data[0] intValue];
    if (subtask == TASK_GET_SUPPORTED_LANGUAGE_LIST) {
        if (data.count < 2) {
            return (char *)strdup("-1;;Data not in good format. The format should be 2;;level\r\n");
        }
        VNRequestTextRecognitionLevel level = VNRequestTextRecognitionLevelAccurate;
        if ([data[1] intValue] == 1) level = VNRequestTextRecognitionLevelFast;
        NSError *err = nil;
        NSArray *supported = nil;
        if (SYSTEM_VERSION_LESS_THAN(@"14.0")) {
            supported = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:1 error:&err];
        } else {
            supported = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:2 error:&err];
        }
        if (err) {
            NSString *e = [NSString stringWithFormat:@"-1;;Error: %@\r\n", err];
            return zx_strdup_nsstring(e);
        }
        NSString *joined = [supported componentsJoinedByString:@";;"];
        NSString *resp = [NSString stringWithFormat:@"0;;%@\r\n", joined ?: @""];
        return zx_strdup_nsstring(resp);
    }

    if (subtask != TASK_TEXT_FROM_AREA) {
        return (char *)strdup("-1;;Text recognition unknown task type\r\n");
    }

    // Expected format: 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path
    if (data.count < 8) {
        return (char *)strdup("-1;;Data not in good format. The format should be 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path\r\n");
    }

    NSString *rectData = data[1];
    NSString *customWordsData = data[2];
    float minimumHeight = [data[3] floatValue];
    int levelData = [data[4] intValue];
    NSString *languagesData = data[5];
    BOOL correct = [data[6] boolValue];
    NSString *debugPath = data[7];

    NSArray *rect = [rectData componentsSeparatedByString:@",,"];
    if (rect.count < 4) {
        return (char *)strdup("-1;;Rect data not in good format. The format should be x1,,y1,,width,,height\r\n");
    }
    CGRect recognizeRect = CGRectMake([rect[0] floatValue], [rect[1] floatValue], [rect[2] floatValue], [rect[3] floatValue]);
    NSArray *customWords = [customWordsData componentsSeparatedByString:@",,"];
    if (minimumHeight <= 0) minimumHeight = 1.0f / 32.0f;
    VNRequestTextRecognitionLevel level = (levelData == 1) ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    NSArray *languages = [languagesData componentsSeparatedByString:@",,"];

    int orientation = zx_ipcGetFrontmostOrientation();

    NSString *tmpPath = zx_makeTempScreenshotPath();
    NSString *errString = nil;
    NSString *shotPath = zx_ipcCaptureScreenshotToPath(tmpPath, &errString);
    if (!shotPath) {
        zx_safeUnlink(tmpPath);
        return zx_strdup_nsstring(errString ?: @"-1;;Failed to capture screenshot.\r\n");
    }

    NSError *err = nil;
    VKOcrManager *ocr = [[VKOcrManager alloc] initWithImagePath:shotPath area:recognizeRect orientation:orientation];
    if (customWords.count > 1 || (customWords.count == 1 && ![customWords[0] isEqualToString:@""])) {
        [ocr setCustomWords:customWords];
    }
    [ocr setMinimumHeight:minimumHeight];
    [ocr setRecognitionLevel:level];
    if (languages.count > 1 || (languages.count == 1 && ![languages[0] isEqualToString:@""])) {
        [ocr setLanguages:languages];
    }
    [ocr setCorrection:correct];

    NSString *result = [ocr recognize:&err];
    // Debug image output in daemon is risky because VKOcrManager's debug path uses Screen/UIScreen.
    // To keep daemon stable, we skip debug output here.
    (void)debugPath;

    zx_safeUnlink(shotPath);

    if (err) {
        return zx_strdup_nsstring([err localizedDescription]);
    }
    NSString *resp = [NSString stringWithFormat:@"0;;%@\r\n", result ?: @""];
    return zx_strdup_nsstring(resp);
}
#endif


static void handleDaemonMessage(UInt8 *buff, CFWriteStreamRef client)
{
    if (!buff) {
        return;
    }
    NSLog(@"### com.zjx.zxtouchd: received task payload: %s", buff);
    const char *buffer = (const char *)buff;
    const int taskType = getTaskTypeFromBuffer(buffer);

// Handle heavy image/OCR tasks inside daemon to reduce SpringBoard load.
#ifdef ZX_DAEMON
if (taskType == 21 || taskType == 27) {#ifdef ZX_DAEMON

    const char *respC = (taskType == 21) ? handleTemplateMatchTaskInDaemon(buffer)
                                         : handleTextRecognizerTaskInDaemon(buffer);
#endif
    if (client && respC) {
        CFWriteStreamWrite(client, (const UInt8 *)respC, strlen(respC));
    }
#endif
    if (respC) free((void *)respC);
    return;
}

    bool isSpringBoardTask = taskType >= 0 && shouldRouteToSpringBoard(taskType);

    if (strcmp(buffer, kZXTouchIPCCommandHome) == 0) {
        isSpringBoardTask = true;
    }

        if (isSpringBoardTask) {
            char ipcPayload[4096];
            if (strcmp(buffer, kZXTouchIPCCommandHome) == 0) {
                snprintf(ipcPayload, sizeof(ipcPayload), "%s", kZXTouchIPCCommandHome);
            } else {
                snprintf(ipcPayload, sizeof(ipcPayload), "%s%s", kZXTouchIPCCommandTaskPrefix, buffer);
            }
            NSString *payloadString = [NSString stringWithUTF8String:ipcPayload];
            if (!payloadString) {
                return;
            }
            bool waitForResponse = strcmp(buffer, kZXTouchIPCCommandHome) == 0
                ? true
                : shouldWaitForResponse(taskType);
            __block CFDataRef responseData = NULL;
            dispatch_sync(ipcQueue(), ^{
                responseData = sendIPCMessage([payloadString UTF8String], waitForResponse);
            });
            if (client) {
            if (responseData) {
                const UInt8 *responseBytes = CFDataGetBytePtr(responseData);
                CFIndex responseLength = CFDataGetLength(responseData);
                if (responseBytes && responseLength > 0) {
                    CFWriteStreamWrite(client, responseBytes, responseLength);
                    NSData *responseNSData = [NSData dataWithBytes:responseBytes
                                                           length:(NSUInteger)responseLength];
                    NSString *responseString = [[NSString alloc] initWithData:responseNSData
                                                                     encoding:NSUTF8StringEncoding];
                    NSLog(@"### com.zjx.zxtouchd: IPC response: %@", responseString);
                } else {
                    NSLog(@"### com.zjx.zxtouchd: IPC response empty");
                }
                CFRelease(responseData);
            } else {
                const char *response = waitForResponse ? "1;;ipc_not_ready\r\n" : "0;;queued\r\n";
                CFWriteStreamWrite(client, (const UInt8 *)response, strlen(response));
            }
        }
        return;
    }

    if (client) {
        const char *response = "1;;zxtouchd: task handling not implemented\r\n";
        CFWriteStreamWrite(client, (const UInt8 *)response, strlen(response));
    }
}

void socketServer()
{
    @autoreleasepool {
        CFSocketRef _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, TCPServerAcceptCallBack, NULL);

        if (_socket == NULL) {
            NSLog(@"### com.zjx.zxtouchd: failed to create socket.");
            return;
        }

        UInt32 reused = 1;

        setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, (const void *)&reused, sizeof(reused));

        struct sockaddr_in Socketaddr;
        memset(&Socketaddr, 0, sizeof(Socketaddr));
        Socketaddr.sin_len = sizeof(Socketaddr);
        Socketaddr.sin_family = AF_INET;

        Socketaddr.sin_addr.s_addr = inet_addr(ZXTOUCHD_ADDR);

        Socketaddr.sin_port = htons(ZXTOUCHD_PORT);

        CFDataRef address = CFDataCreate(kCFAllocatorDefault,  (UInt8 *)&Socketaddr, sizeof(Socketaddr));

        if (CFSocketSetAddress(_socket, address) != kCFSocketSuccess) {

            if (_socket) {
                CFRelease(_socket);
            }

            _socket = NULL;
        }

        socketClients = [[NSMutableDictionary alloc] init];

        NSLog(@"### com.zjx.zxtouchd: connection waiting on port %d", ZXTOUCHD_PORT);
        CFRunLoopRef cfrunLoop = CFRunLoopGetCurrent();
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);

        CFRunLoopAddSource(cfrunLoop, source, kCFRunLoopCommonModes);

        CFRelease(source);
        CFRunLoopRun();
    }

}

static void readStream(CFReadStreamRef readStream, CFStreamEventType eventype, void * clientCallBackInfo)
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool{
            UInt8 readDataBuff[2048];
            memset(readDataBuff, 0, sizeof(readDataBuff));

            CFIndex hasRead = CFReadStreamRead(readStream, readDataBuff, sizeof(readDataBuff));

            if (hasRead > 0) {
                //don't know how it works, copied from https://www.educative.io/edpresso/splitting-a-string-using-strtok-in-c
                for(char * charSep = strtok((char*)readDataBuff, "\r\n"); charSep != NULL; charSep = strtok(NULL, "\r\n")) {
                    UInt8 *buff = (UInt8*)charSep;
                    id temp = [socketClients objectForKey:@((long)readStream)];
                    if (temp != nil) {
                        handleDaemonMessage(buff, (CFWriteStreamRef)[temp longValue]);
                    } else {
                        handleDaemonMessage(buff, NULL);
                    }
                }
            }
        }
    });

}

static void TCPServerAcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    if (kCFSocketAcceptCallBack == type) {

        CFSocketNativeHandle  nativeSocketHandle = *(CFSocketNativeHandle *)data;

        uint8_t name[SOCK_MAXADDRLEN];
        socklen_t namelen = sizeof(name);

        if (getpeername(nativeSocketHandle, (struct sockaddr *)name, &namelen) != 0) {

            NSLog(@"### com.zjx.zxtouchd: ++++++++getpeername+++++++");

            exit(1);
        }

        struct sockaddr_in *addr_in = (struct sockaddr_in *)name;
        NSLog(@"### com.zjx.zxtouchd: connection starts from %s:%d", inet_ntoa(addr_in->sin_addr), ntohs(addr_in->sin_port));

        readStreamRef = NULL;
        writeStreamRef = NULL;

        CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStreamRef, &writeStreamRef);

        if (readStreamRef && writeStreamRef) {
            CFReadStreamOpen(readStreamRef);
            CFWriteStreamOpen(writeStreamRef);

            CFStreamClientContext context = {0, NULL, NULL, NULL };

            if (!CFReadStreamSetClient(readStreamRef, kCFStreamEventHasBytesAvailable, readStream, &context)) {
                NSLog(@"### com.zjx.zxtouchd: error 1");
                return;
            }

            CFReadStreamScheduleWithRunLoop(readStreamRef, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);

            [socketClients setObject:@((long)writeStreamRef) forKey:@((long)readStreamRef)];
        }
        else
        {
            close(nativeSocketHandle);
        }

    }

}
