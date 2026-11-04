static id TLinkAXEntitlementValue(NSString *name)
{
    static TLinkAXSymbols::Cache symbols(
        "/System/Library/Frameworks/Security.framework/Security",
        "SecTaskCreateFromSelf", "SecTaskCopyValueForEntitlement");
    const auto resolved = symbols.load(
        [](const char *path) { return dlopen(path, RTLD_LAZY | RTLD_LOCAL); },
        [](void *handle, const char *name) { return dlsym(handle, name); },
        [](void *handle) { dlclose(handle); });
    void *security = resolved.handle;
    if (!security) return nil;
    typedef CFTypeRef (*CreateTaskFn)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlementFn)(CFTypeRef, CFStringRef, CFErrorRef *);
    CreateTaskFn createTask = (CreateTaskFn)resolved.first;
    CopyEntitlementFn copyValue = (CopyEntitlementFn)resolved.second;
    if (!createTask || !copyValue) return nil;
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) return nil;
    CFErrorRef error = NULL;
    CFTypeRef value = copyValue(task, (__bridge CFStringRef)name, &error);
    CFRelease(task);
    if (error) CFRelease(error);
    return value ? CFBridgingRelease(value) : nil;
}

