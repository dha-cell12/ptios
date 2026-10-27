// Frozen aca0719 app info compatibility oracle.
NSString* appInfoFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    NSString *name = proxy.localizedName ?: @"";
    NSString *shortVersion = proxy.shortVersionString ?: @"";
    NSString *bundleVersion = proxy.bundleVersion ?: @"";
    NSString *state = appStateFromRawData(eventData, nil) ?: @"-1";

    return [NSString stringWithFormat:@"%@;;%@;;%@;;%@;;%@", bundleId, name, shortVersion, bundleVersion, state];
}

