static NSDictionary *TLinkAXSpringBoardProcessContext(void)
{
    // This path is only for the injected SpringBoard bridge. Task 34 already
    // obtains the foreground application from this in-process selector on
    // rootfull and roothide, where the daemon's remote AX PID query may be 0.
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
        return nil;
    Class springBoardClass = NSClassFromString(@"SpringBoard");
    SEL sharedSelector = NSSelectorFromString(@"sharedApplication");
    SEL foregroundSelector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if (!springBoardClass || ![springBoardClass respondsToSelector:sharedSelector])
        return TLinkAXError(@"ui_springboard_process_unavailable", nil);

    __block id foregroundApp = nil;
    __block BOOL queryFailed = NO;
    void (^query)(void) = ^{
        @try {
            id springBoard = ((id (*)(Class, SEL))objc_msgSend)(springBoardClass, sharedSelector);
            if (![springBoard respondsToSelector:foregroundSelector]) {
                queryFailed = YES;
                return;
            }
            foregroundApp = ((id (*)(id, SEL))objc_msgSend)(springBoard, foregroundSelector);
        } @catch (__unused NSException *exception) {
            queryFailed = YES;
        }
    };
    if ([NSThread isMainThread]) query();
    else dispatch_sync(dispatch_get_main_queue(), query);
    if (queryFailed) return TLinkAXError(@"ui_springboard_frontmost_query_failed", nil);

    // A nil result can also occur during an app transition. Do not mistake
    // it for the Home screen and target SpringBoard's own AX tree.
    if (!foregroundApp) return TLinkAXError(@"ui_springboard_frontmost_unavailable", nil);
    SEL bundleSelector = NSSelectorFromString(@"bundleIdentifier");
    NSString *bundleID = [foregroundApp respondsToSelector:bundleSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(foregroundApp, bundleSelector) : nil;
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0)
        return TLinkAXError(@"ui_springboard_frontmost_bundle_unavailable", nil);
    pid_t pid = TLinkAXPIDFromSelector(foregroundApp, NSSelectorFromString(@"pid"));
    if (pid <= 0) pid = TLinkAXPIDFromSelector(foregroundApp, NSSelectorFromString(@"processIdentifier"));
    if (pid <= 0) {
        SEL processSelector = NSSelectorFromString(@"process");
        if ([foregroundApp respondsToSelector:processSelector]) {
            id process = ((id (*)(id, SEL))objc_msgSend)(foregroundApp, processSelector);
            pid = TLinkAXPIDFromSelector(process, NSSelectorFromString(@"processIdentifier"));
            if (pid <= 0) pid = TLinkAXPIDFromSelector(process, NSSelectorFromString(@"pid"));
        }
    }
    if (pid <= 0) {
        Class controllerClass = NSClassFromString(@"SBApplicationController");
        SEL sharedController = NSSelectorFromString(@"sharedInstance");
        SEL applicationSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        if ([controllerClass respondsToSelector:sharedController]) {
            id controller = ((id (*)(Class, SEL))objc_msgSend)(controllerClass, sharedController);
            if ([controller respondsToSelector:applicationSelector]) {
                id application = ((id (*)(id, SEL, id))objc_msgSend)(controller,
                                                                   applicationSelector, bundleID);
                pid = TLinkAXPIDFromSelector(application, NSSelectorFromString(@"pid"));
                if (pid <= 0) pid = TLinkAXPIDFromSelector(application,
                                                           NSSelectorFromString(@"processIdentifier"));
            }
        }
    }
    if (pid <= 0) pid = TLinkAXPIDForBundleID(bundleID);
    if (pid <= 0) return TLinkAXError(@"ui_springboard_frontmost_pid_unavailable",
                                       @{ @"bundle_id": bundleID });
    return @{
        @"ok": @YES,
        @"bundle_id": bundleID,
        @"pid": @(pid),
        @"source": @"springboard_in_process_v1",
    };
}

