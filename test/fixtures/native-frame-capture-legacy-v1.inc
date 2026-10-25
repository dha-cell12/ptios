// Frozen pre-C02b18 JS captureFrame branch at 62a9c90.
    else if ([method isEqualToString:TLinkJSNativeMethodCaptureFrame]) {
        NSDictionary *options = [args count] > 0 ? [args objectAtIndex:0] : @{};
        int gray = TLinkautoJSIntOption(options, @"gray", 1);
        int bgra = TLinkautoJSIntOption(options, @"bgra", 1);
        int ttlMs = TLinkautoJSIntOption(options, @"ttlMs", 1000);
        NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%d%@", gray ? 1 : 0, bgra ? 1 : 0, ttlMs, TLinkautoJSOwnerSuffix(context)];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_FRAME_CAPTURE, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 14) return [TLinkJSNativeResponse responseWithValue:result];
        int frameId = [parts[1] intValue];
        [runtime trackFrameId:frameId];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"id"] = @(frameId);
        res[@"width"] = @([TLinkautoJSSafeStringPart(parts, 2) intValue]);
        res[@"height"] = @([TLinkautoJSSafeStringPart(parts, 3) intValue]);
        res[@"bytesPerRow"] = @([TLinkautoJSSafeStringPart(parts, 4) intValue]);
        res[@"scale"] = @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]);
        res[@"coord"] = TLinkautoJSSafeStringPart(parts, 6);
        res[@"format"] = TLinkautoJSSafeStringPart(parts, 7);
        res[@"hasBGRA"] = @([TLinkautoJSSafeStringPart(parts, 8) intValue] != 0);
        res[@"hasGray"] = @([TLinkautoJSSafeStringPart(parts, 9) intValue] != 0);
        res[@"createdAtMs"] = @([TLinkautoJSSafeStringPart(parts, 10) longLongValue]);
        res[@"captureMs"] = @([TLinkautoJSSafeStringPart(parts, 11) doubleValue]);
        res[@"bgraMs"] = @([TLinkautoJSSafeStringPart(parts, 12) doubleValue]);
        res[@"grayMs"] = @([TLinkautoJSSafeStringPart(parts, 13) doubleValue]);
        if ([parts count] > 14) res[@"totalMs"] = @([TLinkautoJSSafeStringPart(parts, 14) doubleValue]);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
