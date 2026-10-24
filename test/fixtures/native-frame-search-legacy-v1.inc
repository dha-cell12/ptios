// Frozen C02b6 JS branch, baseline 650a4f4; change only for an intentional wire-contract migration.
    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindColor]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if (frameId <= 0) return [TLinkJSNativeResponse responseWithError:@"frameFindColor(frameId, options) requires a positive frame id" code:@-1];
        double x = TLinkautoJSDoubleOption(options, @"x", 0), y = TLinkautoJSDoubleOption(options, @"y", 0), width = TLinkautoJSDoubleOption(options, @"width", 0), height = TLinkautoJSDoubleOption(options, @"height", 0);
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord) || !TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) return [TLinkJSNativeResponse responseWithError:@"frameFindColor options require finite x/y/width/height and valid coord" code:@-1];
        NSString *payload = [NSString stringWithFormat:@"%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;%@;;%d", frameId, x, y, width, height, TLinkautoJSIntOption(options, @"redMin", TLinkautoJSIntOption(options, @"rMin", 0)), TLinkautoJSIntOption(options, @"redMax", TLinkautoJSIntOption(options, @"rMax", 255)), TLinkautoJSIntOption(options, @"greenMin", TLinkautoJSIntOption(options, @"gMin", 0)), TLinkautoJSIntOption(options, @"greenMax", TLinkautoJSIntOption(options, @"gMax", 255)), TLinkautoJSIntOption(options, @"blueMin", TLinkautoJSIntOption(options, @"bMin", 0)), TLinkautoJSIntOption(options, @"blueMax", TLinkautoJSIntOption(options, @"bMax", 255)), TLinkautoJSIntOption(options, @"skip", 0), coord, TLinkautoJSIntOption(options, @"maxAgeMs", 1000)];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_IN_FRAME, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 9) return [TLinkJSNativeResponse responseWithValue:result];
        int foundX = [TLinkautoJSSafeStringPart(parts, 1) intValue], foundY = [TLinkautoJSSafeStringPart(parts, 2) intValue];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"matched": @(foundX >= 0 && foundY >= 0), @"x": @(foundX), @"y": @(foundY), @"red": @([TLinkautoJSSafeStringPart(parts, 3) intValue]), @"green": @([TLinkautoJSSafeStringPart(parts, 4) intValue]), @"blue": @([TLinkautoJSSafeStringPart(parts, 5) intValue]), @"ageMs": @([TLinkautoJSSafeStringPart(parts, 6) longLongValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 7) doubleValue])})];
    }
