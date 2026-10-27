// Frozen 5d4c67a openUrl compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodOpenUrl]) {
        NSString *url = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if (!TLinkautoJSValidProtocolString(url)) return [TLinkJSNativeResponse responseWithError:@"openUrl(url) requires a valid URL string" code:@-1];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_OPEN_URL, url] context:context]];
    }
