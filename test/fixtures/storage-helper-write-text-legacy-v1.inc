// Frozen production writeText from adaf252c.
- (NSDictionary *)writeText:(NSString *)text atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *resolved = [self bundleStoragePathForRelativePath:relativePath bundlePath:bundlePath writing:YES createParent:YES];
    if (![resolved[@"ok"] boolValue]) return resolved;
    NSString *path = resolved[@"path"];
    NSString *safeText = [text isKindOfClass:[NSString class]] ? text : [text description];
    safeText = safeText ?: @"";
    NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];
    if ([data length] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"text is too large", @"path": path ?: @"" };
    NSError *err = nil;
    BOOL ok = [safeText writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to write file", @"path": path ?: @"" };
    return @{ @"ok": @YES, @"path": path ?: @"", @"bytes": @([data length]) };
}

