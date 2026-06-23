#import "TLinkautoJSLegacyTaskAdapter.h"
#import "TLinkautoJSRuntimeExecution.h"
#import "../Task.h"
#import "../RuntimeUtils.h"
#include <dlfcn.h>

@implementation TLinkautoJSLegacyTaskAdapter {
    id<TLinkautoJSTaskContext> _context;
}

- (instancetype)initWithTaskContext:(id<TLinkautoJSTaskContext>)context {
    self = [super init];
    if (self) {
        _context = context;
    }
    return self;
}

- (void)setTaskContext:(id<TLinkautoJSTaskContext>)context {
    _context = context;
}

- (NSDictionary *)runTask:(int)task payload:(NSString *)payload {
    id<TLinkautoJSTaskContext> ctx = _context;
    if (!ctx) return @{@"ok": @NO, @"error": @"context null"};

    if ([ctx isCancelled]) {
        return @{@"ok": @NO, @"error": @"task cancelled"};
    }

    if (task < 0 || task > 255) {
        return @{ @"ok": @NO, @"error": @"runTask task code out of range" };
    }

    NSString *taskStr = [NSString stringWithFormat:@"%d|%@", task, payload ?: @""];
    NSData *payloadData = [taskStr dataUsingEncoding:NSUTF8StringEncoding];

    if (payloadData.length > 512 * 1024) {
        return @{ @"ok": @NO, @"error": @"runTask payload exceeds maximum size" };
    }

    NSCondition *sleepCondition = [[NSCondition alloc] init];
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

        void processTask(UInt8* dataArray, CFWriteStreamRef stream);
        if (1) {
            processTask((UInt8 *)[payloadData bytes], writeStream);
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
    while (!responseString) {
        [sleepCondition wait];
    }
    [sleepCondition unlock];

    if (!responseString) {
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

- (NSDictionary *)dispatchLegacyTask:(NSString *)taskName payload:(NSDictionary *)dict {
    if ([taskName isEqualToString:@"tap"]) {
        return [self runTask:TASK_NATIVE_TAP payload:[NSString stringWithFormat:@"%.1f;;%.1f", [dict[@"x"] doubleValue], [dict[@"y"] doubleValue]]];
    } else if ([taskName isEqualToString:@"swipe"]) {
        return [self runTask:TASK_NATIVE_SWIPE payload:[NSString stringWithFormat:@"%.1f;;%.1f;;%.1f;;%.1f;;%.1f", [dict[@"x1"] doubleValue], [dict[@"y1"] doubleValue], [dict[@"x2"] doubleValue], [dict[@"y2"] doubleValue], [dict[@"duration"] doubleValue]]];
    } else if ([taskName isEqualToString:@"longPress"]) {
        return [self runTask:TASK_NATIVE_TAP payload:[NSString stringWithFormat:@"%.1f;;%.1f;;%.1f", [dict[@"x"] doubleValue], [dict[@"y"] doubleValue], [dict[@"duration"] doubleValue]]];
    } else if ([taskName isEqualToString:@"gesture"]) {
        return [self runTask:TASK_NATIVE_GESTURE payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"toast"]) {
        return [self runTask:TASK_SHOW_TOAST payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"getScreenSize"]) {
        return [self runTask:TASK_SCREENSHOT payload:@""];
    } else if ([taskName isEqualToString:@"pickColor"]) {
        return [self runTask:TASK_COLOR_PICKER payload:[NSString stringWithFormat:@"%.0f;;%.0f", [dict[@"x"] doubleValue], [dict[@"y"] doubleValue]]];
    } else if ([taskName isEqualToString:@"openApp"]) {
        return [self runTask:TASK_PROCESS_BRING_FOREGROUND payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"killApp"]) {
        return [self runTask:TASK_APP_KILL payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"appState"]) {
        return [self runTask:TASK_APP_STATE payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"appInfo"]) {
        return [self runTask:TASK_APP_INFO payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"appPid"]) {
        return [self runTask:TASK_APP_PID payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"listBundles"]) {
        return [self runTask:TASK_LIST_BUNDLES payload:[dict[@"withInfo"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"openUrl"]) {
        return [self runTask:TASK_OPEN_URL payload:dict[@"url"]];
    } else if ([taskName isEqualToString:@"wifi"]) {
        return [self runTask:TASK_WIFI payload:@""];
    } else if ([taskName isEqualToString:@"bluetooth"]) {
        return [self runTask:TASK_BLUETOOTH payload:@""];
    } else if ([taskName isEqualToString:@"setWifi"]) {
        return [self runTask:TASK_WIFI payload:[dict[@"enabled"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"setBluetooth"]) {
        return [self runTask:TASK_BLUETOOTH payload:[dict[@"enabled"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"matchTemplate"]) {
        return [self runTask:TASK_TEMPLATE_MATCH payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"findColor"]) {
        return [self runTask:TASK_COLOR_SEARCHER payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"isColors"]) {
        NSArray *points = dict[@"points"];
        NSDictionary *options = dict[@"options"] ?: @{};
        if (![points isKindOfClass:[NSArray class]] || [points count] == 0 || [points count] > 512) return @{@"ok": @NO, @"error": @"invalid points"};
        NSMutableArray *encoded = [NSMutableArray arrayWithCapacity:[points count]];
        for (id point in points) {
            if (![point isKindOfClass:[NSArray class]] || [point count] < 2) return @{@"ok": @NO, @"error": @"invalid point format"};
            int x = [point[0] intValue];
            int y = [point[1] intValue];
            NSString *colorStr = @"";
            if ([point count] > 2) colorStr = point[2];
            // Decode color to r, g, b
            unsigned int colorCode = 0;
            if ([colorStr hasPrefix:@"#"]) colorStr = [colorStr substringFromIndex:1];
            [[NSScanner scannerWithString:colorStr] scanHexInt:&colorCode];
            int r = (colorCode >> 16) & 0xFF;
            int g = (colorCode >> 8) & 0xFF;
            int b = colorCode & 0xFF;
            [encoded addObject:[NSString stringWithFormat:@"%d,,%d,,%d,,%d,,%d", x, y, r, g, b]];
        }
        NSString *table = [encoded componentsJoinedByString:@"|"];

        int mode = 1;
        if (options[@"mode"]) mode = [options[@"mode"] intValue];
        double value = 0;
        if (options[@"value"]) value = [options[@"value"] doubleValue];
        else if (options[@"tolerance"]) value = [options[@"tolerance"] doubleValue];

        NSDictionary *result = [self runTask:TASK_COLOR_SEARCHER payload:[NSString stringWithFormat:@"2;;%@;;%d;;%.4f", table, mode, value]];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
        BOOL matched = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
        NSMutableDictionary *mutResult = [result mutableCopy];
        mutResult[@"matched"] = @(matched);
        mutResult[@"value"] = @(matched);
        return mutResult;
    } else if ([taskName isEqualToString:@"findMultiColor"]) {
        NSArray *points = dict[@"points"];
        NSDictionary *options = dict[@"options"] ?: @{};
        if (![points isKindOfClass:[NSArray class]] || [points count] == 0 || [points count] > 512) return @{@"ok": @NO, @"error": @"invalid points"};
        NSMutableArray *encoded = [NSMutableArray arrayWithCapacity:[points count]];
        for (id point in points) {
            if (![point isKindOfClass:[NSArray class]] || [point count] < 2) return @{@"ok": @NO, @"error": @"invalid point format"};
            int x = [point[0] intValue];
            int y = [point[1] intValue];
            NSString *colorStr = @"";
            if ([point count] > 2) colorStr = point[2];
            unsigned int colorCode = 0;
            if ([colorStr hasPrefix:@"#"]) colorStr = [colorStr substringFromIndex:1];
            [[NSScanner scannerWithString:colorStr] scanHexInt:&colorCode];
            int r = (colorCode >> 16) & 0xFF;
            int g = (colorCode >> 8) & 0xFF;
            int b = colorCode & 0xFF;
            [encoded addObject:[NSString stringWithFormat:@"%d,,%d,,%d,,%d,,%d", x, y, r, g, b]];
        }
        NSString *table = [encoded componentsJoinedByString:@"|"];

        double x = [options[@"x"] doubleValue];
        double y = [options[@"y"] doubleValue];
        double width = [options[@"width"] doubleValue];
        double height = [options[@"height"] doubleValue];
        int mode = options[@"mode"] ? [options[@"mode"] intValue] : 1;
        double value = 0;
        if (options[@"value"]) value = [options[@"value"] doubleValue];
        else if (options[@"tolerance"]) value = [options[@"tolerance"] doubleValue];
        int skip = [options[@"skip"] intValue];

        NSString *payload = [NSString stringWithFormat:@"3;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d", x, y, width, height, table, mode, value, skip];
        NSDictionary *result = [self runTask:TASK_COLOR_SEARCHER payload:payload];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return result;
        int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue];
        int foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
        NSMutableDictionary *mutResult = [result mutableCopy];
        mutResult[@"matched"] = @(foundX >= 0 && foundY >= 0);
        mutResult[@"x"] = @(foundX);
        mutResult[@"y"] = @(foundY);
        return mutResult;
    } else if ([taskName isEqualToString:@"screenshot"]) {
        return [self runTask:TASK_SCREENSHOT payload:@""];
    } else if ([taskName isEqualToString:@"screenshotTo"]) {
        return [self runTask:TASK_SCREENSHOT payload:dict[@"path"]];
    } else if ([taskName isEqualToString:@"screenshotRegion"]) {
        NSString *targetPath = dict[@"path"] ?: @"";
        NSDictionary *options = dict[@"options"] ?: @{};
        double x = [options[@"x"] doubleValue];
        double y = [options[@"y"] doubleValue];
        double width = [options[@"width"] doubleValue];
        double height = [options[@"height"] doubleValue];
        NSString *payload = [NSString stringWithFormat:@"1;;%@;;%.0f;;%.0f;;%.0f;;%.0f", targetPath, x, y, width, height];
        NSDictionary *result = [self runTask:TASK_SCREENSHOT payload:payload];
        NSArray *parts = result[@"parts"];
        NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
        NSMutableDictionary *mutResult = [result mutableCopy];
        mutResult[@"path"] = resultPath ?: @"";
        mutResult[@"x"] = @(x);
        mutResult[@"y"] = @(y);
        mutResult[@"width"] = @(width);
        mutResult[@"height"] = @(height);
        return mutResult;
    } else if ([taskName isEqualToString:@"saveScreenshotToAlbum"]) {
        return [self runTask:TASK_SCREENSHOT payload:dict[@"path"]];
    } else if ([taskName isEqualToString:@"clearScreenshotAlbum"]) {
        return [self runTask:TASK_SCREENSHOT payload:@""];
    } else if ([taskName isEqualToString:@"hardwareKey"]) {
        return [self runTask:TASK_HARDWARE_KEY payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"pressHardwareKey"]) {
        return [self runTask:TASK_HARDWARE_KEY payload:dict[@"key"]];
    } else if ([taskName isEqualToString:@"keepAwake"]) {
        return [self runTask:TASK_KEEP_AWAKE payload:[dict[@"enabled"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"touchIndicator"]) {
        return [self runTask:TASK_TOUCH_INDICATOR payload:dict[@"action"]];
    } else if ([taskName isEqualToString:@"runShell"]) {
        return [self runTask:TASK_RUN_SHELL payload:dict[@"command"]];
    } else if ([taskName isEqualToString:@"insertText"]) {
        return [self runTask:TASK_TEXT_INPUT payload:dict[@"text"]];
    } else if ([taskName isEqualToString:@"deleteCharacters"]) {
        return [self runTask:TASK_TEXT_INPUT payload:[dict[@"count"] stringValue]];
    } else if ([taskName isEqualToString:@"moveCursor"]) {
        return [self runTask:TASK_TEXT_INPUT payload:[dict[@"offset"] stringValue]];
    } else if ([taskName isEqualToString:@"setClipboardText"]) {
        return [self runTask:TASK_TEXT_INPUT payload:dict[@"text"]];
    } else if ([taskName isEqualToString:@"getClipboardText"]) {
        return [self runTask:TASK_TEXT_INPUT payload:@""];
    } else if ([taskName isEqualToString:@"alert"]) {
        return [self runTask:TASK_SHOW_ALERT_BOX payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"dialog"]) {
        NSString *payload = [NSString stringWithFormat:@"%@;;%@;;%@;;%@", dict[@"title"], dict[@"message"], dict[@"ok"], dict[@"cancel"]];
        NSDictionary *result = [self runTask:TASK_DIALOG payload:payload];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return result;
        NSMutableDictionary *mutResult = [result mutableCopy];
        mutResult[@"response"] = @([TLinkautoJSSafeStringPart(parts, 1) intValue]);
        return mutResult;
    } else if ([taskName isEqualToString:@"clearDialogValues"]) {
        return [self runTask:TASK_CLEAR_DIALOG payload:@""];
    } else if ([taskName isEqualToString:@"info"]) {
        return [self runTask:TASK_GET_DEVICE_INFO payload:@""];
    } else if ([taskName isEqualToString:@"batteryInfo"]) {
        return [self runTask:TASK_GET_DEVICE_INFO payload:@""];
    } else if ([taskName isEqualToString:@"ocrLanguages"]) {
        return [self runTask:TASK_OCR_TESSERACT_REGION payload:@"check_langs"];
    } else if ([taskName isEqualToString:@"ocrRegion"]) {
        return [self runTask:TASK_OCR_TESSERACT_REGION payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"openImage"]) {
        return [self runTask:TASK_IMAGE_OBJECT payload:[NSString stringWithFormat:@"2;;%@", dict[@"path"]]];
    } else if ([taskName isEqualToString:@"captureImage"]) {
        return [self runTask:TASK_IMAGE_OBJECT payload:[NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f", [dict[@"x"] doubleValue], [dict[@"y"] doubleValue], [dict[@"width"] doubleValue], [dict[@"height"] doubleValue]]];
    } else if ([taskName isEqualToString:@"framePickColor"]) {
        return [self runTask:TASK_COLOR_IN_FRAME payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"framePickColors"]) {
        return [self runTask:TASK_COLOR_IN_FRAME payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"findImageInFrame"]) {
        return [self runTask:TASK_FIND_IMAGE_IN_FRAME payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"ocrFrame"]) {
        return [self runTask:TASK_OCR_TESSERACT_REGION payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"ocr"]) {
        return [self runTask:TASK_OCR_TESSERACT_REGION payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"appPaths"]) {
        return [self runTask:TASK_APP_PATHS payload:dict[@"bundleId"]];
    } else if ([taskName isEqualToString:@"setAirplaneMode"]) {
        return [self runTask:TASK_AIRPLANE payload:[dict[@"enabled"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"setCellularData"]) {
        return [self runTask:TASK_CELLULAR_DATA payload:[dict[@"enabled"] boolValue] ? @"1" : @"0"];
    } else if ([taskName isEqualToString:@"setAutoLaunch"]) {
        return [self runTask:TASK_SET_AUTO_LAUNCH payload:[NSString stringWithFormat:@"%@;;%@;;%d", dict[@"name"], dict[@"script"], [dict[@"enabled"] boolValue] ? 1 : 0]];
    } else if ([taskName isEqualToString:@"setTimer"]) {
        return [self runTask:TASK_SET_TIMER payload:[NSString stringWithFormat:@"%@;;%.3f;;%d;;%@", dict[@"name"], [dict[@"interval"] doubleValue], [dict[@"repeat"] boolValue] ? 1 : 0, dict[@"script"]]];
    } else if ([taskName isEqualToString:@"removeTimer"]) {
        return [self runTask:TASK_REMOVE_TIMER payload:dict[@"name"]];
    } else if ([taskName isEqualToString:@"frontMostAppId"]) {
        return [self runTask:TASK_FRONTMOST_APP_ID payload:@""];
    } else if ([taskName isEqualToString:@"frontMostPid"]) {
        return [self runTask:TASK_FRONTMOST_PID payload:@""];
    } else if ([taskName isEqualToString:@"orientation"]) {
        return [self runTask:TASK_FRONTMOST_APP_ORIENTATION payload:@""];
    } else if ([taskName isEqualToString:@"rootDir"]) {
        return [self runTask:TASK_ROOT_DIR payload:@""];
    } else if ([taskName isEqualToString:@"currentDir"]) {
        return [self runTask:TASK_CURRENT_DIR payload:@""];
    } else if ([taskName isEqualToString:@"botPath"]) {
        return [self runTask:TASK_BOT_PATH payload:@""];
    } else if ([taskName isEqualToString:@"airplaneMode"]) {
        return [self runTask:TASK_AIRPLANE payload:@""];
    } else if ([taskName isEqualToString:@"cellularData"]) {
        return [self runTask:TASK_CELLULAR_DATA payload:@""];
    } else if ([taskName isEqualToString:@"listAutoLaunch"]) {
        return [self runTask:TASK_LIST_AUTO_LAUNCH payload:@""];
    } else if ([taskName isEqualToString:@"captureFrame"]) {
        int needGray = [dict[@"gray"] intValue];
        int needBGRA = [dict[@"bgra"] intValue];
        int ttlMs = [dict[@"ttlMs"] intValue];
        NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d", needGray, needBGRA, ttlMs];
        NSDictionary *result = [self runTask:TASK_FRAME_CAPTURE payload:payload];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 1) return result;
        NSMutableDictionary *mutResult = [result mutableCopy];
        mutResult[@"id"] = @([parts[0] intValue]);
        return mutResult;
    } else if ([taskName isEqualToString:@"rawRunTask"]) {
        return [self runTask:[dict[@"task"] intValue] payload:dict[@"payload"]];
    } else if ([taskName isEqualToString:@"batch"]) {
        return [self runTask:TASK_NATIVE_BATCH payload:dict[@"stringPayload"]];
    } else if ([taskName isEqualToString:@"readText"] || [taskName isEqualToString:@"writeText"] || [taskName isEqualToString:@"readJSON"] || [taskName isEqualToString:@"writeJSON"] || [taskName isEqualToString:@"fileExists"] || [taskName isEqualToString:@"deleteFile"] || [taskName isEqualToString:@"runtimeInfo"]) {
        // Handled in JS side or via rawRunTask in original implementation,
        // mapping them directly to equivalent native legacy tasks or returning not implemented.
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"unmapped Phase 1 task: %@", taskName]};
    }

    return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"unknown legacy task: %@", taskName]};
}

@end
