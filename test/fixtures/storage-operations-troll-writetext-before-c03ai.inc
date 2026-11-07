    device[@"writeText"] = ^NSDictionary *(NSString *relativePath, NSString *text) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *writeErr = nil;
        NSString *safeText = text ?: @"";
        BOOL ok = [safeText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        NSUInteger byteCount = [safeText lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        return ok ? @{@"ok": @YES, @"path": path, @"bytes": @(byteCount)} : @{@"ok": @NO, @"path": path, @"error": writeErr.localizedDescription ?: @"write_failed"};
    };
