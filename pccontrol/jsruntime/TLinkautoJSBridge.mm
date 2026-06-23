#import "TLinkautoJSBridge.h"
#import "TLinkautoJSRuntimeExecution.h"
#import "../Task.h"
#import "../RuntimeUtils.h"

@implementation TLinkautoJSBridge {
    __weak TLinkautoJSRuntimeExecution *_execution;
}

- (instancetype)initWithExecution:(TLinkautoJSRuntimeExecution *)execution {
    self = [super init];
    if (self) {
        _execution = execution;
    }
    return self;
}

- (void)injectIntoContext:(JSContext *)context {
    context[@"device"] = self;
}

- (NSDictionary *)runTask:(int)task payload:(NSString *)payload
{
    if (![JSContext currentContext]) return @{ @"ok": @NO, @"raw": @"1;;runtime_missing\r\n", @"parts": @[@"1", @"runtime_missing"] };
    if (task < 0 || task > 99) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"runTask task code out of range" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO, @"raw": @"1;;task_out_of_range\r\n", @"parts": @[@"1", @"task_out_of_range"] };
    }
    NSString *wire = [NSString stringWithFormat:@"%02d%@", task, TLinkautoJSSanitizePayload(payload) inContext:[JSContext currentContext]];
    return [[JSContext currentContext] taskResultForPayload:wire inContext:[JSContext currentContext]];
}

- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options
{
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"", 180);
    if ([safeMessage length] == 0) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"toast(message) requires a non-empty message" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    int type = TLinkautoJSIntOption(options, @"type", 3);
    int duration = TLinkautoJSIntOption(options, @"duration", 2);
    int position = TLinkautoJSIntOption(options, @"position", 0);
    int fontSize = TLinkautoJSIntOption(options, @"fontSize", 14);
    if (type < 0 || type > 4) type = 3;
    if (duration <= 0 && type != 0) duration = 2;
    NSString *payload = [NSString stringWithFormat:@"%d;;%@;;%d;;%d;;%d", type, safeMessage, duration, position, fontSize inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_SHOW_TOAST payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)tap:(double)x y:(double)y
{
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"tap(x, y) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f", x, y inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_NATIVE_TAP payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration
{
    if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) ||
        !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) ||
        !TLinkautoJSIsFiniteNumber(duration)) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"swipe(...) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_NATIVE_SWIPE payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration
{
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"longPress(x, y, duration) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%.2f;;%.2f;;%.0f", x, y, duration inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_NATIVE_TAP payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options
{
    NSString *encoded = TLinkautoJSEncodeGesturePoints(points);
    if (!encoded) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"gesture(points, options) requires 2-512 points as [x,y] arrays or {x,y} objects" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    int finger = TLinkautoJSIntOption(options, @"finger", 0);
    int duration = TLinkautoJSIntOption(options, @"duration", TLinkautoJSIntOption(options, @"durationMs", 300));
    if (duration < 0) duration = 0;
    if (duration > 60000) duration = 60000;
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%@", finger, duration, encoded inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_NATIVE_GESTURE payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)pickColor:(double)x y:(double)y
{
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"pickColor(x, y) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_COLOR_PICKER payload:[NSString stringWithFormat:@"%.0f;;%.0f", x, y] inContext:[JSContext currentContext]];
    NSArray *parts = result[@"parts" inContext:[JSContext currentContext]];
    if (![result[@"ok"] boolValue] || [parts count] < 4) {
        return result;
    }
    return TLinkautoJSResultByAdding(result, @{
        @"red": @([TLinkautoJSSafeStringPart(parts, 1) intValue]),
        @"green": @([TLinkautoJSSafeStringPart(parts, 2) intValue]),
        @"blue": @([TLinkautoJSSafeStringPart(parts, 3) intValue]),
    });
}

- (NSString *)defaultScreenshotPath
{
    NSString *dir = [[JSContext currentContext] currentBundlePath inContext:[JSContext currentContext]];
    if (!dir || [dir length] == 0) {
        dir = @"/tmp";
    }
    NSString *name = [NSString stringWithFormat:@"screenshot_%@.png", TLinkautoJSSanitizeFileComponent([JSContext currentContext].runId) inContext:[JSContext currentContext]];
    return [dir stringByAppendingPathComponent:name inContext:[JSContext currentContext]];
}

- (NSDictionary *)screenshot
{
    return [self screenshotTo:[self defaultScreenshotPath] inContext:[JSContext currentContext]];
}

- (NSDictionary *)screenshotTo:(NSString *)path
{
    NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : [self defaultScreenshotPath inContext:[JSContext currentContext]];
    if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"screenshot path contains unsupported protocol delimiter" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@", targetPath] inContext:[JSContext currentContext]];
    NSArray *parts = result[@"parts" inContext:[JSContext currentContext]];
    NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
    return TLinkautoJSResultByAdding(result, @{ @"path": resultPath ?: @"" });
}

- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options
{
    NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : [self defaultScreenshotPath inContext:[JSContext currentContext]];
    if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"screenshot path contains unsupported protocol delimiter" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }

    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"screenshotRegion(path, options) requires finite positive width/height" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }

    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_SCREENSHOT payload:[NSString stringWithFormat:@"1;;%@;;%.0f;;%.0f;;%.0f;;%.0f", targetPath, x, y, width, height] inContext:[JSContext currentContext]];
    NSArray *parts = result[@"parts" inContext:[JSContext currentContext]];
    NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
    return TLinkautoJSResultByAdding(result, @{
        @"path": resultPath ?: @"",
        @"x": @(x),
        @"y": @(y),
        @"width": @(width),
        @"height": @(height),
    });
}

