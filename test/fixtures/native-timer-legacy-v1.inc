// Frozen 5025221 timer compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodSetTimer]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        double interval = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        BOOL repeat = [args count] > 2 ? [[args objectAtIndex:2] boolValue] : NO;
        NSString *script = [args count] > 3 ? [args objectAtIndex:3] : @"";
        if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script) || !TLinkautoJSIsFiniteNumber(interval) || interval <= 0) return [TLinkJSNativeResponse responseWithError:@"setTimer(name, interval, repeat, script) requires valid values" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%.3f;;%d;;%@", TASK_SET_TIMER, name, interval, repeat ? 1 : 0, script] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodRemoveTimer]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(name)) return [TLinkJSNativeResponse responseWithError:@"removeTimer(name) requires a valid timer name" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_REMOVE_TIMER, name] context:context]];
    }
