static NSDictionary *TLinkAXLockState(void)
{
    __block BOOL locked = TLinkNotifyFlag("com.apple.springboard.lockstate");
    BOOL screenOff = TLinkNotifyFlag("com.apple.springboard.hasBlankedScreen");
    __block BOOL passcodeEnabled = NO;
    static TLinkAXSymbols::Cache symbols(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        "SBSSpringBoardServerPort", "SBGetScreenLockStatus");
    const auto resolved = symbols.load(
        [](const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); },
        [](void *handle, const char *name) { return dlsym(handle, name); },
        [](void *handle) { dlclose(handle); });
    void *sbs = resolved.handle;
    if (sbs) {
        mach_port_t (*serverPort)(void) = (mach_port_t (*)(void))resolved.first;
        void (*lockStatus)(mach_port_t, BOOL *, BOOL *) =
            (void (*)(mach_port_t, BOOL *, BOOL *))resolved.second;
        if (serverPort && lockStatus) {
            @try {
                BOOL sbsLocked = NO;
                lockStatus(serverPort(), &sbsLocked, &passcodeEnabled);
                locked = locked || sbsLocked;
            } @catch (__unused NSException *exception) {
            }
        }
    }
    return @{
        @"locked": @(locked),
        @"screen_off": @(screenOff),
        @"passcode_enabled": @(passcodeEnabled),
    };
}