- (NSDictionary *)frontMostAppId
{
    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_FRONTMOST_APP_ID payload:@"" inContext:[JSContext currentContext]];
    NSArray *parts = result[@"parts" inContext:[JSContext currentContext]];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"bundleId": TLinkautoJSSafeStringPart(parts, 1) });
}

- (NSDictionary *)orientation
{
    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_FRONTMOST_APP_ORIENTATION payload:@"" inContext:[JSContext currentContext]];
    NSArray *parts = result[@"parts" inContext:[JSContext currentContext]];
    if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
    return TLinkautoJSResultByAdding(result, @{ @"value": @([TLinkautoJSSafeStringPart(parts, 1) intValue]) });
}

- (NSDictionary *)batch:(NSArray *)commands
{
    if (![commands isKindOfClass:[NSArray class]]) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch(commands) requires an array" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    if ([commands count] > 256) {
        [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch(commands) accepts at most 256 commands" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }

    NSMutableArray<NSString *> *wireCommands = [NSMutableArray arrayWithCapacity:[commands count] inContext:[JSContext currentContext]];
    for (id item in commands) {
        if ([item isKindOfClass:[NSString class]]) {
            NSString *raw = (NSString *)item;
            if (TLinkautoJSStringContainsAny(raw, @[@"||", @"\r", @"\n"])) {
                [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"raw batch command contains unsupported protocol delimiter" inContext:[JSContext currentContext]];
                return @{ @"ok": @NO };
            }
            if ([raw hasPrefix:@"62"] || [raw hasPrefix:@"63"] || [raw hasPrefix:@"64"]) {
                [wireCommands addObject:raw inContext:[JSContext currentContext]];
            } else {
                [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"raw batch command must start with allowed native task 62/63/64" inContext:[JSContext currentContext]];
                return @{ @"ok": @NO };
            }
            continue;
        }
        if (![item isKindOfClass:[NSDictionary class]]) {
            [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch command must be an object or raw command string" inContext:[JSContext currentContext]];
            return @{ @"ok": @NO };
        }
        NSDictionary *cmd = (NSDictionary *)item;
        NSString *type = [[cmd[@"type"] description] lowercaseString inContext:[JSContext currentContext]];
        if ([type isEqualToString:@"tap"]) {
            double x = [cmd[@"x"] doubleValue inContext:[JSContext currentContext]];
            double y = [cmd[@"y"] doubleValue inContext:[JSContext currentContext]];
            double duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 50.0;
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
                [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch tap requires finite x/y/duration" inContext:[JSContext currentContext]];
                return @{ @"ok": @NO };
            }
            [wireCommands addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f", x, y, duration] inContext:[JSContext currentContext]];
        } else if ([type isEqualToString:@"swipe"]) {
            double x1 = [cmd[@"x1"] doubleValue inContext:[JSContext currentContext]];
            double y1 = [cmd[@"y1"] doubleValue inContext:[JSContext currentContext]];
            double x2 = [cmd[@"x2"] doubleValue inContext:[JSContext currentContext]];
            double y2 = [cmd[@"y2"] doubleValue inContext:[JSContext currentContext]];
            double duration = cmd[@"duration"] ? [cmd[@"duration"] doubleValue] : 300.0;
            if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) ||
                !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) {
                [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch swipe requires finite coordinates/duration" inContext:[JSContext currentContext]];
                return @{ @"ok": @NO };
            }
            [wireCommands addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f", x1, y1, x2, y2, duration] inContext:[JSContext currentContext]];
        } else if ([type isEqualToString:@"gesture"]) {
            NSArray *points = [cmd[@"points"] isKindOfClass:[NSArray class]] ? cmd[@"points"] : nil;
            NSString *encoded = TLinkautoJSEncodeGesturePoints(points);
            if (!encoded) {
                [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"batch gesture requires 2-512 valid points" inContext:[JSContext currentContext]];
                return @{ @"ok": @NO };
            }
            int finger = cmd[@"finger"] ? [cmd[@"finger"] intValue] : 0;
            int duration = cmd[@"duration"] ? [cmd[@"duration"] intValue] : (cmd[@"durationMs"] ? [cmd[@"durationMs"] intValue] : 300);
            if (duration < 0) duration = 0;
            if (duration > 60000) duration = 60000;
            [wireCommands addObject:[NSString stringWithFormat:@"64%d;;%d;;%@", finger, duration, encoded] inContext:[JSContext currentContext]];
        } else {
            [[JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:[NSString stringWithFormat:@"unsupported batch command type: %@", type ?: @""] inContext:[JSContext currentContext]];
            return @{ @"ok": @NO };
        }
    }

    NSString *payload = [wireCommands componentsJoinedByString:@"||" inContext:[JSContext currentContext]];
    return [_execution.taskDispatcher runTask:TASK_NATIVE_BATCH payload:payload inContext:[JSContext currentContext]];
}

- (NSDictionary *)captureFrame:(NSDictionary *)options
{
    BOOL needGray = TLinkautoJSIntOption(options, @"gray", 1) != 0;
    BOOL needBGRA = TLinkautoJSIntOption(options, @"bgra", 1) != 0;
    int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
    if (!needGray && !needBGRA) {
        needGray = YES;
        needBGRA = YES;
    }
    if (ttlMs <= 0) ttlMs = 1000;
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d", needGray ? 1 : 0, needBGRA ? 1 : 0, ttlMs inContext:[JSContext currentContext]];
    NSDictionary *result = [_execution.taskDispatcher runTask:TASK_FRAME_CAPTURE payload:payload inContext:[JSContext currentContext]];
}
@end
