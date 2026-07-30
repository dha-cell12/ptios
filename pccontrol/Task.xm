#include "Task.h"
#import "TLinkDiagnostic.h"
#include "../shared/TLinkRootfullLicenseBuild.h"
#include "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkRootfullLicensePolicy.h"
#import <Foundation/Foundation.h>
#ifndef YES
#define YES true
#endif
#ifndef NO
#define NO false
#endif

#include <spawn.h>
#include <poll.h>
#include "Touch.h"
#include "Process.h"
#include "AlertBox.h"
#include "Record.h"
#include "Play.h"
#include "SocketServer.h"
#include "ScreenMatch.h"
#include "Toast.h"
#include "ColorPicker.h"
#include "Image.h"
#include "Connectivity.h"
#include "UIKeyboard.h"
#include "DeviceInfo.h"
#include "TouchIndicator/TouchIndicatorWindow.h"
#include "HardwareKey.h"
#include "Scheduler.h"
#include "RuntimeUtils.h"
#import "ScriptPlayer.h"
#import <mach/mach.h>
#include <Foundation/NSDistributedNotificationCenter.h>
#include <TextRecognization/TextRecognizer.h>
#include "UpdateCache.h"
#include "TesseractOCRTask.h"
#include "Screen.h"
#include "H264Stream.h"
#include "NSTask.h"
#include <signal.h>
#include <os/lock.h>
#include <atomic>

extern CFRunLoopRef recordRunLoop;
extern ScriptPlayer *scriptPlayer;
static std::atomic<uint64_t> sTLinkSpringBoardLicenseTask10DropCount(0);

/*
get task type
*/
static int getTaskType(UInt8* dataArray)
{
    return (dataArray[0] - '0') * 10 + (dataArray[1] - '0');
}

static int zx_clampTouchCoord(CGFloat value)
{
    if (value < 0) value = 0;
    int fixed = (int)(value * 10.0f + 0.5f);
    if (fixed > 99999) fixed = 99999;
    return fixed;
}

static NSString *zx_touchPayload(int type, int finger, CGFloat x, CGFloat y)
{
    if (finger < 0) finger = 0;
    if (finger > 99) finger = 99;
    return [NSString stringWithFormat:@"1%d%02d%05d%05d", type, finger, zx_clampTouchCoord(x), zx_clampTouchCoord(y)];
}

static void zx_performSingleTouch(int type, int finger, CGFloat x, CGFloat y)
{
    NSString *payload = zx_touchPayload(type, finger, x, y);
    performTouchFromRawData((UInt8 *)[payload UTF8String]);
}

static NSArray<NSString *> *zx_splitTaskParts(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_handleNativeTap(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native tap format: x;;y[;;duration_ms;;finger]\r\n"}];
        return false;
    }
    CGFloat x = [parts[0] floatValue];
    CGFloat y = [parts[1] floatValue];
    int durationMs = parts.count >= 3 ? [parts[2] intValue] : 50;
    int finger = parts.count >= 4 ? [parts[3] intValue] : 0;
    if (durationMs < 0) durationMs = 0;
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);
    if (durationMs > 0) usleep((useconds_t)durationMs * 1000);
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeSwipe(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 5) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native swipe format: x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]\r\n"}];
        return false;
    }
    CGFloat x1 = [parts[0] floatValue];
    CGFloat y1 = [parts[1] floatValue];
    CGFloat x2 = [parts[2] floatValue];
    CGFloat y2 = [parts[3] floatValue];
    int durationMs = [parts[4] intValue];
    int finger = parts.count >= 6 ? [parts[5] intValue] : 0;
    int steps = parts.count >= 7 ? [parts[6] intValue] : durationMs / 16;
    if (durationMs < 0) durationMs = 0;
    if (steps < 2) steps = 2;
    if (steps > 120) steps = 120;

    zx_performSingleTouch(TOUCH_DOWN, finger, x1, y1);
    int sleepPerStep = steps > 0 ? durationMs * 1000 / steps : 0;
    for (int i = 1; i < steps; i++) {
        if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
        CGFloat t = (CGFloat)i / (CGFloat)steps;
        zx_performSingleTouch(TOUCH_MOVE, finger, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
    }
    if (sleepPerStep > 0) usleep((useconds_t)sleepPerStep);
    zx_performSingleTouch(TOUCH_UP, finger, x2, y2);
    return true;
}

