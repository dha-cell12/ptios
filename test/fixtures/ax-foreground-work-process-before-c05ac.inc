static NSString *TLinkAXBundleIDForExecutablePath(NSString *executablePath)
{
    if (executablePath.length == 0) return nil;
    NSRange appMarker = [executablePath rangeOfString:@".app/" options:NSBackwardsSearch];
    if (appMarker.location == NSNotFound) return nil;
    NSString *bundlePath = [executablePath substringToIndex:appMarker.location + @".app".length];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]]
        ? info[@"CFBundleIdentifier"] : nil;
    return bundleID.length > 0 ? bundleID : nil;
}

static pid_t TLinkAXPIDForBundleID(NSString *bundleID)
{
    if (bundleID.length == 0) return 0;
    int mib[3] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    size_t length = 0;
    if (sysctl(mib, 3, NULL, &length, NULL, 0) != 0 || length == 0) return 0;
    length += 64 * sizeof(struct kinfo_proc);
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (sysctl(mib, 3, data.mutableBytes, &length, NULL, 0) != 0) return 0;
    int (*pidPath)(int, void *, uint32_t) =
        (int (*)(int, void *, uint32_t))dlsym(RTLD_DEFAULT, "proc_pidpath");
    if (!pidPath) return 0;
    NSUInteger count = length / sizeof(struct kinfo_proc);
    struct kinfo_proc *processes = (struct kinfo_proc *)data.mutableBytes;
    for (NSUInteger index = 0; index < count; index++) {
        pid_t pid = processes[index].kp_proc.p_pid;
        if (pid <= 0) continue;
        char path[4096] = {0};
        if (pidPath(pid, path, sizeof(path)) <= 0) continue;
        NSString *candidate = TLinkAXBundleIDForExecutablePath(
            [NSString stringWithUTF8String:path] ?: @"");
        if ([candidate isEqualToString:bundleID]) return pid;
    }
    return 0;
}

static pid_t TLinkAXPIDFromSelector(id target, SEL selector)
{
    if (!target || !selector || ![target respondsToSelector:selector]) return 0;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature) return 0;
    const char *returnType = signature.methodReturnType;
    while (returnType && returnType[0] && strchr("rnNoORV", returnType[0])) returnType++;
    if (returnType && returnType[0] == '@') {
        id value = ((id (*)(id, SEL))objc_msgSend)(target, selector);
        return [value respondsToSelector:@selector(intValue)] ? (pid_t)[value intValue] : 0;
    }
    if (signature.methodReturnLength > 0 &&
        signature.methodReturnLength <= sizeof(NSInteger)) {
        return (pid_t)((NSInteger (*)(id, SEL))objc_msgSend)(target, selector);
    }
    return 0;
}

static NSDictionary *TLinkAXContextForPID(pid_t pid)
{
    if (pid <= 0 || pid == getpid()) return nil;
    int (*pidPath)(int, void *, uint32_t) =
        (int (*)(int, void *, uint32_t))dlsym(RTLD_DEFAULT, "proc_pidpath");
    if (!pidPath) return nil;
    char path[4096] = {0};
    if (pidPath(pid, path, sizeof(path)) <= 0) return nil;
    NSString *executablePath = [NSString stringWithUTF8String:path] ?: @"";
    NSRange appMarker = [executablePath rangeOfString:@".app/" options:NSBackwardsSearch];
    if (appMarker.location == NSNotFound) return nil;
    NSString *bundlePath = [executablePath substringToIndex:appMarker.location + @".app".length];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bundleID = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]]
        ? info[@"CFBundleIdentifier"] : @"";
    NSString *executable = [info[@"CFBundleExecutable"] isKindOfClass:[NSString class]]
        ? info[@"CFBundleExecutable"] : @"";
    NSString *packageType = [info[@"CFBundlePackageType"] isKindOfClass:[NSString class]]
        ? info[@"CFBundlePackageType"] : @"";
    if (bundleID.length == 0 || executable.length == 0 ||
        ![[executablePath lastPathComponent] isEqualToString:executable] ||
        (packageType.length > 0 && ![packageType isEqualToString:@"APPL"])) return nil;
    if (![bundleID isEqualToString:@"com.apple.springboard"]) {
        if ([info[@"LSBackgroundOnly"] boolValue] || [info[@"LSUIElement"] boolValue] ||
            [bundleID isEqualToString:@"com.apple.assistivetouchd"] ||
            [bundleID isEqualToString:@"com.apple.AccessibilityUIServer"] ||
            [bundleID isEqualToString:@"com.apple.UIKitSystem"]) return nil;
        NSArray *tags = [info[@"SBAppTags"] isKindOfClass:[NSArray class]]
            ? info[@"SBAppTags"] : @[];
        if ([tags containsObject:@"hidden"]) return nil;
    }
    return @{ @"bundle_id": bundleID, @"pid": @(pid) };
}

