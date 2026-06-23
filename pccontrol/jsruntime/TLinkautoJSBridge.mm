#import "TLinkautoJSBridge.h"
#import "TLinkautoJSRuntimeExecution.h"
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

- (NSDictionary *)tap:(double)x y:(double)y {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"tap(x, y) requires finite numbers" ];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"tap" payload:@{@"x": @(x), @"y": @(y)}];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration {
    if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) || !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"swipe(...) requires finite numbers" ];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"swipe" payload:@{@"x1": @(x1), @"y1": @(y1), @"x2": @(x2), @"y2": @(y2), @"duration": @(duration)}];
}

- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"longPress(x, y, duration) requires finite numbers" ];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"longPress" payload:@{@"x": @(x), @"y": @(y), @"duration": @(duration)}];
}

- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options {
    if (![points isKindOfClass:[NSArray class]] || points.count < 2 || points.count > 512) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"gesture(points, options) requires 2-512 points as [x,y] arrays or {x,y} objects" ];
        return @{ @"ok": @NO };
    }
    NSMutableString *payload = [NSMutableString string];
    double duration = TLinkautoJSIntOption(options, @"duration", 200);
    [payload appendFormat:@"%.0f;;%.1f;;", duration, duration];

    for (NSUInteger i = 0; i < points.count; i++) {
        id pt = points[i];
        double px = 0, py = 0;
        if ([pt isKindOfClass:[NSArray class]] && [pt count] >= 2) {
            px = [pt[0] doubleValue]; py = [pt[1] doubleValue];
        } else if ([pt isKindOfClass:[NSDictionary class]]) {
            px = [pt[@"x"] doubleValue]; py = [pt[@"y"] doubleValue];
        } else {
            return @{ @"ok": @NO, @"error": @"invalid gesture point format" };
        }
        [payload appendFormat:@"%.1f;;%.1f%@", px, py, (i == points.count - 1) ? @"" : @";;"];
    }
    return [_execution.taskDispatcher dispatchTask:@"gesture" payload:@{@"stringPayload": payload}];
}

- (NSDictionary *)getScreenSize {
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"getScreenSize" payload:@{}];
    if (![result[@"ok"] boolValue]) return result;

    NSArray *parts = result[@"parts"];
    int w = [TLinkautoJSSafeStringPart(parts, 0) intValue];
    int h = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    int scale = [TLinkautoJSSafeStringPart(parts, 2) intValue];
    int orient = [TLinkautoJSSafeStringPart(parts, 3) intValue];
    if (scale <= 0) scale = 1;

    NSString *orientStr = @"portrait";
    if (orient == 3) orientStr = @"landscapeRight";
    else if (orient == 4) orientStr = @"landscapeLeft";
    else if (orient == 2) orientStr = @"portraitUpsideDown";

    return @{@"ok": @YES, @"width": @(w), @"height": @(h), @"scale": @(scale), @"orientation": orientStr, @"coordinateSpace": @"native-pixels"};
}

- (NSDictionary *)pickColor:(double)x y:(double)y {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"pickColor(x, y) requires finite numbers" ];
        return @{ @"ok": @NO };
    }
    NSDictionary *res = [_execution.taskDispatcher dispatchTask:@"pickColor" payload:@{@"x": @(x), @"y": @(y)}];
    if (![res[@"ok"] boolValue]) return res;
    NSArray *parts = res[@"parts"];
    return @{@"ok": @YES, @"red": @([TLinkautoJSSafeStringPart(parts, 0) intValue]), @"green": @([TLinkautoJSSafeStringPart(parts, 1) intValue]), @"blue": @([TLinkautoJSSafeStringPart(parts, 2) intValue])};
}

- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options {
    NSString *safeMessage = TLinkautoJSSanitizeProtocolText(message ?: @"", 180);
    if ([safeMessage length] == 0) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"toast(message) requires a non-empty message" ];
        return @{ @"ok": @NO };
    }
    int type = TLinkautoJSIntOption(options, @"type", 3);
    int duration = TLinkautoJSIntOption(options, @"duration", 2);
    int position = TLinkautoJSIntOption(options, @"position", 0);
    int fontSize = TLinkautoJSIntOption(options, @"fontSize", 14);
    if (type < 0 || type > 4) type = 3;
    if (duration <= 0 && type != 0) duration = 2;
    NSString *payload = [NSString stringWithFormat:@"%d;;%@;;%d;;%d;;%d", type, safeMessage, duration, position, fontSize];
    return [_execution.taskDispatcher dispatchTask:@"toast" payload:@{@"stringPayload": payload}];
}

- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options {
    NSString *safePath = TLinkautoJSSanitizeProtocolText(path ?: @"", 256);
    int maxTry = TLinkautoJSIntOption(options, @"maxTryTimes", 1);
    double acceptable = TLinkautoJSDoubleOption(options, @"acceptable", 0.95);
    int skip = TLinkautoJSIntOption(options, @"pixelSkip", 0);
    double scaleMin = TLinkautoJSDoubleOption(options, @"scaleMin", 1.0);
    double scaleMax = TLinkautoJSDoubleOption(options, @"scaleMax", 1.0);
    double scaleStep = TLinkautoJSDoubleOption(options, @"scaleStep", 1.0);
    NSString *payload = [NSString stringWithFormat:@"%d;;%f;;%d;;%f;;%f;;%f;;%@;;;;;", maxTry, acceptable, skip, scaleMin, scaleMax, scaleStep, safePath];
    return [_execution.taskDispatcher dispatchTask:@"matchTemplate" payload:@{@"stringPayload": payload}];
}

- (NSDictionary *)findColor:(NSDictionary *)options {
    int x = TLinkautoJSIntOption(options, @"x", 0);
    int y = TLinkautoJSIntOption(options, @"y", 0);
    int w = TLinkautoJSIntOption(options, @"width", 0);
    int h = TLinkautoJSIntOption(options, @"height", 0);
    NSString *mode = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"mode", @"rgb"), 32);
    NSString *val = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"value", @""), 256);
    double tol = TLinkautoJSDoubleOption(options, @"tolerance", 0.0);
    int skip = TLinkautoJSIntOption(options, @"pixelSkip", 0);
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%@;;%@;;%f;;%d", x, y, w, h, mode, val, tol, skip];
    return [_execution.taskDispatcher dispatchTask:@"findColor" payload:@{@"stringPayload": payload}];
}

- (NSDictionary *)ocrLanguages {
    return [_execution.taskDispatcher dispatchTask:@"ocrLanguages" payload:@{}];
}

- (NSDictionary *)ocrRegion:(NSDictionary *)options {
    int x = TLinkautoJSIntOption(options, @"x", 0);
    int y = TLinkautoJSIntOption(options, @"y", 0);
    int w = TLinkautoJSIntOption(options, @"width", 0);
    int h = TLinkautoJSIntOption(options, @"height", 0);
    NSString *lang = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"lang", @"vie"), 32);
    int psm = TLinkautoJSIntOption(options, @"psm", 7);
    int oem = TLinkautoJSIntOption(options, @"oem", 1);
    NSString *whitelist = TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"whitelist", @""), 256);
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%@;;%d;;%d;;%@", x, y, w, h, lang, psm, oem, whitelist];
    return [_execution.taskDispatcher dispatchTask:@"ocrRegion" payload:@{@"stringPayload": payload}];
}

- (NSDictionary *)runTask:(int)task payload:(NSString *)payload {
    return [_execution.taskDispatcher dispatchTask:@"rawRunTask" payload:@{@"task": @(task), @"payload": payload ?: @""}];
}

