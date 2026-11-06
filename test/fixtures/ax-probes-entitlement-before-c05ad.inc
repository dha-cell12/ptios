static id TLinkAXEntitlementValue(NSString *name, CFTypeRef *sharedTask = nullptr)
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
    CFTypeRef task = sharedTask ? *sharedTask : NULL;
    if (!task) {
        task = createTask(kCFAllocatorDefault);
        if (sharedTask) *sharedTask = task;
    }
    if (!task) return nil;
    CFErrorRef error = NULL;
    CFTypeRef value = NULL;
    @try {
        value = copyValue(task, (__bridge CFStringRef)name, &error);
        id result = value ? CFBridgingRelease(value) : nil;
        value = NULL;
        return result;
    } @finally {
        if (!sharedTask) CFRelease(task);
        if (error) CFRelease(error);
        if (value) CFRelease(value);
    }
}

