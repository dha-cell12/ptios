// Frozen aed36da radio compatibility oracle (unchanged in C02b37).
    else if ([method isEqualToString:TLinkJSNativeMethodConnectivity]) {
        int task = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSString *enabledKey = [args count] > 1 ? [args objectAtIndex:1] : @"enabled";
        id value = [args count] > 2 ? [args objectAtIndex:2] : [NSNull null];
        NSString *payload = (value && value != [NSNull null]) ? [NSString stringWithFormat:@"1;;%d", [value boolValue] ? 1 : 0] : @"0";
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", task, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSStateResult(result, enabledKey)];
    }
