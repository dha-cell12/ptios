// Frozen a97c1b0 screenshot album compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodSaveScreenshotToAlbum]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(path)) return [TLinkJSNativeResponse responseWithError:@"saveScreenshotToAlbum(path) requires a valid path" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%@", TASK_SCREENSHOT, path] context:context]];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodClearScreenshotAlbum]) {
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d3", TASK_SCREENSHOT] context:context]];
    }
