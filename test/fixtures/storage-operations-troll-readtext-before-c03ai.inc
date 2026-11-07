    device[@"readText"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSError *readErr = nil;
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&readErr];
        if (!text) {
            NSString *message = readErr.localizedDescription ?: @"read_failed";
            return @{@"ok": @NO, @"error": message, @"path": path};
        }
        return @{@"ok": @YES, @"path": path, @"text": text};
    };
