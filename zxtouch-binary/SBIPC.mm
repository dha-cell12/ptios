#import "SBIPC.h"
#import "IPCConstants.h"

#import <CoreFoundation/CoreFoundation.h>

NSString *ZXSendSpringBoardTask(NSString *taskLine, NSTimeInterval timeoutSeconds)
{
    if (!taskLine || [taskLine length] == 0) {
        return nil;
    }

    if (access(kZXTouchIPCReadyMarkerPath, F_OK) != 0) {
        return nil;
    }

    CFMessagePortRef remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, kZXTouchIPCPortName);
    if (!remotePort) {
        return nil;
    }

    NSString *payload = [NSString stringWithFormat:@"%s%@", kZXTouchIPCCommandTaskPrefix, taskLine];
    NSData *payloadData = [payload dataUsingEncoding:NSUTF8StringEncoding];
    if (!payloadData) {
        CFRelease(remotePort);
        return nil;
    }

    CFDataRef responseData = NULL;
    CFDataRef requestData = CFDataCreate(kCFAllocatorDefault,
                                         (const UInt8 *)payloadData.bytes,
                                         (CFIndex)payloadData.length);
    if (!requestData) {
        CFRelease(remotePort);
        return nil;
    }

    const CFTimeInterval t = timeoutSeconds > 0 ? timeoutSeconds : 2.0;
    SInt32 result = CFMessagePortSendRequest(remotePort,
                                             1,
                                             requestData,
                                             t,
                                             t,
                                             kCFRunLoopDefaultMode,
                                             &responseData);

    CFRelease(requestData);
    CFRelease(remotePort);

    if (result != kCFMessagePortSuccess || !responseData) {
        if (responseData) {
            CFRelease(responseData);
        }
        return nil;
    }

    const UInt8 *bytes = CFDataGetBytePtr(responseData);
    CFIndex len = CFDataGetLength(responseData);
    NSString *responseString = nil;
    if (bytes && len > 0) {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)len];
        responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    CFRelease(responseData);
    return responseString;
}
