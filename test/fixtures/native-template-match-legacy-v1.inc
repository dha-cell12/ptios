// Frozen from 6aa9104; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodMatchTemplate]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        if ([path length] == 0 || [path rangeOfString:@";;"].location != NSNotFound || [path rangeOfString:@"\r"].location != NSNotFound || [path rangeOfString:@"\n"].location != NSNotFound) {
            return [TLinkJSNativeResponse responseWithError:@"matchTemplate(path, options) requires a valid template path" code:@-1];
        }
        int maxTryTimes = [options[@"maxTryTimes"] respondsToSelector:@selector(intValue)] ? [options[@"maxTryTimes"] intValue] : 2;
        double acceptable = [options[@"acceptable"] respondsToSelector:@selector(doubleValue)] ? [options[@"acceptable"] doubleValue] : 0.8;
        double scaleRatio = [options[@"scaleRatio"] respondsToSelector:@selector(doubleValue)] ? [options[@"scaleRatio"] doubleValue] : 0.8;
        NSString *payload = [NSString stringWithFormat:@"%@;;%d;;%.4f;;%.4f", path, maxTryTimes, acceptable, scaleRatio];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_TEMPLATE_MATCH, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 5) return [TLinkJSNativeResponse responseWithValue:result];
        double x = [parts[1] doubleValue];
        double y = [parts[2] doubleValue];
        double width = [parts[3] doubleValue];
        double height = [parts[4] doubleValue];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"matched"] = @(width > 0 && height > 0);
        res[@"x"] = @(x);
        res[@"y"] = @(y);
        res[@"width"] = @(width);
        res[@"height"] = @(height);
        res[@"centerX"] = @(x + width / 2.0);
        res[@"centerY"] = @(y + height / 2.0);
        return [TLinkJSNativeResponse responseWithValue:res];
    }
