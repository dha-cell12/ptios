import re

text = open("pccontrol/jsruntime/TLinkautoJSBridge.mm").read()

replacements = {
    "- (NSDictionary *)openImage:(NSString *)path { return @{@\"ok\": @NO}; }": """- (NSDictionary *)openImage:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 || TLinkautoJSStringContainsAny(path, @[@";;", @"\\r", @"\\n"])) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"openImage(path) requires a valid path" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"openImage" payload:@{@"path": path}];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 4) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    // Registry assignment delegates
    return @{@"ok": @YES, @"id": @(imageId), @"width": @([TLinkautoJSSafeStringPart(parts, 2) intValue]), @"height": @([TLinkautoJSSafeStringPart(parts, 3) intValue])};
}""",
    "- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height { return @{@\"ok\": @NO}; }": """- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height {
    if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) ||
        !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
        [JSContext currentContext].exception = [JSValue valueWithNewErrorFromMessage:@"captureImage(x, y, width, height) requires finite positive dimensions" inContext:[JSContext currentContext]];
        return @{ @"ok": @NO };
    }
    NSDictionary *result = [_execution.taskDispatcher dispatchTask:@"captureImage" payload:@{@"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)}];
    NSArray *parts = result[@"parts"];
    if (![result[@"ok"] boolValue] || [parts count] < 4) return result;
    int imageId = [TLinkautoJSSafeStringPart(parts, 1) intValue];
    return @{@"ok": @YES, @"id": @(imageId), @"width": @([TLinkautoJSSafeStringPart(parts, 2) intValue]), @"height": @([TLinkautoJSSafeStringPart(parts, 3) intValue])};
}""",
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSBridge.mm", "w") as f:
    f.write(text)
