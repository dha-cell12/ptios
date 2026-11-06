NSDictionary *TLinkAXElementAtPoint(pid_t pid, NSString *bundleID, CGPoint point)
{
    if (pid <= 0 || !isfinite(point.x) || !isfinite(point.y)) {
        return TLinkAXError(@"ui_hit_test_invalid_request", @{@"pid": @(pid)});
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        NSDictionary *lockState = TLinkAXLockState();
        if (TLinkNativeStopped()) {
            result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
            return;
        }
        if ([lockState[@"screen_off"] boolValue]) {
            result = TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if ([lockState[@"locked"] boolValue]) {
            result = TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        BOOL prepared = TLinkAXPrepare();
        if (TLinkNativeStopped()) {
            result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
            return;
        }
        if (!prepared || !sTLinkAXHitTest) {
            result = TLinkAXError(@"ui_hit_test_unavailable", @{@"pid": @(pid)});
            return;
        }
        CGRect screen = [UIScreen mainScreen].bounds;
        if (!CGRectContainsPoint(screen, point)) {
            result = TLinkAXError(@"ui_point_out_of_bounds", @{@"pid": @(pid)});
            return;
        }
        TLinkAXElementRef root = NULL;
        TLinkAXElementRef hit = NULL;
        @try {
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            root = sTLinkAXCreateApp(pid);
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (!root) {
                result = TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
                return;
            }
            auto budget = TLinkCurrentNativeBudget();
            double timeout = budget ? budget->remainingSeconds(0.5) : 0.5;
            if (timeout <= 0 || TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, (float)timeout);
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            int error = sTLinkAXHitTest(root, &hit, (float)point.x, (float)point.y);
            CFRelease(root);
            root = NULL;
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (error != 0 || !hit) {
                result = TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid), @"ax_error": @(error)});
                return;
            }
            NSDictionary *element = TLinkAXSerializeElement(hit, screen, 0);
            CFRelease(hit);
            hit = NULL;
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            result = @{
                @"ok": @YES,
                @"schema": @"ui_hit_test_v1",
                @"source": TLinkAXBackendName,
                @"bundle_id": bundleID ?: @"",
                @"pid": @(pid),
                @"point": @{@"x": @(point.x), @"y": @(point.y)},
                @"coordinate_space": @"points",
                @"element": element ?: @{},
                @"found": @(element != nil),
                @"context_changed": @NO,
            };
        } @catch (__unused NSException *exception) {
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        } @finally {
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
        }
    });
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
    return result ?: TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid)});
}
