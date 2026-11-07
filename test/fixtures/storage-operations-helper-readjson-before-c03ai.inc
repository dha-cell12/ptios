- (NSDictionary *)readJSONAtRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    NSDictionary *textResult = [self readTextAtRelativePath:relativePath bundlePath:bundlePath];
    if (![textResult[@"ok"] boolValue]) return textResult;
    NSData *data = TLinkUTF8DataFromString(textResult[@"text"]);
    NSError *err = nil;
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&err] : nil;
    if (!value) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to parse JSON", @"path": textResult[@"path"] ?: @"" };
    return @{ @"ok": @YES, @"path": textResult[@"path"] ?: @"", @"value": value };
}

