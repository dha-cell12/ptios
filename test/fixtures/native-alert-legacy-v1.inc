// Frozen 78359d2 alert compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodAlert]) {
        NSString *title = [args count] > 0 ? [args objectAtIndex:0] : @"TLinkauto";
        NSString *message = [args count] > 1 ? [args objectAtIndex:1] : @"";
        int duration = [args count] > 2 ? [[args objectAtIndex:2] intValue] : 3;
        if (duration <= 0) duration = 3;
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%d", TASK_SHOW_ALERT_BOX, title ?: @"TLinkauto", message ?: @"", duration] context:context]];
    }
