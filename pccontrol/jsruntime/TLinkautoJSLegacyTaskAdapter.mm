#import "TLinkautoJSLegacyTaskAdapter.h"
#import "TLinkautoJSRuntimeExecution.h"
#import "../Task.h"
#import "../RuntimeUtils.h"
#include <dlfcn.h>

@implementation TLinkautoJSLegacyTaskAdapter {
    __weak TLinkautoJSRuntimeExecution *_execution;
}

- (instancetype)initWithExecution:(TLinkautoJSRuntimeExecution *)execution {
    self = [super init];
    if (self) {
        _execution = execution;
    }
    return self;
}

- (NSDictionary *)runTask:(int)task payload:(NSString *)payload {
    TLinkautoJSRuntimeExecution *exec = _execution;
    if (!exec) return @{@"ok": @NO, @"error": @"execution null"};

    if (task < 0 || task > 255) {
        return @{ @"ok": @NO, @"error": @"runTask task code out of range" };
    }

    NSString *taskStr = [NSString stringWithFormat:@"%d|%@", task, payload ?: @""];
    NSData *payloadData = [taskStr dataUsingEncoding:NSUTF8StringEncoding];

    if (payloadData.length > 512 * 1024) {
        return @{ @"ok": @NO, @"error": @"runTask payload exceeds maximum size" };
    }

    NSCondition *sleepCondition = exec.sleepCondition;
    __block NSString *responseString = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        CFReadStreamRef readStream;
        CFWriteStreamRef writeStream;
        CFStreamCreateBoundPair(NULL, &readStream, &writeStream, 1024 * 1024);

        if (!writeStream) {
            responseString = @"0;;internal error: failed to create stream\r\n";
            [sleepCondition lock];
            [sleepCondition signal];
            [sleepCondition unlock];
            if (readStream) CFRelease(readStream);
            return;
        }

        CFWriteStreamOpen(writeStream);

        void (*processTaskFn)(UInt8*, CFWriteStreamRef) = (void (*)(UInt8*, CFWriteStreamRef))dlsym(RTLD_DEFAULT, "processTask");
        if (processTaskFn) {
            processTaskFn((UInt8 *)[payloadData bytes], writeStream);
        } else {
            NSString *err = @"0;;internal error: processTask missing\r\n";
            CFWriteStreamWrite(writeStream, (const UInt8 *)[err UTF8String], [err length]);
        }

        CFWriteStreamClose(writeStream);

        CFDataRef written = (CFDataRef)CFWriteStreamCopyProperty(writeStream, kCFStreamPropertyDataWritten);
        CFRelease(writeStream);
        if (readStream) CFRelease(readStream);

        NSData *data = CFBridgingRelease(written);
        if (!data || [data length] == 0) {
            responseString = @"0\r\n";
        } else {
            responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }

        [sleepCondition lock];
        [sleepCondition signal];
        [sleepCondition unlock];
    });

    [sleepCondition lock];
    while (!responseString && ![exec isAborted]) {
        [sleepCondition wait];
    }
    [sleepCondition unlock];

    if ([exec isAborted]) {
        return @{ @"ok": @NO, @"error": @"aborted" };
    }

    if (!responseString) {
        return @{ @"ok": @NO, @"error": @"no response" };
    }

    NSArray *parts = [responseString componentsSeparatedByString:@";;"];
    if (parts.count == 0) return @{ @"ok": @NO, @"error": @"empty response" };

    int status = [parts[0] intValue];
    NSString *rawError = parts.count > 1 ? parts[1] : @"";
    NSString *errorMsg = [rawError stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (status == 1) {
        result[@"ok"] = @YES;
        NSMutableArray *resParts = [NSMutableArray arrayWithCapacity:parts.count - 1];
        for (NSUInteger i = 1; i < parts.count; i++) {
            [resParts addObject:[parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        }
        result[@"parts"] = resParts;
    } else {
        result[@"ok"] = @NO;
        result[@"error"] = errorMsg.length > 0 ? errorMsg : @"task failed";
    }
    return result;
}

@end
