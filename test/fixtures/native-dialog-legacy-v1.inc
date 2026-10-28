// Frozen 03f7454 dialog compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodDialog]) {
        NSString *title = [args count] > 0 ? [args objectAtIndex:0] : @"TLinkauto";
        NSString *message = [args count] > 1 ? [args objectAtIndex:1] : @"";
        NSString *ok = [args count] > 2 ? [args objectAtIndex:2] : @"OK";
        NSString *cancel = [args count] > 3 ? [args objectAtIndex:3] : @"Cancel";
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%@;;%@", TASK_DIALOG, title ?: @"TLinkauto", message ?: @"", ok ?: @"OK", cancel ?: @"Cancel"] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"response": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodClearDialogValues]) {
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_CLEAR_DIALOG] context:context]];
    }
