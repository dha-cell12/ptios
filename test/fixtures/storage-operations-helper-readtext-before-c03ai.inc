- (NSDictionary *)readTextAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:NO createParent:NO];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return @{ @"ok": @NO, @"error": @"file not found", @"path": path ?: @"" };
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"file is too large", @"path": path ?: @"" };
    NSError *err = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (!text) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to read file", @"path": path ?: @"" };
    return @{ @"ok": @YES, @"path": path ?: @"", @"text": text ?: @"" };
}

