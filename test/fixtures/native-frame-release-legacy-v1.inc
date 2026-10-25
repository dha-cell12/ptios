// Frozen pre-C02b16 JS frame release branches at e9e0b1c.
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseFrame]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : -1;
        if (frameId < 0) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"invalid handle" }];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%d%@", TASK_FRAME_RELEASE, frameId, TLinkautoJSOwnerSuffix(context)] context:context];
        if ([result[@"ok"] boolValue]) [runtime untrackFrameId:frameId];
        return [TLinkJSNativeResponse responseWithValue:result];
    }
    else if ([method isEqualToString:TLinkJSNativeMethodReleaseAllFrames]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02dall", TASK_FRAME_RELEASE] context:context];
        if ([result[@"ok"] boolValue] && [runtime respondsToSelector:@selector(untrackAllFrameIds)]) {
            [(id)runtime untrackAllFrameIds];
        }
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"released": @([TLinkautoJSSafeStringPart(parts, 1) intValue])})];
    }
