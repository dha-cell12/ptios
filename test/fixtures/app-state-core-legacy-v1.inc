// Frozen dfde59c app state compatibility oracle.
NSString* appStateFromRawData(UInt8 *eventData, NSError **error)
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
    if (!app)
    {
        return @"0";
    }

    SEL processStateSelector = NSSelectorFromString(@"processState");
    if ([app respondsToSelector:processStateSelector])
    {
        NSInteger state = ((NSInteger (*)(id, SEL))objc_msgSend)(app, processStateSelector);
        return [NSString stringWithFormat:@"%ld", (long)state];
    }

    SEL isRunningSelector = NSSelectorFromString(@"isRunning");
    if ([app respondsToSelector:isRunningSelector])
    {
        BOOL isRunning = ((BOOL (*)(id, SEL))objc_msgSend)(app, isRunningSelector);
        return isRunning ? @"1" : @"0";
    }

    return @"-1";
}

