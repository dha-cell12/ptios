// Frozen from 2b06a1f; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodConnectivity]) {
        int task = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSString *enabledKey = [args count] > 1 ? [args objectAtIndex:1] : @"enabled";
        id value = [args count] > 2 ? [args objectAtIndex:2] : [NSNull null];
        BOOL setting = value && value != [NSNull null];
        if (task == TASK_WIFI || task == TASK_BLUETOOTH || task == TASK_AIRPLANE || task == TASK_CELLULAR_DATA) {
            NSDictionary *result = TLinkExecuteNativeRadioState(task,setting,setting ? [value boolValue] : false,context);
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSStateResult(result, enabledKey)];
        }
        NSString *payload = setting ? [NSString stringWithFormat:@"1;;%d", [value boolValue] ? 1 : 0] : @"0";
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", task, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSStateResult(result, enabledKey)];
    }
