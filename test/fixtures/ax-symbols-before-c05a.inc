static NSDictionary *TLinkAXLockState(void)
{
    __block BOOL locked = TLinkNotifyFlag("com.apple.springboard.lockstate");
    BOOL screenOff = TLinkNotifyFlag("com.apple.springboard.hasBlankedScreen");
    __block BOOL passcodeEnabled = NO;
    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
    if (sbs) {
        mach_port_t (*serverPort)(void) = (mach_port_t (*)(void))dlsym(sbs, "SBSSpringBoardServerPort");
        void (*lockStatus)(mach_port_t, BOOL *, BOOL *) =
            (void (*)(mach_port_t, BOOL *, BOOL *))dlsym(sbs, "SBGetScreenLockStatus");
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

static id TLinkAXEntitlementValue(NSString *name)
{
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
    if (!security) return nil;
    typedef CFTypeRef (*CreateTaskFn)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlementFn)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTaskFn createTask = (CreateTaskFn)dlsym(security, "SecTaskCreateFromSelf");
    CopyEntitlementFn copyValue = (CopyEntitlementFn)dlsym(security, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyValue) return nil;
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return nil;
    CFErrorRef error = NULL;
    CFTypeRef value = copyValue(task, (__bridge CFStringRef)name, &error);
    CFRelease(task);
    if (error) CFRelease(error);
    return value ? CFBridgingRelease(value) : nil;
}

