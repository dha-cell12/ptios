    device[@"writeJSON"] = ^NSDictionary *(NSString *relativePath, JSValue *value) {
        id object = [value toObject];
        if (!object || ![NSJSONSerialization isValidJSONObject:object]) {
            return @{@"ok": @NO, @"error": @"invalid_json_object"};
        }
        NSString *err = nil;
        NSString *path = TLinkScriptStoragePath(weakSession, relativePath, YES, &err);
        if (!path) return @{@"ok": @NO, @"error": err ?: @"storage_path_error", @"path": relativePath ?: @""};
        NSString *parent = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *jsonErr = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&jsonErr];
        if (!data) return @{@"ok": @NO, @"path": path, @"error": jsonErr.localizedDescription ?: @"json_encode_failed"};
        BOOL ok = [data writeToFile:path atomically:YES];
        return ok ? @{@"ok": @YES, @"path": path, @"bytes": @(data.length)} : @{@"ok": @NO, @"path": path, @"error": @"write_json_failed"};
    };

