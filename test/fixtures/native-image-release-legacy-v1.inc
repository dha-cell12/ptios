// Frozen pre-C02b17 JS releaseImage branch at d2c9343.
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseImage]) {
        int imageId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (imageId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d3;;%d%@", TASK_IMAGE_OBJECT, imageId, TLinkautoJSOwnerSuffix(context)] context:context];
        if ([result[@"ok"] boolValue]) [runtime untrackImageId:imageId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
