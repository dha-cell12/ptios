// Frozen d16db87 auto-launch compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodSetAutoLaunch]) {
        NSString *name = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *script = [args count] > 1 ? [args objectAtIndex:1] : @"";
        BOOL enabled = [args count] > 2 ? [[args objectAtIndex:2] boolValue] : NO;
        if (!TLinkautoJSValidProtocolString(name) || !TLinkautoJSValidProtocolString(script)) return [TLinkJSNativeResponse responseWithError:@"setAutoLaunch(name, script, enabled) requires valid name and script path" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@;;%@;;%d", TASK_SET_AUTO_LAUNCH, name, script, enabled ? 1 : 0] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodListAutoLaunch]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", TASK_LIST_AUTO_LAUNCH] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:result];
        NSMutableArray *items = [NSMutableArray array];
        for (NSUInteger i = 1; i < [parts count]; i++) {
            NSString *entry = TLinkautoJSSafeStringPart(parts, i);
            if ([entry length] == 0) continue;
            NSArray *fields = [entry componentsSeparatedByString:@",,"];
            if ([fields count] >= 3) [items addObject:@{@"name": TLinkautoJSSafeStringPart(fields, 0), @"script": TLinkautoJSSafeStringPart(fields, 1), @"enabled": @([TLinkautoJSSafeStringPart(fields, 2) intValue] != 0)}];
        }
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"items": items})];
    }
