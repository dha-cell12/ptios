// Frozen de4e01f rootDir/currentDir/botPath JS-to-RAW adapter.
    else if ([method isEqualToString:TLinkJSNativeMethodRootDir] || [method isEqualToString:TLinkJSNativeMethodCurrentDir] || [method isEqualToString:TLinkJSNativeMethodBotPath]) {
        int task = [method isEqualToString:TLinkJSNativeMethodRootDir] ? TASK_ROOT_DIR : ([method isEqualToString:TLinkJSNativeMethodCurrentDir] ? TASK_CURRENT_DIR : TASK_BOT_PATH);
        NSString *key = [method isEqualToString:TLinkJSNativeMethodRootDir] ? @"rootDir" : ([method isEqualToString:TLinkJSNativeMethodCurrentDir] ? @"currentDir" : @"botPath");
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d", task] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        NSString *path = TLinkautoJSSafeStringPart(parts, 1);
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"path": path ?: @"", key: path ?: @""})];
    }
