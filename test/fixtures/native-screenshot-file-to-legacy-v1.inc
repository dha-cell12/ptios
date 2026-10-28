// Frozen from e782771; compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodScreenshotTo]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *targetPath = ([path isKindOfClass:[NSString class]] && [path length] > 0) ? path : @"/var/mobile/Media/DCIM/100APPLE/screenshot.png";
        if ([targetPath rangeOfString:@";;"].location != NSNotFound || [targetPath rangeOfString:@"\r"].location != NSNotFound || [targetPath rangeOfString:@"\n"].location != NSNotFound) {
            return [TLinkJSNativeResponse responseWithError:@"screenshot path contains unsupported protocol delimiter" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%@", TASK_SCREENSHOT, targetPath] context:context];
        NSArray *parts = result[@"parts"];
        NSString *resultPath = [parts count] >= 2 ? parts[1] : targetPath;
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"path"] = resultPath ?: @"";
        return [TLinkJSNativeResponse responseWithValue:res];
    }