static bool zx_parseGesturePoint(NSString *text, CGFloat *x, CGFloat *y)
{
    NSArray<NSString *> *xy = [text componentsSeparatedByString:@","];
    if (xy.count != 2) return false;
    if (x) *x = [xy[0] floatValue];
    if (y) *y = [xy[1] floatValue];
    return true;
}

static bool zx_handleNativeGesture(UInt8 *eventData, NSError **err)
{
    NSArray<NSString *> *parts = zx_splitTaskParts(eventData);
    if (parts.count < 3) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture format: finger;;duration_ms;;x,y|x,y|...\r\n"}];
        return false;
    }
    int finger = [parts[0] intValue];
    int durationMs = [parts[1] intValue];
    NSArray<NSString *> *pointTexts = [parts[2] componentsSeparatedByString:@"|"];
    if (pointTexts.count < 2) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native gesture requires at least two points.\r\n"}];
        return false;
    }
    if (durationMs < 0) durationMs = 0;

    CGFloat x = 0, y = 0;
    if (!zx_parseGesturePoint(pointTexts[0], &x, &y)) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid first gesture point.\r\n"}];
        return false;
    }
    zx_performSingleTouch(TOUCH_DOWN, finger, x, y);

    int intervals = (int)pointTexts.count - 1;
    int sleepPerInterval = intervals > 0 ? durationMs * 1000 / intervals : 0;
    for (NSUInteger i = 1; i < pointTexts.count; i++) {
        if (!zx_parseGesturePoint(pointTexts[i], &x, &y)) {
            zx_performSingleTouch(TOUCH_UP, finger, x, y);
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid gesture point.\r\n"}];
            return false;
        }
        zx_performSingleTouch(TOUCH_MOVE, finger, x, y);
        if (sleepPerInterval > 0) usleep((useconds_t)sleepPerInterval);
    }
    zx_performSingleTouch(TOUCH_UP, finger, x, y);
    return true;
}

