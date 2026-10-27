// Frozen b2ac272 app PID compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodOpenApp] || [method isEqualToString:TLinkJSNativeMethodKillApp] || [method isEqualToString:TLinkJSNativeMethodAppState] || [method isEqualToString:TLinkJSNativeMethodAppInfo] || [method isEqualToString:TLinkJSNativeMethodAppPid] || [method isEqualToString:TLinkJSNativeMethodAppPaths]) {
        NSString *bundleId = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(bundleId)) return [TLinkJSNativeResponse responseWithError:@"app method requires a valid bundle id" code:@-1];
        int task = TASK_APP_STATE;
        if ([method isEqualToString:TLinkJSNativeMethodOpenApp]) task = TASK_PROCESS_BRING_FOREGROUND;
        else if ([method isEqualToString:TLinkJSNativeMethodKillApp]) task = TASK_APP_KILL;
        else if ([method isEqualToString:TLinkJSNativeMethodAppInfo]) task = TASK_APP_INFO;
        else if ([method isEqualToString:TLinkJSNativeMethodAppPid]) task = TASK_APP_PID;
        else if ([method isEqualToString:TLinkJSNativeMethodAppPaths]) task = TASK_APP_PATHS;
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", task, bundleId] context:context];
        NSArray *parts = result[@"parts"];
        if ([method isEqualToString:TLinkJSNativeMethodOpenApp] || [method isEqualToString:TLinkJSNativeMethodKillApp]) return [TLinkJSNativeResponse responseWithValue:result];
        if (![result[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:result];
        if ([method isEqualToString:TLinkJSNativeMethodAppState]) {
            if ([parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
            int state = [TLinkautoJSSafeStringPart(parts, 1) intValue];
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"state": @(state), @"running": @(state > 0)})];
        }
        if ([method isEqualToString:TLinkJSNativeMethodAppInfo]) {
            if ([parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"bundleId": TLinkautoJSSafeStringPart(parts, 1), @"name": TLinkautoJSSafeStringPart(parts, 2), @"shortVersion": TLinkautoJSSafeStringPart(parts, 3), @"bundleVersion": TLinkautoJSSafeStringPart(parts, 4), @"state": @([TLinkautoJSSafeStringPart(parts, 5) intValue])})];
        }
        if ([method isEqualToString:TLinkJSNativeMethodAppPid]) {
            if ([parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"pid": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
        }
        if ([parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"bundlePath": TLinkautoJSSafeStringPart(parts, 1), @"dataPath": [parts count] > 2 ? TLinkautoJSSafeStringPart(parts, 2) : @""})];
    }
