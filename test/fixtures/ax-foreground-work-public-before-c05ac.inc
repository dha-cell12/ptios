NSDictionary *TLinkAXCopyFrontmostContext(void)
{
    NSDictionary *inProcess = TLinkAXSpringBoardProcessContext();
    if (inProcess) return inProcess;
    NSDictionary *direct = TLinkAXDirectFrontmostContext();
    if (TLinkAXResultSucceeded(direct)) return direct;
    NSString *bundleID = TLinkAXFrontmostBundleID();
    if (bundleID.length == 0) {
        return TLinkAXError(@"ui_frontmost_bundle_unavailable", @{
            @"direct_error": direct[@"error"] ?: @"unknown",
            @"diagnostic": direct[@"diagnostic"] ?: @"",
        });
    }
    pid_t pid = TLinkAXPIDForBundleID(bundleID);
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

