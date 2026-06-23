import re

text = open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm").read()

replacements = {
    "} else if ([taskName isEqualToString:@\"captureFrame\"]) {": """} else if ([taskName isEqualToString:@"openImage"]) {
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
    } else if ([taskName isEqualToString:@"captureFrame"]) {""",
}

for k, v in replacements.items():
    text = text.replace(k, v)

with open("pccontrol/jsruntime/TLinkautoJSLegacyTaskAdapter.mm", "w") as f:
    f.write(text)