static bool zx_handleNativeBatch(UInt8 *eventData, NSError **err)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw || raw.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n"}];
        return false;
    }

    NSArray<NSString *> *commands = [raw componentsSeparatedByString:@"||"];
    for (NSString *cmd in commands) {
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        UInt8 *payloadBytes = (UInt8 *)[payload UTF8String];
        if (task == TASK_PERFORM_TOUCH) {
            performTouchFromRawData(payloadBytes);
        } else if (task == TASK_NATIVE_TAP) {
            if (!zx_handleNativeTap(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_SWIPE) {
            if (!zx_handleNativeSwipe(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_GESTURE) {
            if (!zx_handleNativeGesture(payloadBytes, err)) return false;
        } else {
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported batch task: %d\r\n", task]}];
            return false;
        }
    }
    return true;
}

// === runShell drain/timeout support (Group A) ===

static const NSUInteger kShellMaxCapturedOutputBytes = 768 * 1024;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;
static const NSUInteger kShellReadChunkBytes = 16 * 1024;
static const double kShellDefaultTimeout = 30.0;
static const double kShellMinTimeout = 1.0;
static const double kShellMaxTimeout = 300.0;
static const double kShellTerminateGrace = 1.5;

@interface TLinkShellDrainContext : NSObject {
@private
    os_unfair_lock _lock;
    BOOL _forceCloseReaders;
}
@property (nonatomic, strong) NSMutableData *outData;
@property (nonatomic, strong) NSMutableData *errData;
@property (nonatomic, assign) NSUInteger capturedBytes;
@property (nonatomic, assign) BOOL outTruncated;
@property (nonatomic, assign) BOOL errTruncated;
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr;
- (void)requestForceCloseReaders;
- (BOOL)shouldForceCloseReaders;
@end

@implementation TLinkShellDrainContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _forceCloseReaders = false;
        _outData = [NSMutableData data];
        _errData = [NSMutableData data];
    }
    return self;
}
- (void)requestForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    _forceCloseReaders = true;
    os_unfair_lock_unlock(&_lock);
}
- (BOOL)shouldForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    BOOL value = _forceCloseReaders;
    os_unfair_lock_unlock(&_lock);
    return value;
}
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr {
    if (!chunk || chunk.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger remaining = (self.capturedBytes >= kShellMaxCapturedOutputBytes) ? 0 : (kShellMaxCapturedOutputBytes - self.capturedBytes);
    NSUInteger accepted = MIN(remaining, chunk.length);
    if (accepted > 0) {
        self.capturedBytes += accepted;
        if (isStderr) {
            [self.errData appendBytes:chunk.bytes length:accepted];
        } else {
            [self.outData appendBytes:chunk.bytes length:accepted];
        }
    }
    if (accepted < chunk.length) {
        if (isStderr) self.errTruncated = true;
        else self.outTruncated = true;
    }
    os_unfair_lock_unlock(&_lock);
}
@end

@interface TLinkShellResult : NSObject
@property (nonatomic, assign) int exitCode;
@property (nonatomic, assign) int terminationSignal;
@property (nonatomic, assign) BOOL timedOut;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL drainForcedClosed;
@property (nonatomic, strong) NSString *stdoutStr;
@property (nonatomic, strong) NSString *stderrStr;
@property (nonatomic, assign) BOOL stdoutTruncated;
@property (nonatomic, assign) BOOL stderrTruncated;
@end

@implementation TLinkShellResult
@end

static TLinkShellResult *RunShellCore(NSString *command, TLinkTaskExecutionContext *context, double timeoutSeconds, NSUInteger maxOutputBytes) {
    TLinkShellResult *result = [[TLinkShellResult alloc] init];
    result.exitCode = -1;
    result.stdoutStr = @"";
    result.stderrStr = @"";

    double actualTimeout = timeoutSeconds;
    if (actualTimeout <= 0) actualTimeout = (context && context.defaultTimeoutSeconds > 0) ? context.defaultTimeoutSeconds : kShellDefaultTimeout;
    if (actualTimeout < kShellMinTimeout) actualTimeout = kShellMinTimeout;
    if (actualTimeout > kShellMaxTimeout) actualTimeout = kShellMaxTimeout;

    int outPipe[2] = {-1, -1};
    int errPipe[2] = {-1, -1};
    
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        result.stderrStr = @"Failed to create pipes";
        return result;
    }
    
    fcntl(outPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(outPipe[1], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[1], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);

    pid_t pid = -1;
    const char *cmdArgs[] = {"/usr/bin/sudo", "/usr/bin/tlinkautob", "-e", [command UTF8String], NULL};
    int spawnErr = posix_spawn(&pid, "/usr/bin/sudo", &actions, &attr, (char *const *)cmdArgs, NULL);

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);

    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnErr != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        result.stderrStr = [NSString stringWithFormat:@"posix_spawn failed: %d", spawnErr];
        return result;
    }

    TLinkShellDrainContext *drainCtx = [[TLinkShellDrainContext alloc] init];

    dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t drainGroup = dispatch_group_create();

    void (^drainBlock)(int, BOOL) = ^(int fd, BOOL isStderr) {
        fcntl(fd, F_SETFL, O_NONBLOCK);
        while (![drainCtx shouldForceCloseReaders]) {
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 100);
            if (ret > 0) {
                if (pfd.revents & POLLIN) {
                    uint8_t buf[kShellReadChunkBytes];
                    ssize_t bytesRead = read(fd, buf, sizeof(buf));
                    if (bytesRead > 0) {
                        NSData *chunk = [NSData dataWithBytes:buf length:bytesRead];
                        [drainCtx appendChunk:chunk toStderr:isStderr];
                    } else if (bytesRead == 0) {
                        break;
                    }
                } else if (pfd.revents & (POLLHUP | POLLERR)) {
                    break;
                }
            } else if (ret < 0 && errno != EINTR) {
                break;
            }
        }
        close(fd);
    };

    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, false); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, true); });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:actualTimeout];
    BOOL timedOut = false;
    BOOL cancelled = false;

    while (true) {
        int status;
        pid_t wpid = waitpid(pid, &status, WNOHANG);
        if (wpid == pid) {
            if (WIFEXITED(status)) {
                result.exitCode = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                result.exitCode = -1;
                result.terminationSignal = WTERMSIG(status);
            }
            break;
        }

        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            timedOut = true;
            break;
        }
        if (context && context.cancellationToken && [context.cancellationToken isCancelled]) {
            cancelled = true;
            break;
        }
        usleep(20 * 1000);
    }

    if (timedOut || cancelled) {
        result.timedOut = timedOut;
        result.cancelled = cancelled;
        kill(-pid, SIGTERM);
        
        NSDate *graceDeadline = [NSDate dateWithTimeIntervalSinceNow:kShellTerminateGrace];
        while (true) {
            int status;
            pid_t wpid = waitpid(pid, &status, WNOHANG);
            if (wpid == pid) {
                if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
                else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
                break;
            }
            if ([[NSDate date] compare:graceDeadline] != NSOrderedAscending) {
                kill(-pid, SIGKILL);
                break;
            }
            usleep(20 * 1000);
        }
        
        if (result.exitCode == -1 && result.terminationSignal == 0) {
            int status;
            waitpid(pid, &status, 0);
            if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
        }

        NSDate *drainDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (dispatch_group_wait(drainGroup, DISPATCH_TIME_NOW) != 0) {
            if ([[NSDate date] compare:drainDeadline] != NSOrderedAscending) {
                [drainCtx requestForceCloseReaders];
                result.drainForcedClosed = true;
                break;
            }
            usleep(20 * 1000);
        }
    }

    dispatch_group_wait(drainGroup, DISPATCH_TIME_FOREVER);

    NSString *outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSUTF8StringEncoding];
    if (!outStr && drainCtx.outData.length > 0) outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSASCIIStringEncoding];
    
    NSString *errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSUTF8StringEncoding];
    if (!errStr && drainCtx.errData.length > 0) errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSASCIIStringEncoding];

    result.stdoutStr = outStr ?: @"";
    result.stderrStr = errStr ?: @"";
    result.stdoutTruncated = drainCtx.outTruncated;
    result.stderrTruncated = drainCtx.errTruncated;

    return result;
}

