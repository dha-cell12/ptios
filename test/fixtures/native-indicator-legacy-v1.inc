// Frozen acc8648 indicator compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodTouchIndicator]) {
        int value = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (value < 0) return [TLinkJSNativeResponse responseWithError:@"touchIndicator requires valid normalized action" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%d", TASK_TOUCH_INDICATOR, value] context:context]];
    }
