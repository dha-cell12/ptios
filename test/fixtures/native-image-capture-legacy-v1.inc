// Frozen 5ffc503 captureImage JS/RAW adapter.
    else if ([method isEqualToString:TLinkJSNativeMethodCaptureImage]) {
        double x = [args count] > 0 ? [[args objectAtIndex:0] doubleValue] : 0;
        double y = [args count] > 1 ? [[args objectAtIndex:1] doubleValue] : 0;
        double width = [args count] > 2 ? [[args objectAtIndex:2] doubleValue] : 0;
        double height = [args count] > 3 ? [[args objectAtIndex:3] doubleValue] : 0;
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
            return [TLinkJSNativeResponse responseWithError:@"captureImage(x, y, width, height) requires finite numbers" code:@-1];
        }
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d1;;%.0f;;%.0f;;%.0f;;%.0f%@", TASK_IMAGE_OBJECT, x, y, width, height, TLinkautoJSOwnerSuffix(context)] context:context];
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
