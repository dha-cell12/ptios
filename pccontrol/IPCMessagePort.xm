#include "../shared/TLinkC01Ingress.h"
#include "IPCMessagePort.h"
#import "TLinkDiagnostic.h"
#include "IPCConstants.h"
#include "HardwareKey.h"
#include "Task.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkIPCPolicy.h"

static CFMessagePortRef ipcLocalPort = NULL;
static CFRunLoopSourceRef ipcRunLoopSource = NULL;
static BOOL ipcThreadStarted = NO;

static CFDataRef handleIPCMessage(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info)
{
    @autoreleasepool {
        (void)local; (void)info;
        if (!data) {
            return NULL;
        }

        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex length = CFDataGetLength(data);
        if (!bytes || length <= 0) {
            return NULL;
        }

        uint64_t ingressDeadline=0;
        if(msgid==TLinkC01IPCMessage){
            TLinkC01Envelope envelope;
            const auto result=TLinkC01Decode(bytes,size_t(length),envelope);
            if(result!=TLinkC01DecodeResult::Valid){
                const char *failure=result==TLinkC01DecodeResult::Expired?"1;;c01_request_expired\r\n":"1;;c01_ipc_envelope_invalid\r\n";
                return CFDataCreate(kCFAllocatorDefault,(const UInt8 *)failure,strlen(failure));
            }
            bytes=envelope.payload;length=CFIndex(envelope.length);ingressDeadline=envelope.deadline;
        }

        // Task 10 has no response body. Keep its byte/length path out of NSString,
        // logging and response-stream allocation, while retaining the task license gate.
        if (TLinkIPCNoReplyTouch(msgid, bytes, (size_t)length)) {
            processTaskWithContext((UInt8 *)bytes + 6, (size_t)length - 6, NULL, nil);
            return NULL;
        }

        NSString *command = [[NSString alloc] initWithBytes:bytes length:(NSUInteger)length encoding:NSUTF8StringEncoding];
        if (!command) {
            return NULL;
        }

        NSString *taskPrefix = [NSString stringWithUTF8String:kTLinkautoIPCCommandTaskPrefix];
        NSString *taskBody = [command hasPrefix:taskPrefix]
            ? [command substringFromIndex:taskPrefix.length] : @"";
        NSInteger uiTreeTask = taskBody.length >= 2
            ? [[taskBody substringToIndex:2] integerValue] : 0;
        BOOL redactUITree = uiTreeTask >= 77 && uiTreeTask <= 81;
        BOOL quietTask = uiTreeTask == 10 || uiTreeTask == 61;
        if (redactUITree) {
            NSLog(@"### com.tlinkauto.springboard: IPC received UI tree task=%ld payload_redacted=1",
                  (long)uiTreeTask);
        } else if (!quietTask) {
            NSLog(@"### com.tlinkauto.springboard: IPC received command: %@", command);
        }
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

        if ([command hasPrefix:taskPrefix]) {
            NSString *rawTask = [command substringFromIndex:[taskPrefix length]];
            if ([rawTask length] > 0) {
                if (msgid == TLinkIPCNoReplyMessage) {
                    processTaskWithContext((UInt8 *)[rawTask UTF8String],
                                           [rawTask lengthOfBytesUsingEncoding:NSUTF8StringEncoding], NULL, nil);
                    return NULL;
                }
                const double startTime = TLinkNativeNowNs() / 1e9;
                auto budget = std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{}, ingressDeadline, 1024 * 1024, false, true);
                TLinkNativeBudgetScope responseScope(budget);
                UInt8 placeholder[1] = {0}; // notifyClient writes to the budget, never to this placeholder.
                CFWriteStreamRef responseStream = CFWriteStreamCreateWithBuffer(kCFAllocatorDefault, placeholder, sizeof(placeholder));
                if (!responseStream || !CFWriteStreamOpen(responseStream)) {
                    if (responseStream) CFRelease(responseStream);
                    const char *failure = "1;;ipc_response_sink_failed\r\n";
                    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)failure, strlen(failure));
                }
                @try {
                    processTaskWithContext((UInt8 *)[rawTask UTF8String],
                                           [rawTask lengthOfBytesUsingEncoding:NSUTF8StringEncoding], responseStream, nil);
                } @finally { CFWriteStreamClose(responseStream); CFRelease(responseStream); }
                const auto &response = budget->response();
                if (budget->reason() == TLinkNativeStop::OutputLimit) {
                    const char *failure = "1;;ipc_response_too_large\r\n";
                    return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)failure, strlen(failure));
                }
                if(budget->stopped()){
                    const char *failure="1;;c01_request_expired\r\n";
                    return CFDataCreate(kCFAllocatorDefault,(const UInt8 *)failure,strlen(failure));
                }
                if (redactUITree) {
                    NSLog(@"### com.tlinkauto.springboard: IPC UI tree task=%ld response in %.3fs bytes=%ld",
                          (long)uiTreeTask, TLinkNativeNowNs() / 1e9 - startTime, (long)response.size());
                }
                if (!response.empty()) return CFDataCreate(kCFAllocatorDefault, response.data(), (CFIndex)response.size());

            }
            const char *response = "0\r\n";
            return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
        }

        const char *response = "1;;unknown_command\r\n";
        return CFDataCreate(kCFAllocatorDefault, (const UInt8 *)response, strlen(response));
    }
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
