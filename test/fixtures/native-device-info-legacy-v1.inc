// Frozen aed36da device info compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodInfo]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d30", TASK_GET_DEVICE_INFO] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"name": TLinkautoJSSafeStringPart(parts, 1), @"systemName": TLinkautoJSSafeStringPart(parts, 2), @"systemVersion": TLinkautoJSSafeStringPart(parts, 3), @"model": TLinkautoJSSafeStringPart(parts, 4), @"identifierForVendor": TLinkautoJSSafeStringPart(parts, 5)})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodBatteryInfo]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d31", TASK_GET_DEVICE_INFO] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"state": @([TLinkautoJSSafeStringPart(parts, 1) intValue]), @"level": @([TLinkautoJSSafeStringPart(parts, 2) doubleValue])})];
    }
