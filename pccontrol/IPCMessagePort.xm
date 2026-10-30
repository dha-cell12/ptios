#include "../shared/TLinkCaptureLeasePOSIX.h"
#include "../shared/TLinkC01Ingress.h"
#include "../shared/TLinkVPNIPC.h"
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
        if(msgid==TLinkVPNIPCMessage){
            TLinkVPNIPCEnvelope envelope;
            const auto result=TLinkVPNIPCDecode(bytes,size_t(length),envelope);
            if(result!=TLinkVPNIPCDecodeResult::Valid){
                const char *failure=result==TLinkVPNIPCDecodeResult::Expired?"1;;vpn_ipc_expired\r\n":"1;;vpn_ipc_invalid\r\n";
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
                std::unique_ptr<TLinkCaptureReceiverLease> ownedCapture;
                NSString *ownedPrefix=[NSString stringWithFormat:@"29%d;;",kTLinkOwnedCaptureAction];
                if(msgid==TLinkC01IPCMessage&&[rawTask hasPrefix:ownedPrefix]){
                    NSString *path=[rawTask substringFromIndex:ownedPrefix.length];
                    ownedCapture.reset(new TLinkCaptureReceiverLease(path.UTF8String,budget));
                    if(!ownedCapture->valid()){
                        const char *failure="1;;owned_capture_lease_missing_or_expired\r\n";
                        return CFDataCreate(kCFAllocatorDefault,(const UInt8 *)failure,strlen(failure));
                    }
                }
                TLinkCaptureReceiverScope captureScope(ownedCapture.get());
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
                } @finally {
                    CFWriteStreamClose(responseStream);CFRelease(responseStream);
                    if(ownedCapture)ownedCapture->finish();
                }
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

// BEGIN C01 isolated IPC receiver.
static CFDataRef handleC01IPCMessage(CFMessagePortRef local,SInt32 msgid,CFDataRef data,void *info)
{
    auto failure=[](const char *line)->CFDataRef{return CFDataCreate(kCFAllocatorDefault,(const UInt8 *)line,strlen(line));};
    if(msgid!=TLinkC01IPCMessage||!data)return failure("1;;c01_ipc_envelope_required\r\n");
    TLinkC01Envelope envelope;
    const auto decoded=TLinkC01Decode(CFDataGetBytePtr(data),size_t(CFDataGetLength(data)),envelope);
    if(decoded!=TLinkC01DecodeResult::Valid)return failure(decoded==TLinkC01DecodeResult::Expired?
        "1;;c01_request_expired\r\n":"1;;c01_ipc_envelope_invalid\r\n");
    if(!TLinkC01IsolatedPayload(envelope.payload,envelope.length))return failure("1;;c01_ipc_task_not_allowed\r\n");
    static_assert(kTLinkOwnedCaptureAction==4,"Private C01 capture action is contract v1");
    static std::atomic_bool active{false};
    TLinkC01IPCAdmission admission(active);
    if(!admission.admitted())return failure("1;;c01_ipc_busy\r\n");
    @autoreleasepool {
        try {
            @try {return handleIPCMessage(local,msgid,data,info);}
            @catch(NSException *exception){(void)exception;return failure("1;;request_failed\r\n");}
        } catch (...) {return failure("1;;request_failed\r\n");}
    }
}
static bool zx_installC01IPCSource(CFStringRef name,CFMessagePortRef *port,CFRunLoopSourceRef *source)
{
    *port=NULL;*source=NULL;
    CFMessagePortContext context={0,NULL,NULL,NULL,NULL};Boolean shouldFree=false;
    *port=CFMessagePortCreateLocal(kCFAllocatorDefault,name,handleC01IPCMessage,&context,&shouldFree);
    if(!*port)return false;
    *source=CFMessagePortCreateRunLoopSource(kCFAllocatorDefault,*port,0);
    if(!*source){CFMessagePortInvalidate(*port);CFRelease(*port);*port=NULL;return false;}
    CFRunLoopAddSource(CFRunLoopGetCurrent(),*source,kCFRunLoopCommonModes);
    return true;
}
// END C01 isolated IPC receiver.
static void startC01IPCServerOnBackgroundThread()
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSThread *thread=[[NSThread alloc] initWithBlock:^{
            @autoreleasepool {
                CFMessagePortRef port=NULL;CFRunLoopSourceRef source=NULL;
                if(!zx_installC01IPCSource(kTLinkautoC01IPCPortName,&port,&source)){
                    NSLog(@"### com.tlinkauto.springboard: C01 IPC source unavailable.");return;
                }
                CFRunLoopRun();
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopCommonModes);
                CFRelease(source);CFMessagePortInvalidate(port);CFRelease(port);
            }
        }];
        thread.name=@"com.tlinkauto.springboard.c01-ipc";
        [thread start];
    });
}

