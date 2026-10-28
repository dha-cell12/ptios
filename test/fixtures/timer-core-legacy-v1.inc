// Frozen 5025221 timer compatibility oracle.
NSString* setTimerFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *payload = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    NSArray *data = [payload componentsSeparatedByString:@";;"];
    if (data.count < 4) {
        if (error) *error = schedulerError(@"Timer requires name, interval, repeat, script.");
        return nil;
    }
    NSString *name = data[0];
    NSString *script = data[3];
    BOOL repeat = [data[2] intValue] != 0;
    double interval = 0;
    NSScanner *scanner = [NSScanner scannerWithString:data[1]];
    uint64_t intervalNs = 0;
    if (![scanner scanDouble:&interval] || !scanner.isAtEnd ||
        !TLinkSchedulerInterval(interval, repeat, &intervalNs)) {
        if (error) *error = schedulerError(@"Timer interval must be finite and positive; repeating timers require at least 1 second.");
        return nil;
    }
    if (name.length == 0 || script.length == 0) {
        if (error) *error = schedulerError(@"Timer name and script are required.");
        return nil;
    }
    const std::string timerName(name.UTF8String);
    __block NSError *result = nil;
    schedulerPerformSync(^{
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, schedulerQueue());
        if (!source) { result = schedulerError(@"Unable to create timer."); return; }
        const uint64_t generation = timerRegistry.set(timerName, TLinkSchedulerTimer{source, script}, repeat);
        if (generation == 0) {
            dispatch_source_cancel(source);
            dispatch_resume(source); // Balance the initial suspension even on setup failure.
            result = schedulerError(@"Timer generation exhausted.");
            return;
        }
        dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, (int64_t)intervalNs),
                                  repeat ? intervalNs : DISPATCH_TIME_FOREVER, TLinkSchedulerLeeway(intervalNs));
        dispatch_source_set_event_handler(source, ^{
            @autoreleasepool { schedulerTimerFired(timerName, generation); }
        });
        dispatch_resume(source);
    });
    if (error) *error = result;
    return result ? nil : @"";
}

NSString* removeTimerFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *name = eventData ? [NSString stringWithUTF8String:(char*)eventData] : nil;
    if (name.length == 0) {
        if (error) *error = schedulerError(@"Timer name is required.");
        return nil;
    }
    const std::string timerName(name.UTF8String);
    schedulerPerformSync(^{ timerRegistry.remove(timerName); });
    if (error) *error = nil;
    return @"";
}
