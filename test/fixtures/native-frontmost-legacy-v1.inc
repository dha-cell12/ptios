// Frozen c3f2443 frontMostAppId/orientation JS-to-RAW adapters.
    else if ([method isEqualToString:TLinkJSNativeMethodFrontMostAppId]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_FRONTMOST_APP_ID] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"bundleId": TLinkautoJSSafeStringPart(parts, 1)})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodOrientation]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_FRONTMOST_APP_ORIENTATION] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"value": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