void processTaskLegacy(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    processTaskWithContext(buff, SIZE_MAX, writeStreamRef, nil);
}

void processTask(UInt8 *buff, CFWriteStreamRef writeStreamRef)
{
    processTaskLegacy(buff, writeStreamRef);
}

/**
Process Task
*/
void processTaskWithContext(UInt8 *buff, size_t actualLength, CFWriteStreamRef writeStreamRef, TLinkTaskExecutionContext *context)
{
    if (!buff) return;
    
    //NSLog(@"### com.tlinkauto.springboard: task type: %d. Data: %s", getTaskType(buff), buff);
    UInt8 *eventData = buff + 0x2;
    int taskType = getTaskType(buff);

    NSString *licenseDenial = nil;
    if (!TLinkRootfullLicenseTaskAllowed(taskType, &licenseDenial)) {
        if (taskType == TASK_PERFORM_TOUCH) {
            sTLinkSpringBoardLicenseTask10DropCount.fetch_add(1, std::memory_order_relaxed);
            return;
        }
        notifyClient((UInt8 *)[(licenseDenial ?: @"-1;;license_required\r\n") UTF8String],
                     writeStreamRef);
        return;
    }

    //for touching
    if (taskType == TASK_PERFORM_TOUCH)
    {
        @autoreleasepool{
            performTouchFromRawData(eventData);
        }
    }
    else if (taskType == TASK_PERFORM_TOUCH_ACK)
    {
        @autoreleasepool{
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            char *sep = strstr((char *)eventData, ";;");
            if (!sep) {
                notifyClient((UInt8*)"1;;touch_ack_bad_payload\r\n", writeStreamRef);
                return;
            }

            *sep = '\0';
            char *seq = (char *)eventData;
            UInt8 *touchData = (UInt8 *)(sep + 2);
            performTouchFromRawData(touchData);
            int dispatchUs = (int)((CFAbsoluteTimeGetCurrent() - start) * 1000000.0);
            NSString *response = [NSString stringWithFormat:@"0;;%s;;%d\r\n", seq, dispatchUs];
            notifyClient((UInt8*)[response UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_TAP)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeTap(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_SWIPE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeSwipe(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_GESTURE)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeGesture(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_NATIVE_BATCH)
    {
        @autoreleasepool{
            NSError *err = nil;
            zx_handleNativeBatch(eventData, &err);
            if (err) notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            else notifyClient((UInt8*)"0\r\n", writeStreamRef);
        }
    }
    else if (taskType == TASK_PROCESS_BRING_FOREGROUND) //bring to foreground
    {
        @autoreleasepool{   
            switchProcessForegroundFromRawData(eventData);
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_SHOW_ALERT_BOX)
    {
        @autoreleasepool{   
            NSError *err = nil;
            showAlertBoxFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_USLEEP)
    {
        if (writeStreamRef)
        {
            int usleepTime = 0;
            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
            notifyClient((UInt8*)"0;;Sleep ends\r\n", writeStreamRef); 
        }
        else
        {
            int usleepTime = 0;

            @try{
                usleepTime = atoi((char*)eventData);
            }
            @catch (NSException *exception) {
                NSLog(@"com.tlinkauto.springboard: Debug: %@", exception.reason);
                return;
            }
            //NSLog(@"com.tlinkauto.springboard: sleep %d microseconds", usleepTime);
            usleep(usleepTime);
        }

    }
    else if (taskType == TASK_RUN_SHELL)
    {
        @autoreleasepool{
            NSString *rawPayload = [NSString stringWithUTF8String:(const char *)eventData] ?: @"";
            double timeout = kShellDefaultTimeout;
            NSString *command = rawPayload;
            NSRange sepRange = [rawPayload rangeOfString:@";;"];
            if (sepRange.location != NSNotFound) {
                NSString *maybeTimeout = [rawPayload substringToIndex:sepRange.location];
                NSScanner *scanner = [NSScanner scannerWithString:maybeTimeout];
                double parsed = 0;
                if ([scanner scanDouble:&parsed] && [scanner isAtEnd] && parsed > 0) {
                    timeout = parsed;
                    command = [rawPayload substringFromIndex:sepRange.location + 2];
                }
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, SIZE_MAX);
            
            NSString *combined = result.stderrStr.length > 0 ? [result.stdoutStr stringByAppendingString:result.stderrStr] : result.stdoutStr;
            NSString *safeOutput = [[combined stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
            if (result.stdoutTruncated || result.stderrTruncated) {
                safeOutput = [safeOutput stringByAppendingFormat:@"\\n[output truncated: exceeded %lu bytes]", (unsigned long)kShellMaxCapturedOutputBytes];
            }
            
            if (result.timedOut) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command timed out after %.0fs: %@\r\n", timeout, safeOutput] UTF8String], writeStreamRef);
            } else if (result.cancelled) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command cancelled: %@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else if (result.exitCode == 0) {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", safeOutput] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"-1;;Shell command failed (%d): %@\r\n", result.exitCode, safeOutput] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_RUN_SHELL_V2)
    {
        @autoreleasepool{
            NSError *jsonErr = nil;
            NSData *payloadData = [NSData dataWithBytes:eventData length:actualLength - 2];
            NSDictionary *req = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&jsonErr];
            
            NSString *command = @"";
            double timeout = kShellDefaultTimeout;
            NSUInteger maxOutput = kTLinkautoJSMaxResponseBytes;
            
            if (!jsonErr && [req isKindOfClass:[NSDictionary class]]) {
                command = req[@"command"] ?: @"";
                if (req[@"timeoutSeconds"]) timeout = [req[@"timeoutSeconds"] doubleValue];
                if (req[@"maxOutputBytes"]) maxOutput = [req[@"maxOutputBytes"] unsignedIntegerValue];
            }
            
            TLinkShellResult *result = RunShellCore(command, context, timeout, maxOutput);
            
            NSMutableDictionary *resp = [NSMutableDictionary dictionary];
            resp[@"exitCode"] = result.exitCode == -1 ? [NSNull null] : @(result.exitCode);
            resp[@"terminationSignal"] = @(result.terminationSignal);
            resp[@"timedOut"] = @(result.timedOut);
            resp[@"cancelled"] = @(result.cancelled);
            resp[@"drainForcedClosed"] = @(result.drainForcedClosed);
            resp[@"stdout"] = result.stdoutStr;
            resp[@"stderr"] = result.stderrStr;
            resp[@"stdoutTruncated"] = @(result.stdoutTruncated);
            resp[@"stderrTruncated"] = @(result.stderrTruncated);
            
            NSData *respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            if (respData.length > kTLinkautoJSMaxResponseBytes) {
                resp[@"stdout"] = @"[Truncated due to JSON size limit]";
                resp[@"stderr"] = @"[Truncated due to JSON size limit]";
                resp[@"stdoutTruncated"] = @(true);
                resp[@"stderrTruncated"] = @(true);
                respData = [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
            }
            
            NSString *respJson = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", respJson] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_START)
    {
        @autoreleasepool {
            NSError *err = nil;
            startRecording(writeStreamRef, &err);    
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_RECORDING_STOP)
    {
        @autoreleasepool {
            stopRecording(); 
            notifyClient((UInt8*)"0\r\n", writeStreamRef); 
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            playScript((UInt8*)eventData, &err);
            if (err)
            {
                setLastScriptError([err localizedDescription]);
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_PLAY_SCRIPT_FORCE_STOP)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptPlaying(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEMPLATE_MATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            CGRect result = screenMatchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%.2f;;%.2f;;%.2f;;%.2f\r\n", 
                result.origin.x, result.origin.y, result.size.width, result.size.height] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SHOW_TOAST)
    {
        @autoreleasepool {
            NSError *err = nil;
            showToastFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_PICKER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSDictionary *rgb = getRGBFromRawData(eventData, &err); 
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n", [rgb[@"red"] intValue], [rgb[@"green"] intValue], [rgb[@"blue"] intValue]] UTF8String], writeStreamRef);
            }
            rgb = nil;
        }
    }
    else if (taskType == TASK_TEXT_INPUT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = inputTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_GET_DEVICE_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *deviceInfo = getDeviceInfoFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", deviceInfo] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TOUCH_INDICATOR)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleTouchIndicatorTaskWithRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEXT_RECOGNIZER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *text = performTextRecognizerTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", text] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_SEARCHER)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *returndata = searchRGBFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", returndata] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HARDWARE_KEY)
    {
        @autoreleasepool {
            NSError *err = nil;
            sendHardwareKeyEventFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_KILL)
    {
        @autoreleasepool {
            NSError *err = nil;
            killAppFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_STATE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = appStateFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_INFO)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *info = appInfoFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", info] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ID)
    {
        @autoreleasepool {
            NSString *frontApp = frontMostAppId();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", frontApp] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_FRONTMOST_APP_ORIENTATION)
    {
        @autoreleasepool {
            NSString *orientation = frontMostAppOrientation();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", orientation] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SET_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            setAutoLaunchFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_AUTO_LAUNCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *list = listAutoLaunch(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", list ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_SET_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            setTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_REMOVE_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            removeTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_KEEP_AWAKE)
    {
        @autoreleasepool {
            NSError *err = nil;
            keepAwakeFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = appPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRONTMOST_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = frontMostPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_APP_PATHS)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *paths = appPathsFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", paths ?: @";;"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_LIST_BUNDLES)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = listBundlesFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OPEN_URL)
    {
        @autoreleasepool {
            NSError *err = nil;
            (void)openUrlFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_WIFI)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = wifiTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_BLUETOOTH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = bluetoothTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_AIRPLANE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = airplaneTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CELLULAR_DATA)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = cellularDataTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_VPN)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = vpnTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_HELLO_STATUS)
    {
        @autoreleasepool {
            UIDevice *dev = [UIDevice currentDevice];
            NSString *name = dev.name ?: @"";
            NSString *systemName = dev.systemName ?: @"iOS";
            NSString *systemVersion = dev.systemVersion ?: @"";
            NSString *model = dev.model ?: @"";

            BOOL playing = false;
            NSString *bundlePath = @"";
            if (scriptPlayer) {
                playing = [scriptPlayer isPlaying];
                bundlePath = [scriptPlayer getCurrentBundlePath] ?: @"";
            }
            NSString *licenseBuildMode =
                [NSString stringWithUTF8String:TLinkRootfullLicenseBuildMode()] ?: @"";
            NSMutableDictionary *licenseStatus =
                [TLinkLicenseStatusDictionary() mutableCopy];
            licenseStatus[@"phase"] = @6;
            licenseStatus[@"runtime"] = @"rootfull";
            licenseStatus[@"runtime_gate_active"] = @1;
            licenseStatus[@"activation_lifecycle_active"] = @1;
            licenseStatus[@"enforcement_scope"] = @"task_and_long_running_component_gate";
            licenseStatus[@"task_policy"] = @"rootfull_explicit_v1";
            licenseStatus[@"h264_gate_active"] = @1;
            licenseStatus[@"h264_heartbeat_interval_ms"] = @5000;
            licenseStatus[@"h264_client_active"] = @(TLinkH264LicenseHeartbeatActive());
            licenseStatus[@"h264_denied_accept_count"] =
                @(TLinkH264LicenseDeniedAcceptCount());
            licenseStatus[@"h264_revoked_client_count"] =
                @(TLinkH264LicenseRevokedClientCount());
            licenseStatus[@"script_heartbeat_active"] = @1;
            licenseStatus[@"scheduler_launch_gate_active"] = @1;
            licenseStatus[@"helper_runtime_gate_active"] = @1;
            licenseStatus[@"ui_feature_snapshot_active"] = @1;
            licenseStatus[@"release_integrity_active"] = @1;
            licenseStatus[@"anti_rollback_active"] = @1;
            licenseStatus[@"verifier_performance"] = TLinkLicensePerformanceDictionary();
            licenseStatus[@"task10_license_drop_count"] =
                @(sTLinkSpringBoardLicenseTask10DropCount.load(std::memory_order_relaxed));
            licenseStatus[@"rootfull_build_mode"] = licenseBuildMode;
            licenseStatus[@"verifier_build_mode"] = TLinkLicenseBuildMode() ?: @"";

            NSDictionary *payload = @{
                @"tlinkauto": @{
                    @"protocols": @[@"v0", @"v1"],
                    @"port": @6000,
                    @"license_contract_version": @1,
                },
                @"device": @{
                    @"name": name,
                    @"system_name": systemName,
                    @"system_version": systemVersion,
                    @"model": model,
                },
                @"script": @{
                    @"is_playing": @(playing),
                    @"bundle_path": bundlePath,
                    @"last_error": getLastScriptError() ?: @"",
                    @"last_error_ts": @(getLastScriptErrorTs()),
                    @"license_runtime": scriptPlayer
                        ? [scriptPlayer licenseRuntimeDiagnostics]
                        : @{},
                    @"scheduler_license": TLinkSchedulerLicenseDiagnostics(),
                },
                @"vpn": @{
                    @"vpn_contract_version": @1,
                    @"legacy_task": @59,
                    @"state": @"unavailable",
                    @"query": @"unsupported",
                    @"control": @"unsupported",
                    @"backend": @"stub",
                    @"broker": @"not_implemented",
                    @"profile_scope": @"tlink_owned_only",
                    @"configuration_transport": @"local_ui_keychain_only",
                    @"credentials_over_task59": @(NO),
                },
                @"license": licenseStatus,
            };

            NSError *jsonErr = nil;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonErr];
            if (!jsonData || jsonErr) {
                notifyClient((UInt8*)"1;;Failed to encode hello status.\r\n", writeStreamRef);
                return;
            }
            NSString *b64 = [jsonData base64EncodedStringWithOptions:0];
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", b64 ?: @""] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREEN_KEEP)
    {
        @autoreleasepool {
            NSError *err = nil;
            handleScreenKeepTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_IMAGE_OBJECT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleImageObjectTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (ret && [ret length] > 0)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_CAPTURE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameCaptureTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_RELEASE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameReleaseTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0;;0;;0;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_COLOR_IN_FRAME)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleColorInFrameTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FRAME_BATCH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFrameBatchTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_OCR_TESSERACT_REGION)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleTesseractOCRTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_FIND_IMAGE)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleFindImageTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @"-1;;-1;;0;;0;;-1;;-1;;0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_STOP_SCRIPT)
    {
        @autoreleasepool {
            NSError *err = nil;
            stopScriptFromRawData(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *response = dialogFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", response ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_CLEAR_DIALOG)
    {
        @autoreleasepool {
            NSError *err = nil;
            clearDialogValues(&err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_ROOT_DIR)
    {
        @autoreleasepool {
            NSString *path = rootDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_CURRENT_DIR)
    {
        @autoreleasepool {
            NSString *path = currentDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_BOT_PATH)
    {
        @autoreleasepool {
            NSString *path = botPathValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_SCREENSHOT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *resultPath = handleScreenshotTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (resultPath)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", resultPath] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_UPDATE_CACHE)
    {
        @autoreleasepool{
            NSError *err = nil;
            updateCacheFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[@"0\r\n" UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_TEST)
    {

    }
}
