// Frozen 1e5c795 app kill compatibility oracle.
NSString* killAppFromRawData(UInt8 *eventData, NSError **error)
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

    SBApplication *app = getApplicationForBundleId(bundleId);
    if (!sendTerminationToApp(app))
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to terminate app.\r\n"}];
        }
        return nil;
    }

    return @"";
}

