static NSString *TLinkAXFrontmostBundleID(void)
{
    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
    if (!sbs) return nil;
    const char *symbols[] = {
        "SBSCopyFrontmostApplicationDisplayIdentifier",
        "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
        NULL,
    };
    for (NSUInteger index = 0; symbols[index]; index++) {
        CFStringRef (*copyFrontmost)(void) = (CFStringRef (*)(void))dlsym(sbs, symbols[index]);
        if (!copyFrontmost) continue;
        CFStringRef value = copyFrontmost();
        if (!value) continue;
        NSString *bundleID = [(__bridge NSString *)value copy];
        if (strncmp(symbols[index], "SBSCopy", 7) == 0) CFRelease(value);
        if (bundleID.length > 0) return bundleID;
    }

    mach_port_t (*serverPort)(void) =
        (mach_port_t (*)(void))dlsym(sbs, "SBSSpringBoardServerPort");
    void (*legacyFrontmost)(mach_port_t, char *) =
        (void (*)(mach_port_t, char *))dlsym(sbs, "SBFrontmostApplicationDisplayIdentifier");
    if (serverPort && legacyFrontmost) {
        char displayIdentifier[512] = {0};
        @try {
            legacyFrontmost(serverPort(), displayIdentifier);
        } @catch (__unused NSException *exception) {
            displayIdentifier[0] = '\0';
        }
        NSString *bundleID = displayIdentifier[0] != '\0'
            ? [NSString stringWithUTF8String:displayIdentifier]
            : nil;
        if (bundleID.length > 0) return bundleID;
    }
    return nil;
}

