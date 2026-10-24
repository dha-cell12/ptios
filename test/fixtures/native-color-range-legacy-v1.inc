// Frozen pre-C02b10 JS findColor branch at 036c2b7.
    else if ([method isEqualToString:TLinkJSNativeMethodFindColor]) {
        NSDictionary *options = [args count] > 0 ? [args objectAtIndex:0] : @{};
        double x = [options[@"x"] respondsToSelector:@selector(doubleValue)] ? [options[@"x"] doubleValue] : 0;
        double y = [options[@"y"] respondsToSelector:@selector(doubleValue)] ? [options[@"y"] doubleValue] : 0;
        double width = [options[@"width"] respondsToSelector:@selector(doubleValue)] ? [options[@"width"] doubleValue] : 0;
        double height = [options[@"height"] respondsToSelector:@selector(doubleValue)] ? [options[@"height"] doubleValue] : 0;
        int redMin = [options[@"redMin"] respondsToSelector:@selector(intValue)] ? [options[@"redMin"] intValue] : 0;
        int redMax = [options[@"redMax"] respondsToSelector:@selector(intValue)] ? [options[@"redMax"] intValue] : 255;
        int greenMin = [options[@"greenMin"] respondsToSelector:@selector(intValue)] ? [options[@"greenMin"] intValue] : 0;
        int greenMax = [options[@"greenMax"] respondsToSelector:@selector(intValue)] ? [options[@"greenMax"] intValue] : 255;
        int blueMin = [options[@"blueMin"] respondsToSelector:@selector(intValue)] ? [options[@"blueMin"] intValue] : 0;
        int blueMax = [options[@"blueMax"] respondsToSelector:@selector(intValue)] ? [options[@"blueMax"] intValue] : 255;
        int skip = [options[@"skip"] respondsToSelector:@selector(intValue)] ? [options[@"skip"] intValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
            return [TLinkJSNativeResponse responseWithError:@"findColor(options) requires finite x/y/width/height" code:@-1];
        }
        NSString *payload = [NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d",
                             x, y, width, height, redMin, redMax, greenMin, greenMax, blueMin, blueMax, skip];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_SEARCHER, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 6) return [TLinkJSNativeResponse responseWithValue:result];
        int foundX = [parts[1] intValue];
        int foundY = [parts[2] intValue];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"matched"] = @(foundX >= 0 && foundY >= 0);
        res[@"x"] = @(foundX);
        res[@"y"] = @(foundY);
        res[@"red"] = @([parts[3] intValue]);
        res[@"green"] = @([parts[4] intValue]);
        res[@"blue"] = @([parts[5] intValue]);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    
