// Frozen e5a4acb frontmost PID compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodFrontMostPid]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_FRONTMOST_PID] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"pid": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
