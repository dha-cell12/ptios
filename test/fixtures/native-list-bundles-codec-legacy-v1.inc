// Frozen from 892d8de; direct listBundles branch before metadata codec change.
    else if ([method isEqualToString:TLinkJSNativeMethodListBundles]) {
        BOOL withInfo = [args count] > 0 ? [[args objectAtIndex:0] boolValue] : NO;
        NSDictionary *result = TLinkExecuteNativeListBundles(withInfo,context);
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        if (withInfo) {
            NSString *json = TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 1));
            NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
            id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSArray *items = [obj isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)obj)[@"items"] : @[];
            return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"items": [items isKindOfClass:[NSArray class]] ? items : @[]})];
        }
        NSString *raw = TLinkautoJSSafeStringPart(parts, 1);
        NSArray *bundleIds = [raw length] > 0 ? [raw componentsSeparatedByString:@",,"] : @[];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"bundleIds": bundleIds})];
    }
