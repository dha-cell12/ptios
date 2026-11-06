static NSDictionary *TLinkAXDirectFrontmostContext(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities",
               RTLD_NOW | RTLD_GLOBAL);
    });
    Class serverClass = NSClassFromString(@"AXSpringBoardServer");
    SEL serverSelector = NSSelectorFromString(@"server");
    if (!serverClass || ![serverClass respondsToSelector:serverSelector]) {
        return TLinkAXError(@"ui_ax_springboard_server_unavailable", nil);
    }
    pid_t focusedPID = 0;
    pid_t topEventPID = 0;
    BOOL systemAppFrontmost = NO;
    @try {
        id server = ((id (*)(Class, SEL))objc_msgSend)(serverClass, serverSelector);
        if (!server) return TLinkAXError(@"ui_ax_springboard_server_unavailable", nil);
        focusedPID = TLinkAXPIDFromSelector(server, NSSelectorFromString(@"focusedAppPID"));
        topEventPID = TLinkAXPIDFromSelector(server, NSSelectorFromString(@"topEventPidOverride"));
        SEL systemSelector = NSSelectorFromString(@"isSystemAppFrontmost");
        if ([server respondsToSelector:systemSelector]) {
            systemAppFrontmost = ((BOOL (*)(id, SEL))objc_msgSend)(server, systemSelector);
        }
    } @catch (__unused NSException *exception) {
        return TLinkAXError(@"ui_ax_springboard_query_failed", nil);
    }

    NSDictionary *context = TLinkAXContextForPID(focusedPID);
    NSString *source = @"ax_springboard_focused_pid_v1";
    if (!context && topEventPID > 0 && topEventPID != focusedPID) {
        context = TLinkAXContextForPID(topEventPID);
        source = @"ax_springboard_top_event_pid_v1";
    }
    if (!context && systemAppFrontmost) {
        context = TLinkAXContextForPID(TLinkAXPIDForBundleID(@"com.apple.springboard"));
        source = @"ax_springboard_system_app_v1";
    }
    NSString *diagnostic = [NSString stringWithFormat:
        @"focused_pid=%d top_event_pid=%d system_frontmost=%d",
        focusedPID, topEventPID, systemAppFrontmost];
    if (!context) {
        return TLinkAXError(@"ui_ax_springboard_focused_pid_unavailable",
                            @{ @"diagnostic": diagnostic });
    }
    return @{
        @"ok": @YES,
        @"bundle_id": context[@"bundle_id"],
        @"pid": context[@"pid"],
        @"source": source,
        @"diagnostic": diagnostic,
    };
}

