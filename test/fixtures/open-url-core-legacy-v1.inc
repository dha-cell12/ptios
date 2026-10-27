// Frozen 5d4c67a openUrl compatibility oracle.
NSString* openUrlFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *raw = [NSString stringWithFormat:@"%s", eventData ?: (UInt8*)""];
    if ([raw length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing URL.\r\n"}];
        }
        return nil;
    }

    // Settings URLs: modern iOS commonly uses "App-Prefs:" instead of "prefs:".
    NSString *primary = raw;
    NSString *fallback = nil;
    if ([[raw lowercaseString] hasPrefix:@"prefs:"]) {
        fallback = [@"App-Prefs:" stringByAppendingString:[raw substringFromIndex:6]];
    }

    NSURL *url = [NSURL URLWithString:primary];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid URL.\r\n"}];
        }
        return nil;
    }

    __block BOOL started = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            started = YES;
            [app openURL:url options:@{} completionHandler:^(__unused BOOL success) {
                // Do not block waiting for completion; some handlers call back late.
            }];
        } else {
            started = [app openURL:url];
        }

        if (!started && fallback) {
            NSURL *u2 = [NSURL URLWithString:fallback];
            if (u2) {
                if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
                    started = YES;
                    [app openURL:u2 options:@{} completionHandler:^(__unused BOOL success) {}];
                } else {
                    started = [app openURL:u2];
                }
            }
        }
    });

    if (!started) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to open URL.\r\n"}];
        }
        return nil;
    }
    return @"";
}
