// Frozen pre-C02b13 findImageInFrame bridge at 404af5a.
    else if ([method isEqualToString:TLinkJSNativeMethodFindImageInFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        int imageId = [args count] > 1 ? [[args objectAtIndex:1] intValue] : 0;
        NSDictionary *options = [args count] > 2 ? [args objectAtIndex:2] : @{};
        if (frameId <= 0 || imageId <= 0) return [TLinkJSNativeResponse responseWithError:@"findImageInFrame(frameId, imageId, options) requires positive ids" code:@-1];
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        NSString *payload = [NSString stringWithFormat:@"%d;;%d;;%.0f;;%.0f;;%.0f;;%.0f;;%.4f;;%.4f;;%.4f;;%.4f;;%d;;%@;;%d", frameId, imageId, TLinkautoJSDoubleOption(options, @"x", 0), TLinkautoJSDoubleOption(options, @"y", 0), TLinkautoJSDoubleOption(options, @"width", 0), TLinkautoJSDoubleOption(options, @"height", 0), TLinkautoJSDoubleOption(options, @"acceptable", 0.95), TLinkautoJSDoubleOption(options, @"scaleMin", 1.0), TLinkautoJSDoubleOption(options, @"scaleMax", 1.0), TLinkautoJSDoubleOption(options, @"scaleStep", 1.0), TLinkautoJSIntOption(options, @"pixelSkip", 0), coord, TLinkautoJSIntOption(options, @"maxAgeMs", 1000)];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_FIND_IMAGE_IN_FRAME, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 11) return [TLinkJSNativeResponse responseWithValue:result];
        int matchX = [TLinkautoJSSafeStringPart(parts, 1) intValue], matchY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"matched": @(matchX >= 0 && matchY >= 0), @"x": @(matchX), @"y": @(matchY), @"width": @([TLinkautoJSSafeStringPart(parts, 3) intValue]), @"height": @([TLinkautoJSSafeStringPart(parts, 4) intValue]), @"centerX": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]), @"centerY": @([TLinkautoJSSafeStringPart(parts, 6) doubleValue]), @"score": @([TLinkautoJSSafeStringPart(parts, 7) doubleValue]), @"ageMs": @([TLinkautoJSSafeStringPart(parts, 8) longLongValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 9) doubleValue])})];
    }