// BEGIN isolated VPN IPC receiver.
static CFDataRef handleVPNIPCMessage(CFMessagePortRef local,SInt32 msgid,CFDataRef data,void *info)
{
    auto failure=[](const char *line)->CFDataRef{return CFDataCreate(kCFAllocatorDefault,(const UInt8 *)line,strlen(line));};
    if(msgid!=TLinkVPNIPCMessage||!data)return failure("1;;vpn_ipc_envelope_required\r\n");
    TLinkVPNIPCEnvelope envelope;
    const auto decoded=TLinkVPNIPCDecode(CFDataGetBytePtr(data),size_t(CFDataGetLength(data)),envelope);
    if(decoded!=TLinkVPNIPCDecodeResult::Valid)return failure(decoded==TLinkVPNIPCDecodeResult::Expired?"1;;vpn_ipc_expired\r\n":"1;;vpn_ipc_invalid\r\n");
    static std::atomic_bool active{false};TLinkC01IPCAdmission admission(active);
    if(!admission.admitted())return failure("1;;vpn_ipc_busy\r\n");
    @autoreleasepool {try{@try{return handleIPCMessage(local,msgid,data,info);}
        @catch(NSException *exception){(void)exception;return failure("1;;request_failed\r\n");}}
        catch(...){return failure("1;;request_failed\r\n");}}
}
static bool zx_installVPNIPCSource(CFStringRef name,CFMessagePortRef *port,CFRunLoopSourceRef *source)
{
    *port=NULL;*source=NULL;CFMessagePortContext context={0,NULL,NULL,NULL,NULL};Boolean shouldFree=false;
    *port=CFMessagePortCreateLocal(kCFAllocatorDefault,name,handleVPNIPCMessage,&context,&shouldFree);
    if(!*port)return false;
    *source=CFMessagePortCreateRunLoopSource(kCFAllocatorDefault,*port,0);
    if(!*source){CFMessagePortInvalidate(*port);CFRelease(*port);*port=NULL;return false;}
    CFRunLoopAddSource(CFRunLoopGetCurrent(),*source,kCFRunLoopCommonModes);return true;
}
static void startVPNIPCServerOnBackgroundThread()
{
    static dispatch_once_t once;dispatch_once(&once, ^{
        NSThread *thread=[[NSThread alloc] initWithBlock:^{@autoreleasepool{
            CFStringRef name=CFStringCreateWithCString(kCFAllocatorDefault,TLinkVPNIPCPortName,kCFStringEncodingUTF8);
            CFMessagePortRef port=NULL;CFRunLoopSourceRef source=NULL;
            const bool installed=name&&zx_installVPNIPCSource(name,&port,&source);if(name)CFRelease(name);
            if(!installed){NSLog(@"### com.tlinkauto.springboard: VPN IPC source unavailable.");return;}
            CFRunLoopRun();CFRunLoopRemoveSource(CFRunLoopGetCurrent(),source,kCFRunLoopCommonModes);
            CFRelease(source);CFMessagePortInvalidate(port);CFRelease(port);
        }}];thread.name=@"com.tlinkauto.springboard.vpn-ipc";[thread start];
    });
}
// END isolated VPN IPC receiver.

void startIPCServerOnBackgroundThread()
{
    startC01IPCServerOnBackgroundThread();
    startVPNIPCServerOnBackgroundThread();
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
