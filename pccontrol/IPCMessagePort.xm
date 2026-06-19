#include "IPCMessagePort.h"
#include "IPCConstants.h"
#include "HardwareKey.h"
#include "Task.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>

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

    NSLog(@"### com.tlinkauto.springboard: IPC received command: %@", command);
    if ([command isEqualToString:[NSString stringWithUTF8String:kTLinkautoIPCCommandHome]]) {
        NSError *error = nil;
        sendHardwareKeyEventFromRawData((UInt8 *)"1;;1", &error);
        sendHardwareKeyEventFromRawData((UInt8 *)"0;;1", &error);
        const char *response = "0\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }

    if ([command isEqualToString:[NSString stringWithUTF8String:kTLinkautoIPCCommandPing]]) {
        const char *response = "0\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }

    NSString *taskPrefix = [NSString stringWithUTF8String:kTLinkautoIPCCommandTaskPrefix];
    if ([command hasPrefix:taskPrefix]) {
        NSString *rawTask = [command substringFromIndex:[taskPrefix length]];
        if ([rawTask length] > 0) {
            CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
            NSLog(@"### com.tlinkauto.springboard: IPC task start: %@", rawTask);
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
                    NSLog(@"### com.tlinkauto.springboard: IPC task response in %.3fs: %@", duration, responseString);
                    return responseData;
                }
                if (responseProperty) {
                    CFRelease(responseProperty);
                }
            } else {
                processTask((UInt8 *)[rawTask UTF8String]);
            }
            CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - startTime;
            NSLog(@"### com.tlinkauto.springboard: IPC task finished in %.3fs without response", duration);
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
        NSLog(@"### com.tlinkauto.springboard: IPC server already running.");
        return;
    }

    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    Boolean shouldFree = false;
    ipcLocalPort = CFMessagePortCreateLocal(kCFAllocatorDefault,
                                            kTLinkautoIPCPortName,
                                            handleIPCMessage,
                                            &context,
                                            &shouldFree);
    if (!ipcLocalPort) {
        NSLog(@"### com.tlinkauto.springboard: failed to create IPC message port.");
        return;
    }

    ipcRunLoopSource = CFMessagePortCreateRunLoopSource(kCFAllocatorDefault, ipcLocalPort, 0);
    if (!ipcRunLoopSource) {
        NSLog(@"### com.tlinkauto.springboard: failed to create IPC run loop source.");
        CFRelease(ipcLocalPort);
        ipcLocalPort = NULL;
        return;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), ipcRunLoopSource, kCFRunLoopCommonModes);
    NSData *markerData = [@"ready" dataUsingEncoding:NSUTF8StringEncoding];
    if (![markerData writeToFile:kTLinkautoIPCReadyMarkerPath atomically:YES]) {
        NSLog(@"### com.tlinkauto.springboard: failed to write IPC ready marker.");
    } else {
        NSLog(@"### com.tlinkauto.springboard: IPC ready marker written.");
    }
    NSLog(@"### com.tlinkauto.springboard: IPC message port started.");
}

void startIPCServerOnBackgroundThread()
{
    if (ipcThreadStarted) {
        NSLog(@"### com.tlinkauto.springboard: IPC server thread already started.");
        return;
    }
    ipcThreadStarted = YES;
    NSLog(@"### com.tlinkauto.springboard: starting IPC server thread.");
    NSThread *ipcThread = [[NSThread alloc] initWithBlock:^{
        @autoreleasepool {
            startIPCServer();
            CFRunLoopRun();
        }
    }];
    [ipcThread start];
}
