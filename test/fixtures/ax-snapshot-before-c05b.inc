static NSDictionary *TLinkAXCopySnapshotUnlocked(pid_t pid,
                                                 NSString *bundleID,
                                                 NSDictionary *options)
{
    if (pid <= 0) return TLinkAXError(@"ui_invalid_pid", @{@"pid": @(pid)});
    NSDictionary *lockState = TLinkAXLockState();
    BOOL allowLocked = [options[@"allow_locked"] boolValue];
    if (!allowLocked && [lockState[@"screen_off"] boolValue]) {
        return TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
    }
    if (!allowLocked && [lockState[@"locked"] boolValue]) {
        return TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
    }
    if (!TLinkAXPrepare()) return TLinkAXError(@"ui_axruntime_unavailable", @{@"pid": @(pid)});

    id maxElementsValue = options[@"max_elements"] ?: options[@"maxElements"];
    id timeoutValue = options[@"timeout_ms"] ?: options[@"timeoutMs"];
    id visibleValue = options[@"visible_only"] ?: options[@"visibleOnly"];
    id clickableValue = options[@"clickable_only"] ?: options[@"clickableOnly"];
    NSInteger maxElements = TLinkAXBoundedInteger(maxElementsValue, 250, 1, 1000);
    NSInteger timeoutMs = TLinkAXBoundedInteger(timeoutValue, 1500, 100, 3000);
    BOOL visibleOnly = visibleValue ? [visibleValue boolValue] : YES;
    BOOL clickableOnly = [clickableValue boolValue];
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime deadline = started + ((double)timeoutMs / 1000.0);

    TLinkAXElementRef root = NULL;
    CFTypeRef rawElements = NULL;
    @try {
        root = sTLinkAXCreateApp(pid);
        if (!root) return TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
        auto nativeBudget = TLinkCurrentNativeBudget();
        double queryTimeout = MIN(0.5f, (float)timeoutMs / 1000.0f);
        if (nativeBudget) queryTimeout = nativeBudget->remainingSeconds(queryTimeout);
        if (TLinkNativeStopped()) { CFRelease(root); root = NULL; return TLinkAXError(@"ui_cancelled_or_timed_out", nil); }
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, (float)queryTimeout);
        int error = sTLinkAXCopyAttribute(root, (CFStringRef)(uintptr_t)3015, &rawElements);
        CFRelease(root);
        root = NULL;
        if (error != 0 || !rawElements || CFGetTypeID(rawElements) != CFArrayGetTypeID()) {
            if (rawElements) CFRelease(rawElements);
            return TLinkAXError(@"ui_element_query_failed", @{@"pid": @(pid), @"ax_error": @(error)});
        }
    } @catch (__unused NSException *exception) {
        if (root) CFRelease(root);
        if (rawElements) CFRelease(rawElements);
        return TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
    }

    NSArray *elements = CFBridgingRelease(rawElements);
    CGRect screen = [UIScreen mainScreen].bounds;
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)maxElements, elements.count)];
    NSUInteger scanned = 0;
    NSUInteger serializationFailures = 0;
    BOOL truncated = NO;
    size_t estimatedJSONBytes = 0;
    for (id object in elements) {
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        if (rows.count >= (NSUInteger)maxElements || CFAbsoluteTimeGetCurrent() >= deadline) {
            truncated = YES;
            break;
        }
        scanned++;
        NSDictionary *node = TLinkAXSerializeElement((__bridge TLinkAXElementRef)object, screen, scanned - 1);
        if (!node) {
            serializationFailures++;
            continue;
        }
        if (visibleOnly && ![node[@"intersects_screen"] boolValue]) continue;
        if (clickableOnly && ![node[@"clickable"] boolValue]) continue;
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        // Conservative escaped-JSON and base64 accounting before retaining another row.
        size_t rowBytes = 768;
        for (NSString *key in @[@"label", @"value", @"identifier", @"role"]) {
            NSString *text = node[key];
            size_t bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (!TLinkNativeOutputAllowed(bytes)) return TLinkAXError(@"ui_response_too_large", @{@"partial": @YES});
            rowBytes += 6 * bytes;
        }
        estimatedJSONBytes += rowBytes;
        if (!TLinkNativeOutputAllowed(32 * 1024 + 4 * ((estimatedJSONBytes + 2) / 3)))
            return TLinkAXError(@"ui_response_too_large", @{@"partial": @YES});
        [rows addObject:node];
    }
    NSTimeInterval durationMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
    return @{
        @"ok": @YES,
        @"schema": TLinkAXSnapshotSchema,
        @"source": TLinkAXBackendName,
        @"bundle_id": bundleID ?: @"",
        @"pid": @(pid),
        @"captured_at_ms": @((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0)),
        @"duration_ms": @((NSInteger)llround(durationMs)),
        @"screen": @{
            @"width": @(screen.size.width), @"height": @(screen.size.height),
            @"scale": @([UIScreen mainScreen].scale),
            @"coordinate_space": @"points",
        },
        @"elements": rows,
        @"count": @(rows.count),
        @"scanned_count": @(scanned),
        @"source_count": @(elements.count),
        @"serialization_failure_count": @(serializationFailures),
        @"truncated": @(truncated || scanned < elements.count),
        @"partial": @(serializationFailures > 0 || truncated || scanned < elements.count),
        @"context_changed": @NO,
        @"lock_state": lockState,
    };
}

