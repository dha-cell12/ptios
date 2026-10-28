// Frozen d16db87 auto-launch compatibility oracle.
static NSString* autoLaunchFilePath(void)
{
    return [getDocumentRoot() stringByAppendingPathComponent:kAutoLaunchFileName];
}

static NSMutableDictionary* loadAutoLaunchConfig(void)
{
    NSString *path = autoLaunchFilePath();
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!config)
    {
        config = [NSMutableDictionary dictionary];
    }
    return config;
}

NSString* setAutoLaunchFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *payload = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    NSArray *data = [payload componentsSeparatedByString:@";;"];
    if ([data count] < 3)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Auto launch requires name, script, enabled.\r\n"}];
        }
        return nil;
    }

    NSString *name = data[0];
    NSString *script = data[1];
    BOOL enabled = [data[2] intValue] != 0;

    NSError *updateError = nil;
    if (!TLinkAutoLaunchSetEntry(autoLaunchFilePath(), name,
                                @{@"script": script, @"enabled": @(enabled)}, &updateError)) {
        if (error) *error = schedulerError(updateError.localizedDescription ?: @"Failed to update auto launch config.");
        return nil;
    }
    if (error) *error = nil;
    return @"";
}

NSString* listAutoLaunch(NSError **error)
{
    NSMutableDictionary *config = loadAutoLaunchConfig();
    NSMutableArray<NSString*> *entries = [NSMutableArray array];
    [config enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *obj, BOOL *stop) {
        if (![obj isKindOfClass:[NSDictionary class]]) return;
        NSString *script = [obj[@"script"] isKindOfClass:[NSString class]] ? obj[@"script"] : @"";
        NSString *enabled = [obj[@"enabled"] respondsToSelector:@selector(boolValue)] && [obj[@"enabled"] boolValue] ? @"1" : @"0";
        [entries addObject:[NSString stringWithFormat:@"%@,,%@,,%@", key, script, enabled]];
    }];
    return [entries componentsJoinedByString:@";;"];
}
