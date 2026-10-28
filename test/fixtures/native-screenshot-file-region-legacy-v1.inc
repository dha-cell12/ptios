// Frozen from e782771; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodScreenshotRegion]) {
        NSString *targetPath = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if (TLinkautoJSStringContainsAny(targetPath, @[@";;", @"\r", @"\n"])) {
            return [TLinkJSNativeResponse responseWithError:@"screenshot path contains unsupported protocol delimiter" code:@-1];
        }
        double x = TLinkautoJSDoubleOption(options, @"x", 0);
        double y = TLinkautoJSDoubleOption(options, @"y", 0);
        double width = TLinkautoJSDoubleOption(options, @"width", 0);
        double height = TLinkautoJSDoubleOption(options, @"height", 0);
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height) || width <= 0 || height <= 0) {
            return [TLinkJSNativeResponse responseWithError:@"screenshotRegion(path, options) requires finite positive width/height" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%@;;%.0f;;%.0f;;%.0f;;%.0f", TASK_SCREENSHOT, targetPath, x, y, width, height] context:context];
        NSArray *parts = result[@"parts"];
        NSString *resultPath = [parts count] >= 2 ? TLinkautoJSSafeStringPart(parts, 1) : targetPath;
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"path": resultPath ?: @"", @"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)})];
    }
