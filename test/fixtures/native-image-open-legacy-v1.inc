// Frozen adf0a93 JS openImage branch before C02b20.
    else if ([method isEqualToString:TLinkJSNativeMethodOpenImage]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        if ([path length] == 0) {
            return [TLinkJSNativeResponse responseWithError:@"openImage(path) requires a valid path" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%@%@", TASK_IMAGE_OBJECT, path, TLinkautoJSOwnerSuffix(context)] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        int imageId = [parts[1] intValue];
        [runtime trackImageId:imageId];
        NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
        res[@"id"] = @(imageId);
        if ([parts count] > 3) {
            res[@"width"] = @([TLinkautoJSSafeStringPart(parts, 2) intValue]);
            res[@"height"] = @([TLinkautoJSSafeStringPart(parts, 3) intValue]);
        }
        return [TLinkJSNativeResponse responseWithValue:res];
    }
    
