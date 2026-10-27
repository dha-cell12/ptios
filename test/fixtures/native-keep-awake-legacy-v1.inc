// Frozen b60a754 keep-awake compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodKeepAwake]) {
        BOOL enabled = [args count] > 0 ? [[args objectAtIndex:0] boolValue] : NO;
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_KEEP_AWAKE, enabled ? @"1" : @"0"] context:context]];
    }
