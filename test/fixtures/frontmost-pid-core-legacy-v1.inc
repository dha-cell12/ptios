// Frozen e5a4acb frontmost PID compatibility oracle.
NSString* frontMostPidFromRawData(UInt8 *eventData, NSError **error)
{
    (void)eventData;
    NSString *bid = frontMostAppId();
    pid_t pid = zx_pidForBundleId(bid);
    return [NSString stringWithFormat:@"%d", pid];
}

