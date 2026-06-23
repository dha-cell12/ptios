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
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"tap(x, y) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"tap" payload:@{@"x": @(x), @"y": @(y)}];
}

- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration {
    if (!TLinkautoJSIsFiniteNumber(x1) || !TLinkautoJSIsFiniteNumber(y1) || !TLinkautoJSIsFiniteNumber(x2) || !TLinkautoJSIsFiniteNumber(y2) || !TLinkautoJSIsFiniteNumber(duration)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"swipe(...) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"swipe" payload:@{@"x1": @(x1), @"y1": @(y1), @"x2": @(x2), @"y2": @(y2), @"duration": @(duration)}];
}

- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(duration)) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"longPress(x, y, duration) requires finite numbers" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    return [_execution.taskDispatcher dispatchTask:@"longPress" payload:@{@"x": @(x), @"y": @(y), @"duration": @(duration)}];
}

- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options {
    if (![points isKindOfClass:[NSArray class]] || points.count < 2 || points.count > 512) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"gesture(points, options) requires 2-512 points as [x,y] arrays or {x,y} objects" inContext:[JSContext currentContext]];
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
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"pickColor(x, y) requires finite numbers" inContext:[JSContext currentContext]];
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
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"toast(message) requires a non-empty message" inContext:[JSContext currentContext]];
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
- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options {
    double x = TLinkautoJSDoubleOption(options, @"x", 0);
    double y = TLinkautoJSDoubleOption(options, @"y", 0);
    double width = TLinkautoJSDoubleOption(options, @"width", 0);
    double height = TLinkautoJSDoubleOption(options, @"height", 0);

    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"screenshotRegion(path, options) requires finite positive width/height" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }

    return [_execution.taskDispatcher dispatchTask:@"screenshotRegion" payload:@{
        @"path": path ?: @"",
        @"x": @(x),
        @"y": @(y),
        @"width": @(width),
        @"height": @(height)
    }];
}
- (NSDictionary *)batch:(NSArray *)commands { return [_execution.taskDispatcher dispatchTask:@"batch" payload:@{@"commands": commands ?: @[]}]; }
- (NSDictionary *)captureFrame:(NSDictionary *)options {
    BOOL needGray = TLinkautoJSIntOption(options, @"gray", 1) != 0;
    BOOL needBGRA = TLinkautoJSIntOption(options, @"bgra", 1) != 0;
    int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
    if (!needGray && !needBGRA) { needGray = YES; needBGRA = YES; }
    if (ttlMs <= 0) ttlMs = 1000;

    return [_execution.taskDispatcher dispatchTask:@"captureFrame" payload:@{
        @"gray": @(needGray),
        @"bgra": @(needBGRA),
        @"ttlMs": @(ttlMs)
    }];
}
- (NSDictionary *)releaseFrame:(int)frameId { [_execution.handleRegistry releaseFrame:frameId]; return @{@"ok": @YES}; }
- (NSDictionary *)openImage:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 || TLinkautoJSStringContainsAny(path, @[@";;", @"\r", @"\n"])) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"openImage(path) requires a valid path" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"openImage" payload:@{@"path": path}];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 3) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 0) intValue];
    // Registry assignment delegates
    return @{@"ok": @YES, @"id": @(imageId), @"width": @([TLinkautoJSSafeStringPart(parts, 1) intValue]), @"height": @([TLinkautoJSSafeStringPart(parts, 2) intValue])};
}
- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"captureImage(x, y, width, height) requires finite positive dimensions" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"captureImage" payload:@{@"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)}];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 3) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 0) intValue];
    return @{@"ok": @YES, @"id": @(imageId), @"width": @([TLinkautoJSSafeStringPart(parts, 1) intValue]), @"height": @([TLinkautoJSSafeStringPart(parts, 2) intValue])};
}
- (NSDictionary *)releaseImage:(int)imageId { [_execution.handleRegistry releaseImage:imageId]; return @{@"ok": @YES}; }
- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"framePickColor" payload:@{@"frameId": @(frameId), @"x": @(x), @"y": @(y), @"options": options ?: @{}}];
}
- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"framePickColors" payload:@{@"frameId": @(frameId), @"points": points ?: @[], @"options": options ?: @{}}];
}
- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"findImageInFrame" payload:@{@"frameId": @(frameId), @"imageId": @(imageId), @"options": options ?: @{}}];
}
- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"ocrFrame" payload:@{@"frameId": @(frameId), @"options": options ?: @{}}];
}
- (NSDictionary *)ocr:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"ocr" payload:@{@"options": options ?: @{}}];
}
- (NSDictionary *)openApp:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"openApp" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)killApp:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"killApp" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appState:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appState" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appInfo:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appInfo" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appPid:(NSString *)bundleId { return [_execution.taskDispatcher dispatchTask:@"appPid" payload:@{@"bundleId": bundleId ?: @""}]; }
- (NSDictionary *)appPaths:(NSString *)bundleId {
    return [_execution.taskDispatcher dispatchTask:@"appPaths" payload:@{@"bundleId": bundleId ?: @""}];
}
- (NSDictionary *)listBundles:(BOOL)withInfo { return [_execution.taskDispatcher dispatchTask:@"listBundles" payload:@{@"withInfo": @(withInfo)}]; }
- (NSDictionary *)openUrl:(NSString *)url { return [_execution.taskDispatcher dispatchTask:@"openUrl" payload:@{@"url": url ?: @""}]; }
- (NSDictionary *)setWifi:(BOOL)enabled { return [_execution.taskDispatcher dispatchTask:@"setWifi" payload:@{@"enabled": @(enabled)}]; }
- (NSDictionary *)setBluetooth:(BOOL)enabled { return [_execution.taskDispatcher dispatchTask:@"setBluetooth" payload:@{@"enabled": @(enabled)}]; }
- (NSDictionary *)setAirplaneMode:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setAirplaneMode" payload:@{@"enabled": @(enabled)}];
}
- (NSDictionary *)setCellularData:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setCellularData" payload:@{@"enabled": @(enabled)}];
}
- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration { return [_execution.taskDispatcher dispatchTask:@"alert" payload:@{@"stringPayload": [NSString stringWithFormat:@"%@;;%@;;%d", title, message, duration]}]; }
- (NSDictionary *)dialog:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"dialog" payload:@{
        @"title": TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"title", @"TLinkauto"), 80) ?: @"",
        @"message": TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"message", @""), 300) ?: @"",
        @"ok": TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"ok", @"OK"), 40) ?: @"",
        @"cancel": TLinkautoJSSanitizeProtocolText(TLinkautoJSStringOption(options, @"cancel", @"Cancel"), 40) ?: @""
    }];
}
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
- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"isColors" payload:@{
        @"points": points ?: @[],
        @"options": options ?: @{}
    }];
}
- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"findMultiColor" payload:@{
        @"points": points ?: @[],
        @"options": options ?: @{}
    }];
}
- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setAutoLaunch" payload:@{@"name": name ?: @"", @"script": script ?: @"", @"enabled": @(enabled)}];
}
- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script {
    return [_execution.taskDispatcher dispatchTask:@"setTimer" payload:@{@"name": name ?: @"", @"interval": @(interval), @"repeat": @(repeat), @"script": script ?: @""}];
}
- (NSDictionary *)removeTimer:(NSString *)name {
    return [_execution.taskDispatcher dispatchTask:@"removeTimer" payload:@{@"name": name ?: @""}];
}
- (NSDictionary *)readText:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"readText" payload:@{@"path": path ?: @""}];
}
- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text {
    return [_execution.taskDispatcher dispatchTask:@"writeText" payload:@{@"path": path ?: @"", @"text": text ?: @""}];
}
- (NSDictionary *)readJSON:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"readJSON" payload:@{@"path": path ?: @""}];
}
- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value {
    return [_execution.taskDispatcher dispatchTask:@"writeJSON" payload:@{@"path": path ?: @"", @"value": value ? [value toObject] : @""}];
}
- (NSDictionary *)fileExists:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"fileExists" payload:@{@"path": path ?: @""}];
}
- (NSDictionary *)deleteFile:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"deleteFile" payload:@{@"path": path ?: @""}];
}
- (NSDictionary *)screenshot { return [_execution.taskDispatcher dispatchTask:@"screenshot" payload:@{}]; }
- (NSDictionary *)frontMostAppId {
    return [_execution.taskDispatcher dispatchTask:@"frontMostAppId" payload:@{}];
}
- (NSDictionary *)frontMostPid {
    return [_execution.taskDispatcher dispatchTask:@"frontMostPid" payload:@{}];
}
- (NSDictionary *)orientation {
    return [_execution.taskDispatcher dispatchTask:@"orientation" payload:@{}];
}
- (NSDictionary *)getClipboardText { return [_execution.taskDispatcher dispatchTask:@"getClipboardText" payload:@{}]; }
- (NSDictionary *)rootDir {
    return [_execution.taskDispatcher dispatchTask:@"rootDir" payload:@{}];
}
- (NSDictionary *)currentDir {
    return [_execution.taskDispatcher dispatchTask:@"currentDir" payload:@{}];
}
- (NSDictionary *)botPath {
    return [_execution.taskDispatcher dispatchTask:@"botPath" payload:@{}];
}
- (NSDictionary *)info { return [_execution.taskDispatcher dispatchTask:@"info" payload:@{}]; }
- (NSDictionary *)batteryInfo { return [_execution.taskDispatcher dispatchTask:@"batteryInfo" payload:@{}]; }
- (NSDictionary *)runtimeInfo {
    return [_execution.taskDispatcher dispatchTask:@"runtimeInfo" payload:@{}];
}
- (NSDictionary *)wifi { return [_execution.taskDispatcher dispatchTask:@"wifi" payload:@{}]; }
- (NSDictionary *)bluetooth { return [_execution.taskDispatcher dispatchTask:@"bluetooth" payload:@{}]; }
- (NSDictionary *)airplaneMode {
    return [_execution.taskDispatcher dispatchTask:@"airplaneMode" payload:@{}];
}
- (NSDictionary *)cellularData {
    return [_execution.taskDispatcher dispatchTask:@"cellularData" payload:@{}];
}
- (NSDictionary *)clearScreenshotAlbum { return [_execution.taskDispatcher dispatchTask:@"clearScreenshotAlbum" payload:@{}]; }
- (NSDictionary *)listAutoLaunch {
    return [_execution.taskDispatcher dispatchTask:@"listAutoLaunch" payload:@{}];
}
- (NSDictionary *)clearDialogValues { return [_execution.taskDispatcher dispatchTask:@"clearDialogValues" payload:@{}]; }

@end
