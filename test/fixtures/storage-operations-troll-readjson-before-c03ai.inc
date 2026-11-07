    device[@"readJSON"] = ^NSDictionary *(NSString *relativePath) {
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, NO, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0) return @{@"ok": @NO, @"path": path, @"error": @"read_failed"};
        NSError *jsonErr = nil;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (!object) return @{@"ok": @NO, @"path": path, @"error": jsonErr.localizedDescription ?: @"json_parse_failed"};
        return @{@"ok": @YES, @"path": path, @"value": object};
    };
