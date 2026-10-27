// Frozen b2ac272 app PID compatibility oracle.
NSString* appPidFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }
    pid_t pid = zx_pidForBundleId(bundleId);
    return [NSString stringWithFormat:@"%d", pid];
}

