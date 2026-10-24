// Frozen C02b7 JS branch, baseline d6147de; change only for an intentional wire-contract migration.
    else if ([method isEqualToString:TLinkJSNativeMethodFrameIsColors] || [method isEqualToString:TLinkJSNativeMethodFrameFindMultiColor]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSArray *points = [args count] > 1 ? [args objectAtIndex:1] : @[];
        NSDictionary *options = [args count] > 2 ? [args objectAtIndex:2] : @{};
        NSString *table = TLinkautoJSEncodePointColorTable(points);
        if (frameId <= 0 || !table) return [TLinkJSNativeResponse responseWithError:@"frame color method requires a frame id and point colors" code:@-1];
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
        if ([method isEqualToString:TLinkJSNativeMethodFrameIsColors]) {
            NSString *payload = [NSString stringWithFormat:@"%d;;is_colors;;%@;;%d;;%.4f;;%@;;%d", frameId, table, TLinkautoJSIntOption(options, @"mode", 1), TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0)), coord, maxAgeMs];
            NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_IN_FRAME, payload] context:context];
            NSArray *parts = result[@"parts"];
            if (![result[@"ok"] boolValue] || [parts count] < 5) return [TLinkJSNativeResponse responseWithValue:result];
            BOOL matched = [TLinkautoJSSafeStringPart(parts, 1) intValue] != 0;
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"matched": @(matched), @"value": @(matched), @"ageMs": @([TLinkautoJSSafeStringPart(parts, 2) longLongValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 3) doubleValue])})];
        }
        double x = TLinkautoJSDoubleOption(options, @"x", 0), y = TLinkautoJSDoubleOption(options, @"y", 0), width = TLinkautoJSDoubleOption(options, @"width", 0), height = TLinkautoJSDoubleOption(options, @"height", 0);
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) return [TLinkJSNativeResponse responseWithError:@"frameFindMultiColor options require finite x/y/width/height" code:@-1];
        NSString *payload = [NSString stringWithFormat:@"%d;;find_multi_point;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d;;%@;;%d", frameId, x, y, width, height, table, TLinkautoJSIntOption(options, @"mode", 1), TLinkautoJSDoubleOption(options, @"value", TLinkautoJSDoubleOption(options, @"tolerance", 0)), TLinkautoJSIntOption(options, @"skip", 0), coord, maxAgeMs];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_IN_FRAME, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
        int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue], foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY), @"ageMs": @([TLinkautoJSSafeStringPart(parts, 3) longLongValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 4) doubleValue])})];
    }
