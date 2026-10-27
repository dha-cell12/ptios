// Frozen df1283d toast compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodToast]) {
        NSString *message = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@";;" withString:@"; "];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        safeMessage = [safeMessage stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        if ([safeMessage length] > 180) safeMessage = [safeMessage substringToIndex:180];
        if ([safeMessage length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"toast(message) requires a non-empty message" code:@-1];
        }
        int type = [options[@"type"] respondsToSelector:@selector(intValue)] ? [options[@"type"] intValue] : 3;
        int duration = [options[@"duration"] respondsToSelector:@selector(intValue)] ? [options[@"duration"] intValue] : 2;
        int position = [options[@"position"] respondsToSelector:@selector(intValue)] ? [options[@"position"] intValue] : 0;
        int fontSize = [options[@"fontSize"] respondsToSelector:@selector(intValue)] ? [options[@"fontSize"] intValue] : 14;
        if (type < 0 || type > 4) type = 3;
        if (duration <= 0 && type != 0) duration = 2;
        NSString *payload = [NSString stringWithFormat:@"%d;;%@;;%d;;%d;;%d", type, safeMessage, duration, position, fontSize];
        NSDictionary *res = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_SHOW_TOAST, payload] context:context];
        return [TLinkJSNativeResponse responseWithValue:res];
    }
