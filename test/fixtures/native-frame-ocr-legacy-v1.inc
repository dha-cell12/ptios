// Frozen pre-C02b14 ocrFrame bridge at 4a3b0d4.
    else if ([method isEqualToString:TLinkJSNativeMethodOcrFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if ([context.cancellationToken isCancelled]) return [TLinkJSNativeResponse responseWithError:@"JavaScript execution was aborted" code:@-1];
        if (frameId <= 0) return [TLinkJSNativeResponse responseWithError:@"ocrFrame(frameId, options) requires a positive frame id" code:@-1];
        double x = TLinkautoJSDoubleOption(options, @"x", 0), y = TLinkautoJSDoubleOption(options, @"y", 0), width = TLinkautoJSDoubleOption(options, @"width", 0), height = TLinkautoJSDoubleOption(options, @"height", 0);
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) return [TLinkJSNativeResponse responseWithError:@"ocrFrame options require finite x/y/width/height" code:@-1];
        NSString *lang = TLinkautoJSStringOption(options, @"lang", @"vie");
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(lang) || !TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"ocrFrame lang/coord contains unsupported protocol delimiter" code:@-1];
        NSString *payload = [NSString stringWithFormat:@"%d;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%d;;%@;;%d;;%d;;%@;;%d", frameId, x, y, width, height, lang, TLinkautoJSIntOption(options, @"oem", 1), TLinkautoJSIntOption(options, @"psm", 7), TLinkautoJSBase64Encode(TLinkautoJSStringOption(options, @"whitelist", @"")), TLinkautoJSIntOption(options, @"scaleUp", 2), TLinkautoJSIntOption(options, @"thresholdMode", 0), coord, TLinkautoJSIntOption(options, @"maxAgeMs", 1000)];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_OCR_TESSERACT_REGION, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:TLinkautoJSOCRResultByAddingDecodedError(result)];
        if ([parts count] < 7) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"text": TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 1)), @"confidence": @([TLinkautoJSSafeStringPart(parts, 2) doubleValue]), @"ageMs": @([TLinkautoJSSafeStringPart(parts, 3) longLongValue]), @"ocrMs": @([TLinkautoJSSafeStringPart(parts, 4) doubleValue]), @"preprocessMs": @([TLinkautoJSSafeStringPart(parts, 5) doubleValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 6) doubleValue])})];
    }
