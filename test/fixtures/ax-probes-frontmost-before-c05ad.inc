static NSString *TLinkAXFrontmostBundleID(void)
{
    static TLinkAXSymbols::Cache copySymbols(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        "SBSCopyFrontmostApplicationDisplayIdentifier", "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay");
    const auto resolved = copySymbols.load(
        [](const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); },
        [](void *handle, const char *name) { return dlsym(handle, name); },
        [](void *handle) { dlclose(handle); }, false);
    void *sbs = resolved.handle;
    if (!sbs) return nil;
    const char *symbols[] = {
        "SBSCopyFrontmostApplicationDisplayIdentifier",
        "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
        NULL,
    };
    for (NSUInteger index = 0; symbols[index]; index++) {
        void *copySymbol = index == 0 ? resolved.first : copySymbols.loadSecond(
            [](void *handle, const char *name) { return dlsym(handle, name); });
        CFStringRef (*copyFrontmost)(void) = (CFStringRef (*)(void))copySymbol;
        if (!copyFrontmost) continue;
        CFStringRef value = copyFrontmost();
        if (!value) continue;
        NSString *bundleID = [(__bridge NSString *)value copy];
        if (strncmp(symbols[index], "SBSCopy", 7) == 0) CFRelease(value);
        if (bundleID.length > 0) return bundleID;
    }

    static TLinkAXSymbols::Symbol serverPortSymbol("SBSSpringBoardServerPort");
    static TLinkAXSymbols::Symbol legacyFrontmostSymbol("SBFrontmostApplicationDisplayIdentifier");
    mach_port_t (*serverPort)(void) = (mach_port_t (*)(void))serverPortSymbol.load(sbs,
        [](void *handle, const char *name) { return dlsym(handle, name); });
    void (*legacyFrontmost)(mach_port_t, char *) = (void (*)(mach_port_t, char *))legacyFrontmostSymbol.load(sbs,
        [](void *handle, const char *name) { return dlsym(handle, name); });
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

