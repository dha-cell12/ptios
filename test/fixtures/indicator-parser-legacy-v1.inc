// Frozen acc8648 indicator compatibility oracle.
void handleTouchIndicatorTaskWithRawData(UInt8 *eventData, NSError **error)
{
    NSString *raw = eventData ? [NSString stringWithUTF8String:(const char *)eventData] : nil;
    NSString *action = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([action isEqualToString:@"0"]) {
        stopTouchIndicator(error);
    } else if ([action isEqualToString:@"1"]) {
        startTouchIndicator(error);
    } else if ([action isEqualToString:@"2"]) {
        __block NSError *result = nil;
        zx_indicatorPerformOnMain(^{
            if (indicatorState != TLinkIndicatorRunning) {
                result = zx_indicatorError(@"Cannot reload configuration while the touch indicator is stopped.");
                return;
            }
            TLinkIndicatorColor color;
            result = zx_indicatorLoadColor(YES, &color);
            if (!result) [touchIndicatorWindow setIndicatorColorWithRed:color.red green:color.green blue:color.blue alpha:color.alpha];
        });
        if (error) *error = result;
    } else {
        if (error) *error = zx_indicatorError(@"Unknown touch indicator action; expected 0, 1 or 2.");
    }
}

