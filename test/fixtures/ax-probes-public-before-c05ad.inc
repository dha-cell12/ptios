NSDictionary *TLinkAXCopyFrontmostContext(void)
{
    if (TLinkNativeStopped()) return TLinkAXError(TLinkCurrentNativeBudget() && TLinkCurrentNativeBudget()->reason() == TLinkNativeStop::OutputLimit
        ? @"ui_response_too_large" : @"ui_cancelled_or_timed_out", nil);
    NSDictionary *inProcess = TLinkAXSpringBoardProcessContext();
    if (TLinkNativeStopped()) return TLinkAXError(TLinkCurrentNativeBudget() && TLinkCurrentNativeBudget()->reason() == TLinkNativeStop::OutputLimit
        ? @"ui_response_too_large" : @"ui_cancelled_or_timed_out", nil);
    if (inProcess) return inProcess;
    NSDictionary *direct = TLinkAXDirectFrontmostContext();
    if (TLinkNativeStopped()) return TLinkAXError(TLinkCurrentNativeBudget() && TLinkCurrentNativeBudget()->reason() == TLinkNativeStop::OutputLimit
        ? @"ui_response_too_large" : @"ui_cancelled_or_timed_out", nil);
    if (TLinkAXResultSucceeded(direct)) return direct;
    NSString *bundleID = TLinkAXFrontmostBundleID();
    if (TLinkNativeStopped()) return TLinkAXError(TLinkCurrentNativeBudget() && TLinkCurrentNativeBudget()->reason() == TLinkNativeStop::OutputLimit
        ? @"ui_response_too_large" : @"ui_cancelled_or_timed_out", nil);
    if (bundleID.length == 0) {
        return TLinkAXError(@"ui_frontmost_bundle_unavailable", @{
            @"direct_error": direct[@"error"] ?: @"unknown",
            @"diagnostic": direct[@"diagnostic"] ?: @"",
        });
    }
    pid_t pid = TLinkAXPIDForBundleID(bundleID);
    if (TLinkNativeStopped()) return TLinkAXError(TLinkCurrentNativeBudget() && TLinkCurrentNativeBudget()->reason() == TLinkNativeStop::OutputLimit
        ? @"ui_response_too_large" : @"ui_cancelled_or_timed_out", nil);
    if (pid <= 0) {
        return TLinkAXError(@"ui_frontmost_pid_unavailable", @{
            @"bundle_id": bundleID,
            @"direct_error": direct[@"error"] ?: @"unknown",
            @"diagnostic": direct[@"diagnostic"] ?: @"",
        });
    }
    return @{
        @"ok": @YES,
        @"bundle_id": bundleID,
        @"pid": @(pid),
        @"source": @"springboardservices_process_scan_v1",
    };
}

