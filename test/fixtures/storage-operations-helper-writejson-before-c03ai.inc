- (NSDictionary *)writeJSONValue:(id)value atRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    self.storageOpsCount++;
    id object = [value isKindOfClass:[JSValue class]] ? [(JSValue *)value toObject] : value;
    if ([object isKindOfClass:[NSNull class]]) object = nil;
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) return @{ @"ok": @NO, @"error": @"writeJSON(path, value) requires a JSON-serializable object or array" };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&err];
    if (!data) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to encode JSON" };
    if ([data length] > kTLinkJSHelperMaxStorageFileBytes) return @{ @"ok": @NO, @"error": @"JSON is too large" };
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    return [self writeText:text atRelativePath:relativePath bundlePath:bundlePath];
}