// Stub out all remaining required interfaces to satisfy protocol matching.
// They simply delegate similarly via dispatchTask for this iteration.
- (NSDictionary *)screenshotTo:(NSString *)path { return [_execution.taskDispatcher dispatchTask:@"screenshotTo" payload:@{@"path": path}]; }
- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options { return [_execution.taskDispatcher dispatchTask:@"screenshotRegion" payload:@{@"path": path, @"options": options ?: @{}}]; }
- (NSDictionary *)batch:(NSArray *)commands { return @{@"ok": @NO, @"error": @"batch not yet mapped in Phase 1 proxy"}; }
- (NSDictionary *)captureFrame:(NSDictionary *)options {
    BOOL needGray = TLinkautoJSIntOption(options, @"gray", 1) != 0;
    BOOL needBGRA = TLinkautoJSIntOption(options, @"bgra", 1) != 0;
    int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
    if (!needGray && !needBGRA) { needGray = YES; needBGRA = YES; }
    if (ttlMs <= 0) ttlMs = 1000;
    NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d", needGray ? 1 : 0, needBGRA ? 1 : 0, ttlMs];
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"captureFrame" payload:@{@"stringPayload": payload}];
    if (![result[@"ok"] boolValue]) return result;
    // Registry assignment happens in bridge normally, but we delegate strictly here.
    return @{@"ok": @YES, @"id": result[@"parts"][0]};
}
- (NSDictionary *)releaseFrame:(int)frameId { [_execution.handleRegistry releaseFrame:frameId]; return @{@"ok": @YES}; }
- (NSDictionary *)openImage:(NSString *)path { return @{@"ok": @NO}; }
- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height { return @{@"ok": @NO}; }
- (NSDictionary *)releaseImage:(int)imageId { [_execution.handleRegistry releaseImage:imageId]; return @{@"ok": @YES}; }
- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options { return @{@"ok": @NO}; }
- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options { return @{@"ok": @NO}; }
- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options { return @{@"ok": @NO}; }
- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options { return @{@"ok": @NO}; }
- (NSDictionary *)ocr:(NSDictionary *)options { return @{@"ok": @NO}; }
- (NSDictionary *)openApp:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"openApp" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)killApp:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"killApp" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appState:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appState" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appInfo:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appInfo" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appPid:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appPid" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appPaths:(NSString *)bundleId { return @{@"ok": @NO}; }
- (NSDictionary *)listBundles:(BOOL)withInfo { return [_execution.taskDispatcher dispatchTask:@"listBundles" payload:@{@"withInfo": @(withInfo)}]; }
- (NSDictionary *)openUrl:(NSString *)url { return [_execution.taskDispatcher dispatchTask:@"openUrl" payload:@{@"url": url ?: @""}]; }
- (NSDictionary *)setWifi:(BOOL)enabled { return [_execution.taskDispatcher dispatchTask:@"setWifi" payload:@{@"enabled": @(enabled)}]; }
- (NSDictionary *)setBluetooth:(BOOL)enabled { return [_execution.taskDispatcher dispatchTask:@"setBluetooth" payload:@{@"enabled": @(enabled)}]; }
- (NSDictionary *)setAirplaneMode:(BOOL)enabled { return @{@"ok": @NO}; }
- (NSDictionary *)setCellularData:(BOOL)enabled { return @{@"ok": @NO}; }
- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration { return [_execution.taskDispatcher dispatchTask:@"alert" payload:@{@"stringPayload": [NSString stringWithFormat:@"%@;;%@;;%d", title, message, duration]}]; }
- (NSDictionary *)dialog:(NSDictionary *)options { return [_execution.taskDispatcher dispatchTask:@"dialog" payload:@{@"stringPayload": @""}]; }
- (NSDictionary *)setClipboardText:(NSString *)text { return [_execution.taskDispatcher dispatchTask:@"setClipboardText" payload:@{@"text": text ?: @""}]; }
- (NSDictionary *)insertText:(NSString *)text { return [_execution.taskDispatcher dispatchTask:@"insertText" payload:@{@"text": text ?: @""}]; }
- (NSDictionary *)deleteCharacters:(int)count { return [_execution.taskDispatcher dispatchTask:@"deleteCharacters" payload:@{@"count": @(count)}]; }
- (NSDictionary *)moveCursor:(int)offset { return [_execution.taskDispatcher dispatchTask:@"moveCursor" payload:@{@"offset": @(offset)}]; }
- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action { return [_execution.taskDispatcher dispatchTask:@"hardwareKey" payload:@{@"stringPayload": [NSString stringWithFormat:@"%@;;%@", key, action]}]; }
- (NSDictionary *)pressHardwareKey:(NSString *)key { return [_execution.taskDispatcher dispatchTask:@"pressHardwareKey" payload:@{@"key": key ?: @""}]; }
- (NSDictionary *)keepAwake:(BOOL)enabled { return [_execution.taskDispatcher dispatchTask:@"keepAwake" payload:@{@"enabled": @(enabled)}]; }
- (NSDictionary *)touchIndicator:(NSString *)action { return [_execution.taskDispatcher dispatchTask:@"touchIndicator" payload:@{@"action": action ?: @""}]; }
- (NSDictionary *)runShell:(NSString *)command { return [_execution.taskDispatcher dispatchTask:@"runShell" payload:@{@"command": command ?: @""}]; }
- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path { return [_execution.taskDispatcher dispatchTask:@"saveScreenshotToAlbum" payload:@{@"path": path ?: @""}]; }
- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options { return [_execution.taskDispatcher dispatchTask:@"isColors" payload:@{@"stringPayload": @""}]; }
- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options { return [_execution.taskDispatcher dispatchTask:@"findMultiColor" payload:@{@"stringPayload": @""}]; }
- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled { return @{@"ok": @NO}; }
- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script { return @{@"ok": @NO}; }
- (NSDictionary *)removeTimer:(NSString *)name { return @{@"ok": @NO}; }
- (NSDictionary *)readText:(NSString *)path { return @{@"ok": @NO}; }
- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text { return @{@"ok": @NO}; }
- (NSDictionary *)readJSON:(NSString *)path { return @{@"ok": @NO}; }
- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value { return @{@"ok": @NO}; }
- (NSDictionary *)fileExists:(NSString *)path { return @{@"ok": @NO}; }
- (NSDictionary *)deleteFile:(NSString *)path { return @{@"ok": @NO}; }
- (NSDictionary *)screenshot { return [_execution.taskDispatcher dispatchTask:@"screenshot" payload:@{}]; }
- (NSDictionary *)frontMostAppId { return @{@"ok": @NO}; }
- (NSDictionary *)frontMostPid { return @{@"ok": @NO}; }
- (NSDictionary *)orientation { return @{@"ok": @NO}; }
- (NSDictionary *)getClipboardText { return [_execution.taskDispatcher dispatchTask:@"getClipboardText" payload:@{}]; }
- (NSDictionary *)rootDir { return @{@"ok": @NO}; }
- (NSDictionary *)currentDir { return @{@"ok": @NO}; }
- (NSDictionary *)botPath { return @{@"ok": @NO}; }
- (NSDictionary *)info { return [_execution.taskDispatcher dispatchTask:@"info" payload:@{}]; }
- (NSDictionary *)batteryInfo { return [_execution.taskDispatcher dispatchTask:@"batteryInfo" payload:@{}]; }
- (NSDictionary *)runtimeInfo { return @{@"ok": @NO}; }
- (NSDictionary *)wifi { return [_execution.taskDispatcher dispatchTask:@"wifi" payload:@{}]; }
- (NSDictionary *)bluetooth { return [_execution.taskDispatcher dispatchTask:@"bluetooth" payload:@{}]; }
- (NSDictionary *)airplaneMode { return @{@"ok": @NO}; }
- (NSDictionary *)cellularData { return @{@"ok": @NO}; }
- (NSDictionary *)clearScreenshotAlbum { return [_execution.taskDispatcher dispatchTask:@"clearScreenshotAlbum" payload:@{}]; }
- (NSDictionary *)listAutoLaunch { return @{@"ok": @NO}; }
- (NSDictionary *)clearDialogValues { return [_execution.taskDispatcher dispatchTask:@"clearDialogValues" payload:@{}]; }

@end
