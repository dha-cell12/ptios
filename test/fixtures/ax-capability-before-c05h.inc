NSDictionary *TLinkAXCapabilitySnapshot(void)
{
    BOOL prepared = TLinkAXPrepare();
    NSDictionary *lockState = TLinkAXLockState();
    NSDictionary *foreground = TLinkAXCopyFrontmostContext();
    NSArray<NSString *> *names = @[
        @"com.apple.private.accessibility.inspection",
        @"com.apple.accessibility.api",
        @"com.apple.private.accessibility.look-me-up-setup",
    ];
    NSMutableDictionary *entitlements = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        id value = TLinkAXEntitlementValue(name);
        entitlements[name] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
    }
    return @{
        @"ok": @(prepared),
        @"schema": @"ui_tree_capability_v1",
        @"source": TLinkAXBackendName,
        @"state": prepared ? @"ready" : @"unavailable",
        @"flat_snapshot": @YES,
        @"hierarchy": @NO,
        @"framework_loaded": @(sTLinkAXFrameworkLoaded),
        @"accessibility_library_loaded": @(sTLinkAccessibilityLibraryLoaded),
        @"create_app_symbol": @(sTLinkAXCreateApp != NULL),
        @"copy_attribute_symbol": @(sTLinkAXCopyAttribute != NULL),
        @"set_timeout_symbol": @(sTLinkAXSetTimeout != NULL),
        @"value_get_symbol": @(sTLinkAXValueGetValue != NULL),
        @"hit_test_symbol": @(sTLinkAXHitTest != NULL),
        @"enable_symbol": @(sTLinkAXEnableSymbol),
        @"automation_symbol": @(sTLinkAXAutomationSymbol),
        @"requesting_client_symbol": @(sTLinkAXRequestingClientSymbol),
        @"override_client_symbol": @(sTLinkAXOverrideClientSymbol),
        @"foreground_probe": @{
            @"ok": @([foreground[@"ok"] boolValue]),
            @"bundle_id": foreground[@"bundle_id"] ?: @"",
            @"pid": foreground[@"pid"] ?: @0,
            @"source": foreground[@"source"] ?: @"",
            @"error": foreground[@"error"] ?: @"",
            @"diagnostic": foreground[@"diagnostic"] ?: @"",
            @"direct_error": foreground[@"direct_error"] ?: @"",
        },
        @"entitlements": entitlements,
        @"lock_state": lockState,
        @"default_max_elements": @250,
        @"hard_max_elements": @1000,
        @"default_max_scanned_elements": @(kTLinkAXDefaultMaxScannedElements),
        @"hard_max_scanned_elements": @(kTLinkAXHardMaxScannedElements),
        @"default_timeout_ms": @1500,
    };
}

