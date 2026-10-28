// Frozen from 64a6458; compatibility oracle.
static bool zx_handleNativeBatch(UInt8 *eventData, NSError **err)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw || raw.length == 0) {
        if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Native batch format: command||command, command starts with 10/62/63/64.\r\n"}];
        return false;
    }

    NSArray<NSString *> *commands = [raw componentsSeparatedByString:@"||"];
    TLinkRawTouches ownedTouches;
    bool completed = false;
    @try {
    for (NSString *cmd in commands) {
        if (!zx_nativeContinue(err)) return false;
        if (cmd.length < 2) continue;
        int task = [[cmd substringToIndex:2] intValue];
        NSString *payload = [cmd substringFromIndex:2];
        UInt8 *payloadBytes = (UInt8 *)[payload UTF8String];
        if (task == TASK_PERFORM_TOUCH) {
            if (!performTouchFromRawData(payloadBytes, [payload lengthOfBytesUsingEncoding:NSUTF8StringEncoding])) {
                if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"1;;touch_bad_payload\r\n"}];
                return false;
            }
            ownedTouches.observe(payloadBytes, [payload lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
        } else if (task == TASK_NATIVE_TAP) {
            if (!zx_handleNativeTap(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_SWIPE) {
            if (!zx_handleNativeSwipe(payloadBytes, err)) return false;
        } else if (task == TASK_NATIVE_GESTURE) {
            if (!zx_handleNativeGesture(payloadBytes, err)) return false;
        } else {
            if (err) *err = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported batch task: %d\r\n", task]}];
            return false;
        }
    }
    if (!zx_nativeContinue(err)) return false;
    completed = true;
    return true;
    } @finally {
        if (!completed) ownedTouches.release([](const uint8_t *bytes, size_t length) { return performTouchFromRawData(bytes, length); });
    }
}

