NSDictionary *TLinkAXElementAtPoint(pid_t pid, NSString *bundleID, CGPoint point)
{
    if (pid <= 0 || !isfinite(point.x) || !isfinite(point.y)) {
        return TLinkAXError(@"ui_hit_test_invalid_request", @{@"pid": @(pid)});
    }
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        NSDictionary *lockState = TLinkAXLockState();
        if ([lockState[@"screen_off"] boolValue]) {
            result = TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if ([lockState[@"locked"] boolValue]) {
            result = TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if (!TLinkAXPrepare() || !sTLinkAXHitTest) {
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
            root = sTLinkAXCreateApp(pid);
            if (!root) {
                result = TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
                return;
            }
            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, 0.5f);
            int error = sTLinkAXHitTest(root, &hit, (float)point.x, (float)point.y);
            CFRelease(root);
            root = NULL;
            if (error != 0 || !hit) {
                if (hit) CFRelease(hit);
                result = TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid), @"ax_error": @(error)});
                return;
            }
            NSDictionary *element = TLinkAXSerializeElement(hit, screen, 0);
            CFRelease(hit);
            hit = NULL;
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
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        }
    });
    return result ?: TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid)});
}
