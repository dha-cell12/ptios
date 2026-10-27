// Frozen 1e5c795 app open compatibility oracle (unchanged in C02b33).
int switchProcessForegroundFromRawData(UInt8 *eventData)
{
    return bringAppForeground([NSString stringWithFormat:@"%s", eventData]);
}

int bringAppForeground(NSString *appIdentifier)
{
    BOOL isMainThread = [NSThread isMainThread];
    if (isMainThread) {
        NSLog(@"### com.tlinkauto.springboard: WARNING: bringAppForeground called on main thread for %@", appIdentifier);
    }
    
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    CFStringRef appBundleName = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@"), appIdentifier);
    //[NSString stringWithFormat:@"%s", eventData];
    NSLog(@"### com.tlinkauto.springboard: Switch to application: %@", appBundleName);
    if (!openApp)
        openApp = (int(*)(CFStringRef, Boolean))dlsym(sbServices,"SBSLaunchApplicationWithIdentifier");

    int result = openApp(appBundleName, false);
    
    CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - start;
    if (duration > 0.1) {
        NSLog(@"### com.tlinkauto.springboard: WARNING: bringAppForeground took %.2fms", duration * 1000.0);
    }
    
    return result;
}

