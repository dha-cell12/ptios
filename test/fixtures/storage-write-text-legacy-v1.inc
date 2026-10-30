// Frozen writeText branch from adaf252c; preserve writer/path/error/byte result contract.
    else if ([method isEqualToString:TLinkJSNativeMethodWriteText]) {
        NSString *path = [args count] > 0 ? [args objectAtIndex:0] : @"";
        NSString *text = [args count] > 1 ? [args objectAtIndex:1] : @"";
        NSString *resolvedPath = nil;
        NSDictionary *resolved = [runtime bundleStoragePathForRelativePath:path createParent:YES];
        if (![resolved[@"ok"] boolValue]) return [TLinkJSNativeResponse responseWithValue:resolved];
        resolvedPath = resolved[@"path"];
        if (!resolvedPath) return [TLinkJSNativeResponse responseWithError:@"context runtime missing for path resolution" code:@-1];
        
        NSString *safeText = [text isKindOfClass:[NSString class]] ? text : [text description];
        safeText = safeText ?: @"";
        NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];
        if ([data length] > kTLinkautoJSMaxStorageFileBytes) {
            return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": @"text is too large", @"path": resolvedPath ?: @"" }];
        }
        NSError *err = nil;
        BOOL ok = [safeText writeToFile:resolvedPath atomically:YES encoding:NSUTF8StringEncoding error:&err];
        if (!ok) return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to write file", @"path": resolvedPath ?: @"" }];
        return [TLinkJSNativeResponse responseWithValue:@{ @"ok": @YES, @"path": resolvedPath ?: @"", @"bytes": @([data length]) }];
    }
    
