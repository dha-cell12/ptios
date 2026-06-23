import re

text = open("pccontrol/jsruntime/TLinkautoJSBridge.mm").read()

replacements = {
    "- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options { return @{@\"ok\": @NO}; }": """- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"framePickColor" payload:@{@"frameId": @(frameId), @"x": @(x), @"y": @(y), @"options": options ?: @{}}];
}""",
    "- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options { return @{@\"ok\": @NO}; }": """- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"framePickColors" payload:@{@"frameId": @(frameId), @"points": points ?: @[], @"options": options ?: @{}}];
}""",
    "- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options { return @{@\"ok\": @NO}; }": """- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"findImageInFrame" payload:@{@"frameId": @(frameId), @"imageId": @(imageId), @"options": options ?: @{}}];
}""",
    "- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options { return @{@\"ok\": @NO}; }": """- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"ocrFrame" payload:@{@"frameId": @(frameId), @"options": options ?: @{}}];
}""",
    "- (NSDictionary *)ocr:(NSDictionary *)options { return @{@\"ok\": @NO}; }": """- (NSDictionary *)ocr:(NSDictionary *)options {
    return [_execution.taskDispatcher dispatchTask:@"ocr" payload:@{@"options": options ?: @{}}];
}""",
    "- (NSDictionary *)appPaths:(NSString *)bundleId { return @{@\"ok\": @NO}; }": """- (NSDictionary *)appPaths:(NSString *)bundleId {
    return [_execution.taskDispatcher dispatchTask:@"appPaths" payload:@{@"bundleId": bundleId ?: @""}];
}""",
    "- (NSDictionary *)setAirplaneMode:(BOOL)enabled { return @{@\"ok\": @NO}; }": """- (NSDictionary *)setAirplaneMode:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setAirplaneMode" payload:@{@"enabled": @(enabled)}];
}""",
    "- (NSDictionary *)setCellularData:(BOOL)enabled { return @{@\"ok\": @NO}; }": """- (NSDictionary *)setCellularData:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setCellularData" payload:@{@"enabled": @(enabled)}];
}""",
    "- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled { return @{@\"ok\": @NO}; }": """- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled {
    return [_execution.taskDispatcher dispatchTask:@"setAutoLaunch" payload:@{@"name": name ?: @"", @"script": script ?: @"", @"enabled": @(enabled)}];
}""",
    "- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script { return @{@\"ok\": @NO}; }": """- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script {
    return [_execution.taskDispatcher dispatchTask:@"setTimer" payload:@{@"name": name ?: @"", @"interval": @(interval), @"repeat": @(repeat), @"script": script ?: @""}];
}""",
    "- (NSDictionary *)removeTimer:(NSString *)name { return @{@\"ok\": @NO}; }": """- (NSDictionary *)removeTimer:(NSString *)name {
    return [_execution.taskDispatcher dispatchTask:@"removeTimer" payload:@{@"name": name ?: @""}];
}""",
    "- (NSDictionary *)readText:(NSString *)path { return @{@\"ok\": @NO}; }": """- (NSDictionary *)readText:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"readText" payload:@{@"path": path ?: @""}];
}""",
    "- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text { return @{@\"ok\": @NO}; }": """- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text {
    return [_execution.taskDispatcher dispatchTask:@"writeText" payload:@{@"path": path ?: @"", @"text": text ?: @""}];
}""",
    "- (NSDictionary *)readJSON:(NSString *)path { return @{@\"ok\": @NO}; }": """- (NSDictionary *)readJSON:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"readJSON" payload:@{@"path": path ?: @""}];
}""",
    "- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value { return @{@\"ok\": @NO}; }": """- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value {
    return [_execution.taskDispatcher dispatchTask:@"writeJSON" payload:@{@"path": path ?: @"", @"value": value ? [value toObject] : @""}];
}""",
    "- (NSDictionary *)fileExists:(NSString *)path { return @{@\"ok\": @NO}; }": """- (NSDictionary *)fileExists:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"fileExists" payload:@{@"path": path ?: @""}];
}""",
    "- (NSDictionary *)deleteFile:(NSString *)path { return @{@\"ok\": @NO}; }": """- (NSDictionary *)deleteFile:(NSString *)path {
    return [_execution.taskDispatcher dispatchTask:@"deleteFile" payload:@{@"path": path ?: @""}];
}""",
    "- (NSDictionary *)frontMostAppId { return @{@\"ok\": @NO}; }": """- (NSDictionary *)frontMostAppId {
    return [_execution.taskDispatcher dispatchTask:@"frontMostAppId" payload:@{}];
}""",
    "- (NSDictionary *)frontMostPid { return @{@\"ok\": @NO}; }": """- (NSDictionary *)frontMostPid {
    return [_execution.taskDispatcher dispatchTask:@"frontMostPid" payload:@{}];
}""",
    "- (NSDictionary *)orientation { return @{@\"ok\": @NO}; }": """- (NSDictionary *)orientation {
    return [_execution.taskDispatcher dispatchTask:@"orientation" payload:@{}];
}""",
    "- (NSDictionary *)rootDir { return @{@\"ok\": @NO}; }": """- (NSDictionary *)rootDir {
    return [_execution.taskDispatcher dispatchTask:@"rootDir" payload:@{}];
}""",
    "- (NSDictionary *)currentDir { return @{@\"ok\": @NO}; }": """- (NSDictionary *)currentDir {
    return [_execution.taskDispatcher dispatchTask:@"currentDir" payload:@{}];
}""",
    "- (NSDictionary *)botPath { return @{@\"ok\": @NO}; }": """- (NSDictionary *)botPath {
    return [_execution.taskDispatcher dispatchTask:@"botPath" payload:@{}];
}""",
    "- (NSDictionary *)runtimeInfo { return @{@\"ok\": @NO}; }": """- (NSDictionary *)runtimeInfo {
    return [_execution.taskDispatcher dispatchTask:@"runtimeInfo" payload:@{}];
}""",
    "- (NSDictionary *)airplaneMode { return @{@\"ok\": @NO}; }": """- (NSDictionary *)airplaneMode {
    return [_execution.taskDispatcher dispatchTask:@"airplaneMode" payload:@{}];
}""",
    "- (NSDictionary *)cellularData { return @{@\"ok\": @NO}; }": """- (NSDictionary *)cellularData {
    return [_execution.taskDispatcher dispatchTask:@"cellularData" payload:@{}];
}""",
    "- (NSDictionary *)listAutoLaunch { return @{@\"ok\": @NO}; }": """- (NSDictionary *)listAutoLaunch {
    return [_execution.taskDispatcher dispatchTask:@"listAutoLaunch" payload:@{}];
}""",
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSBridge.mm", "w") as f:
    f.write(text)
