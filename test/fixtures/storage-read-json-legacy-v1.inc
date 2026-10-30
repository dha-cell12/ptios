// Frozen production readJSON from 54991dd3.
    else if ([method isEqualToString:TLinkJSNativeMethodReadJSON]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        TLinkJSNativeRequest *subReq = [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodReadText arguments:@[path]];
        TLinkJSNativeResponse *subRes = [self executeRequest:subReq context:context error:error];
        if (!subRes.ok) return subRes;
        NSDictionary *textResult = subRes.value;
        if (![textResult[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:textResult];
        NSData *data = [textResult[@"text"] dataUsingEncoding:NSUTF8StringEncoding];
        NSError *err = nil;
        id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
        if (!value) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to parse JSON", @"path": textResult[@"path"] ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": textResult[@"path"] ?: @"", @"value": value }];
    }
