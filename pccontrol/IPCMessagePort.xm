#include "IPCMessagePort.h"
#include "IPCConstants.h"
#include "HardwareKey.h"
#include "Task.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>

// File logging fallback for devices without unified logging CLI.
static NSString *const kZXTouchIPCLogPath = @"/var/mobile/Library/ZXTouch/ipc_pccontrol.log";

static void zx_append_ipc_log(NSString *line)
{
    if (!line) return;
    @autoreleasepool {
        // Using stdio append is the most reliable across iOS/jailbreak environments.
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/ZXTouch"
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];

        NSString *timestamp = [[NSDate date] description];
        NSString *full = [NSString stringWithFormat:@"[%@] %@\n", timestamp, line];
        const char *cpath = [kZXTouchIPCLogPath fileSystemRepresentation];
        FILE *fp = fopen(cpath, "a");
        if (!fp) {
            return;
        }
        fputs([full UTF8String], fp);
        fflush(fp);
        fclose(fp);
    }
}

static CFMessagePortRef ipcLocalPort = NULL;
static CFRunLoopSourceRef ipcRunLoopSource = NULL;
static BOOL ipcThreadStarted = NO;

static CFDataRef handleIPCMessage(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    if (!data) {
        return NULL;
    }

    const UInt8 *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    if (!bytes || length <= 0) {
        return NULL;
    }

    NSString *command = [[NSString alloc] initWithBytes:bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
    if (!command) {
        return NULL;
    }

    NSLog(@"### com.zjx.springboard: IPC received command: %@", command);
    zx_append_ipc_log([NSString stringWithFormat:@"IPC received: %@", command]);
    if ([command isEqualToString:[NSString stringWithUTF8String:kZXTouchIPCCommandHome]]) {
        zx_append_ipc_log(@"CMD_HOME");
        NSError *error = nil;
        sendHardwareKeyEventFromRawData((UInt8 *)"1;;1", &error);
        sendHardwareKeyEventFromRawData((UInt8 *)"0;;1", &error);
        const char *response = "0\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }

    if ([command isEqualToString:[NSString stringWithUTF8String:kZXTouchIPCCommandPing]]) {
        zx_append_ipc_log(@"CMD_PING");
        const char *response = "0\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }

    NSString *taskPrefix = [NSString stringWithUTF8String:kZXTouchIPCCommandTaskPrefix];
    if ([command hasPrefix:taskPrefix]) {
        NSString *rawTask = [command substringFromIndex:[taskPrefix length]];
        if ([rawTask length] > 0) {
            CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
            NSLog(@"### com.zjx.springboard: IPC task start: %@", rawTask);
            zx_append_ipc_log([NSString stringWithFormat:@"TASK start: %@", rawTask]);
            CFWriteStreamRef responseStream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault,
                                                                                      kCFAllocatorDefault);
            if (responseStream) {
                CFWriteStreamOpen(responseStream);
                processTask((UInt8 *)[rawTask UTF8String], responseStream);
                CFTypeRef responseProperty = CFWriteStreamCopyProperty(responseStream, kCFStreamPropertyDataWritten);
                CFWriteStreamClose(responseStream);
                CFRelease(responseStream);
                CFDataRef responseData = NULL;
                if (responseProperty && CFGetTypeID(responseProperty) == CFDataGetTypeID()) {
                    responseData = (CFDataRef)responseProperty;
                }
                if (responseData && CFDataGetLength(responseData) > 0) {
                    CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - startTime;
                    NSData *responseNSData = [NSData dataWithBytes:CFDataGetBytePtr(responseData)
                                                           length:(NSUInteger)CFDataGetLength(responseData)];
                    NSString *responseString = [[NSString alloc] initWithData:responseNSData
                                                                     encoding:NSUTF8StringEncoding];
                    NSLog(@"### com.zjx.springboard: IPC task response in %.3fs: %@", duration, responseString);
                    zx_append_ipc_log([NSString stringWithFormat:@"TASK response in %.3fs: %@", duration, responseString ?: @"(null)"]);
                    return responseData;
                }
                if (responseProperty) {
                    CFRelease(responseProperty);
                }
            } else {
                processTask((UInt8 *)[rawTask UTF8String]);
            }
            CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - startTime;
            NSLog(@"### com.zjx.springboard: IPC task finished in %.3fs without response", duration);
            zx_append_ipc_log([NSString stringWithFormat:@"TASK finished in %.3fs (no response)", duration]);
        }
        const char *response = "0\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }

    const char *response = "1;;unknown_command\r\n";
    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
}

void startIPCServer()
{
    if (ipcLocalPort) {
        NSLog(@"### com.zjx.springboard: IPC server already running.");
        zx_append_ipc_log(@"IPC server already running");
        return;
    }

    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    Boolean shouldFree = false;
    ipcLocalPort = CFMessagePortCreateLocal(kCFAllocatorDefault,
                                            kZXTouchIPCPortName,
                                            handleIPCMessage,
                                            &context,
                                            &shouldFree);
    if (!ipcLocalPort) {
        NSLog(@"### com.zjx.springboard: failed to create IPC message port.");
        zx_append_ipc_log(@"ERROR: failed to create IPC message port (CFMessagePortCreateLocal returned NULL)");
        return;
    }

    ipcRunLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, ipcLocalPort, 0);
    if (!ipcRunLoopSource) {
        NSLog(@"### com.zjx.springboard: failed to create IPC run loop source.");
        zx_append_ipc_log(@"ERROR: failed to create IPC run loop source");
        CFRelease(ipcLocalPort);
        ipcLocalPort = NULL;
        return;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), ipcRunLoopSource, kCFRunLoopCommonModes);
    NSData *markerData = [@"ready" dataUsingEncoding:NSUTF8StringEncoding];
    if (![markerData writeToFile:kZXTouchIPCReadyMarkerPath atomically:YES]) {
        NSLog(@"### com.zjx.springboard: failed to write IPC ready marker.");
        zx_append_ipc_log(@"ERROR: failed to write IPC ready marker");
    } else {
        NSLog(@"### com.zjx.springboard: IPC ready marker written.");
        zx_append_ipc_log(@"IPC ready marker written");
    }
    NSLog(@"### com.zjx.springboard: IPC message port started.");
    zx_append_ipc_log(@"IPC message port started");
}

void startIPCServerOnBackgroundThread()
{
    if (ipcThreadStarted) {
        NSLog(@"### com.zjx.springboard: IPC server thread already started.");
        return;
    }
    ipcThreadStarted = YES;
    NSLog(@"### com.zjx.springboard: starting IPC server thread.");
    NSThread *ipcThread = [[NSThread alloc] initWithBlock:^{
        @autoreleasepool {
            startIPCServer();
            CFRunLoopRun();
        }
    }];
    [ipcThread start];
}
