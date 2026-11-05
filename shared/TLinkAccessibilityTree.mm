#include "TLinkNativeDispatch.h"
#include "TLinkAXSymbolCache.h"
#include "TLinkAXSnapshotWindow.h"
#include "TLinkAXAdmission.h"
#import "TLinkAccessibilityTree.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <math.h>
#import <mach/mach.h>
#import <objc/message.h>
#include <string.h>

NSString *const TLinkAXSnapshotSchema = @"ui_snapshot_v1";
NSString *const TLinkAXBackendName = @"axruntime_numeric_v1";

// Scanned nodes are bounded independently of rows surviving the filters.
static const NSInteger kTLinkAXDefaultMaxScannedElements = 4096;
static const NSInteger kTLinkAXHardMaxScannedElements = 16384;

typedef CFTypeRef TLinkAXElementRef;
typedef TLinkAXElementRef (*TLinkAXCreateAppFn)(pid_t);
typedef int (*TLinkAXCopyAttributeFn)(TLinkAXElementRef, CFStringRef, CFTypeRef *);
typedef int (*TLinkAXSetTimeoutFn)(TLinkAXElementRef, float);
typedef Boolean (*TLinkAXValueGetValueFn)(CFTypeRef, int, void *);
typedef int (*TLinkAXHitTestFn)(TLinkAXElementRef, TLinkAXElementRef *, float, float);

static TLinkAXCreateAppFn sTLinkAXCreateApp = NULL;
static TLinkAXCopyAttributeFn sTLinkAXCopyAttribute = NULL;
static TLinkAXSetTimeoutFn sTLinkAXSetTimeout = NULL;
static TLinkAXValueGetValueFn sTLinkAXValueGetValue = NULL;
static TLinkAXHitTestFn sTLinkAXHitTest = NULL;
static BOOL sTLinkAXFrameworkLoaded = NO;
static BOOL sTLinkAccessibilityLibraryLoaded = NO;
static BOOL sTLinkAXEnableSymbol = NO;
static BOOL sTLinkAXAutomationSymbol = NO;
static BOOL sTLinkAXRequestingClientSymbol = NO;
static BOOL sTLinkAXOverrideClientSymbol = NO;

static dispatch_queue_t TLinkAXQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.tlinkauto.accessibility-tree", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static TLinkAXAdmission::State &TLinkAXAdmissionState(void)
{
    static TLinkAXAdmission::State state;
    return state;
}

static BOOL TLinkNotifyFlag(const char *name)
{
    int token = 0;
    if (notify_register_check(name, &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state != 0;
}

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

static BOOL TLinkAXPrepare(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *ax = dlopen("/System/Library/PrivateFrameworks/AXRuntime.framework/AXRuntime", RTLD_NOW | RTLD_LOCAL);
        void *accessibility = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW | RTLD_LOCAL);
        sTLinkAXFrameworkLoaded = ax != NULL;
        sTLinkAccessibilityLibraryLoaded = accessibility != NULL;

        void (*enable)(BOOL) = accessibility
            ? (void (*)(BOOL))dlsym(accessibility, "_AXSApplicationAccessibilitySetEnabled") : NULL;
        void (*automation)(BOOL) = accessibility
            ? (void (*)(BOOL))dlsym(accessibility, "_AXSSetAutomationEnabled") : NULL;
        sTLinkAXEnableSymbol = enable != NULL;
        sTLinkAXAutomationSymbol = automation != NULL;
        if (enable) enable(YES);
        if (automation) automation(YES);

        if (!ax) return;
        void (*requestingClient)(uint32_t) =
            (void (*)(uint32_t))dlsym(ax, "__AXSetRequestingClient");
        uint64_t (*overrideClient)(uint64_t) =
            (uint64_t (*)(uint64_t))dlsym(ax, "_AXOverrideRequestingClientType");
        sTLinkAXRequestingClientSymbol = requestingClient != NULL;
        sTLinkAXOverrideClientSymbol = overrideClient != NULL;
        if (requestingClient) requestingClient(2);
        if (overrideClient) overrideClient(2);

        sTLinkAXCreateApp = (TLinkAXCreateAppFn)dlsym(ax, "_AXUIElementCreateAppElementWithPid");
        sTLinkAXCopyAttribute = (TLinkAXCopyAttributeFn)dlsym(ax, "AXUIElementCopyAttributeValue");
        sTLinkAXSetTimeout = (TLinkAXSetTimeoutFn)dlsym(ax, "AXUIElementSetMessagingTimeout");
        sTLinkAXValueGetValue = (TLinkAXValueGetValueFn)dlsym(ax, "AXValueGetValue");
        sTLinkAXHitTest = (TLinkAXHitTestFn)dlsym(ax, "AXUIElementCopyElementAtPosition");
    });
    return sTLinkAXCreateApp && sTLinkAXCopyAttribute && sTLinkAXValueGetValue;
}

static NSDictionary *TLinkAXError(NSString *code, NSDictionary *extra)
{
    NSMutableDictionary *result = [@{
        @"ok": @NO,
        @"schema": TLinkAXSnapshotSchema,
        @"source": TLinkAXBackendName,
        @"error": code ?: @"ui_tree_unknown_error",
    } mutableCopy];
    if ([extra isKindOfClass:[NSDictionary class]]) [result addEntriesFromDictionary:extra];
    return result;
}

BOOL TLinkAXResultSucceeded(NSDictionary *result)
{
    return [result isKindOfClass:[NSDictionary class]] && [result[@"ok"] boolValue];
}

NSDictionary *TLinkAXCapabilitySnapshot(void)
{
    BOOL prepared = TLinkAXPrepare();
    NSDictionary *lockState = TLinkAXLockState();
    NSDictionary *foreground = TLinkAXCopyFrontmostContext();
    NSArray<NSString *> *names = @[
        @"com.apple.private.accessibility.inspection",
        @"com.apple.accessibility.api",
        @"com.apple.private.accessibility.look-me-up-setup",
    ];
    NSMutableDictionary *entitlements = [NSMutableDictionary dictionary];
    CFTypeRef entitlementTask = NULL;
    @try {
        for (NSString *name in names) {
            id value = TLinkAXEntitlementValue(name, &entitlementTask);
            entitlements[name] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
        }
    } @finally {
        if (entitlementTask) CFRelease(entitlementTask);
    }
    return @{
        @"ok": @(prepared),
        @"schema": @"ui_tree_capability_v1",
        @"source": TLinkAXBackendName,
        @"state": prepared ? @"ready" : @"unavailable",
        @"flat_snapshot": @YES,
        @"hierarchy": @NO,
        @"framework_loaded": @(sTLinkAXFrameworkLoaded),
        @"accessibility_library_loaded": @(sTLinkAccessibilityLibraryLoaded),
        @"create_app_symbol": @(sTLinkAXCreateApp != NULL),
        @"copy_attribute_symbol": @(sTLinkAXCopyAttribute != NULL),
        @"set_timeout_symbol": @(sTLinkAXSetTimeout != NULL),
        @"value_get_symbol": @(sTLinkAXValueGetValue != NULL),
        @"hit_test_symbol": @(sTLinkAXHitTest != NULL),
        @"enable_symbol": @(sTLinkAXEnableSymbol),
        @"automation_symbol": @(sTLinkAXAutomationSymbol),
        @"requesting_client_symbol": @(sTLinkAXRequestingClientSymbol),
        @"override_client_symbol": @(sTLinkAXOverrideClientSymbol),
        @"foreground_probe": @{
            @"ok": @([foreground[@"ok"] boolValue]),
            @"bundle_id": foreground[@"bundle_id"] ?: @"",
            @"pid": foreground[@"pid"] ?: @0,
            @"source": foreground[@"source"] ?: @"",
            @"error": foreground[@"error"] ?: @"",
            @"diagnostic": foreground[@"diagnostic"] ?: @"",
            @"direct_error": foreground[@"direct_error"] ?: @"",
        },
        @"entitlements": entitlements,
        @"lock_state": lockState,
        @"default_max_elements": @250,
        @"hard_max_elements": @1000,
        @"default_max_scanned_elements": @(kTLinkAXDefaultMaxScannedElements),
        @"hard_max_scanned_elements": @(kTLinkAXHardMaxScannedElements),
        @"max_pending_queries": @(TLinkAXAdmission::MaxPending),
        @"default_timeout_ms": @1500,
    };
}

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

static id TLinkAXAttribute(TLinkAXElementRef element, uint32_t key, int *errorOut,
                         TLinkAXSnapshotWindow *window = nullptr)
{
    if (TLinkNativeStopped()) return nil;
    if (!element || !sTLinkAXCopyAttribute) return nil;
    auto budget = TLinkCurrentNativeBudget();
    if (window || budget) {
        double timeout = budget ? budget->remainingSeconds(0.10) : 0.10;
        if (window) timeout = window->remainingSeconds(TLinkNativeNowNs(), timeout);
        if (timeout <= 0 || TLinkNativeStopped()) return nil;
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, (float)timeout);
        if (TLinkNativeStopped() || (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)) return nil;
    }
    CFTypeRef value = NULL;
    @try {
        int error = sTLinkAXCopyAttribute(element, (CFStringRef)(uintptr_t)key, &value);
        if (errorOut) *errorOut = error;
        if (error != 0 || ((window || budget) && (TLinkNativeStopped() ||
            (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0)))) return nil;
        id result = value ? CFBridgingRelease(value) : nil;
        value = NULL;
        return result;
    } @finally {
        if (value) CFRelease(value);
    }
}

static NSString *TLinkAXStringValue(id value)
{
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue] ?: @"";
    return @"";
}

static NSString *TLinkAXRoleForTraits(uint64_t traits)
{
    if (traits & UIAccessibilityTraitButton) return @"button";
    if (traits & UIAccessibilityTraitLink) return @"link";
    if (traits & UIAccessibilityTraitImage) return @"image";
    if (traits & UIAccessibilityTraitHeader) return @"heading";
    if (traits & UIAccessibilityTraitAdjustable) return @"adjustable";
    if (traits & UIAccessibilityTraitSearchField) return @"search_field";
    if (traits & UIAccessibilityTraitKeyboardKey) return @"keyboard_key";
    if (traits & UIAccessibilityTraitStaticText) return @"text";
    return @"element";
}

static NSDictionary *TLinkAXSerializeElement(TLinkAXElementRef element,
                                             CGRect screen,
                                             NSUInteger index,
                                             TLinkAXSnapshotWindow *window = nullptr)
{
    if (!element) return nil;
    @try {
        if (TLinkNativeStopped()) return nil;
        auto nativeBudget = TLinkCurrentNativeBudget();
        if (!window && !nativeBudget && sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, 0.10f);
        id frameValue = TLinkAXAttribute(element, 2003, NULL, window);
        CGRect frame = CGRectZero;
        if (!frameValue ||
            !sTLinkAXValueGetValue((__bridge CFTypeRef)frameValue, 3, &frame) ||
            !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
            !isfinite(frame.size.width) || !isfinite(frame.size.height)) {
            return nil;
        }

        id label = TLinkAXAttribute(element, 2001, NULL, window);
        id value = TLinkAXAttribute(element, 2006, NULL, window);
        id identifier = TLinkAXAttribute(element, 5019, NULL, window);
        id traitsValue = TLinkAXAttribute(element, 2004, NULL, window);
        uint64_t traits = [traitsValue respondsToSelector:@selector(unsignedLongLongValue)]
            ? (uint64_t)[traitsValue unsignedLongLongValue] : 0;
        BOOL enabled = (traits & UIAccessibilityTraitNotEnabled) == 0;
        BOOL hasSize = frame.size.width > 0.0 && frame.size.height > 0.0;
        BOOL interactiveTrait = (traits & (UIAccessibilityTraitButton |
                                           UIAccessibilityTraitLink |
                                           UIAccessibilityTraitAdjustable |
                                           UIAccessibilityTraitKeyboardKey)) != 0;
        BOOL clickable = enabled && hasSize &&
            (interactiveTrait || (traits & UIAccessibilityTraitStaticText) == 0);
        CGRect intersection = CGRectIntersection(frame, screen);
        BOOL intersectsScreen = !CGRectIsNull(intersection) && !CGRectIsEmpty(intersection);

        CGPoint point = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
        id pointValue = TLinkAXAttribute(element, 2007, NULL, window);
        CGPoint candidate = point;
        if (pointValue &&
            sTLinkAXValueGetValue((__bridge CFTypeRef)pointValue, 1, &candidate) &&
            isfinite(candidate.x) && isfinite(candidate.y)) {
            point = candidate;
        }
        BOOL activationValid = CGRectContainsPoint(screen, point);
        if (!activationValid && CGRectContainsPoint(screen, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame)))) {
            point = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
            activationValid = YES;
        }

        if ((window || nativeBudget) && (TLinkNativeStopped() ||
            (window && window->remainingSeconds(TLinkNativeNowNs(), 0.10) <= 0))) return nil;
        return @{
            @"index": @(index),
            @"label": TLinkAXStringValue(label),
            @"identifier": TLinkAXStringValue(identifier),
            @"value": TLinkAXStringValue(value),
            @"role": TLinkAXRoleForTraits(traits),
            @"traits": @(traits),
            @"enabled": @(enabled),
            @"clickable": @(clickable),
            @"intersects_screen": @(intersectsScreen),
            @"visible": @(intersectsScreen),
            @"frame": @{
                @"x": @(frame.origin.x), @"y": @(frame.origin.y),
                @"width": @(frame.size.width), @"height": @(frame.size.height),
            },
            @"activation_point": @{
                @"x": @(point.x), @"y": @(point.y),
            },
            @"activation_point_valid": @(activationValid),
        };
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSInteger TLinkAXBoundedInteger(id value, NSInteger fallback, NSInteger minimum, NSInteger maximum)
{
    NSInteger number = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
    if (number < minimum) number = minimum;
    if (number > maximum) number = maximum;
    return number;
}

static NSDictionary *TLinkAXCopySnapshotUnlocked(pid_t pid,
                                                 NSString *bundleID,
                                                 NSDictionary *options)
{
    if (pid <= 0) return TLinkAXError(@"ui_invalid_pid", @{@"pid": @(pid)});
    NSDictionary *lockState = TLinkAXLockState();
    BOOL allowLocked = [options[@"allow_locked"] boolValue];
    if (!allowLocked && [lockState[@"screen_off"] boolValue]) {
        return TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
    }
    if (!allowLocked && [lockState[@"locked"] boolValue]) {
        return TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
    }
    if (!TLinkAXPrepare()) return TLinkAXError(@"ui_axruntime_unavailable", @{@"pid": @(pid)});

    id maxElementsValue = options[@"max_elements"] ?: options[@"maxElements"];
    id maxScannedValue = options[@"max_scanned_elements"] ?: options[@"maxScannedElements"];
    id timeoutValue = options[@"timeout_ms"] ?: options[@"timeoutMs"];
    id visibleValue = options[@"visible_only"] ?: options[@"visibleOnly"];
    id clickableValue = options[@"clickable_only"] ?: options[@"clickableOnly"];
    NSInteger maxElements = TLinkAXBoundedInteger(maxElementsValue, 250, 1, 1000);
    NSInteger maxScannedElements = TLinkAXBoundedInteger(maxScannedValue,
        kTLinkAXDefaultMaxScannedElements, 1, kTLinkAXHardMaxScannedElements);
    NSInteger timeoutMs = TLinkAXBoundedInteger(timeoutValue, 1500, 100, 3000);
    BOOL visibleOnly = visibleValue ? [visibleValue boolValue] : YES;
    BOOL clickableOnly = [clickableValue boolValue];
    TLinkAXSnapshotWindow window(TLinkNativeNowNs(), (unsigned)timeoutMs);

    TLinkAXElementRef root = NULL;
    CFTypeRef rawElements = NULL;
    NSArray *elements = nil;
    @try {
        root = sTLinkAXCreateApp(pid);
        if (!root) return TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
        auto nativeBudget = TLinkCurrentNativeBudget();
        double queryTimeout = MIN(0.5f, (float)timeoutMs / 1000.0f);
        if (nativeBudget) queryTimeout = nativeBudget->remainingSeconds(queryTimeout);
        queryTimeout = window.remainingSeconds(TLinkNativeNowNs(), queryTimeout);
        if (TLinkNativeStopped() || queryTimeout <= 0) { CFRelease(root); root = NULL; return TLinkAXError(@"ui_cancelled_or_timed_out", nil); }
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, (float)queryTimeout);
        if (TLinkNativeStopped() || window.remainingSeconds(TLinkNativeNowNs(), queryTimeout) <= 0) {
            CFRelease(root); root = NULL;
            return TLinkAXError(@"ui_cancelled_or_timed_out", nil);
        }
        int error = sTLinkAXCopyAttribute(root, (CFStringRef)(uintptr_t)3015, &rawElements);
        CFRelease(root);
        root = NULL;
        if (error != 0 || !rawElements || CFGetTypeID(rawElements) != CFArrayGetTypeID()) {
            return TLinkAXError(@"ui_element_query_failed", @{@"pid": @(pid), @"ax_error": @(error)});
        }
        elements = CFBridgingRelease(rawElements);
        rawElements = NULL;
    } @catch (__unused NSException *exception) {
        return TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
    } @finally {
        if (root) CFRelease(root);
        if (rawElements) CFRelease(rawElements);
    }

    CGRect screen = [UIScreen mainScreen].bounds;
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)maxElements, elements.count)];
    NSUInteger scanned = 0;
    NSUInteger serializationFailures = 0;
    BOOL truncated = NO;
    size_t estimatedJSONBytes = 0;
    for (id object in elements) {
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        if (rows.count >= (NSUInteger)maxElements || scanned >= (NSUInteger)maxScannedElements ||
            window.remainingSeconds(TLinkNativeNowNs(), 1.0) <= 0) {
            truncated = YES;
            break;
        }
        @autoreleasepool {
            scanned++;
            NSDictionary *node = TLinkAXSerializeElement((__bridge TLinkAXElementRef)object, screen, scanned - 1, &window);
            if (window.remainingSeconds(TLinkNativeNowNs(), 1.0) <= 0) {
                truncated = YES;
                break;
            }
            if (!node) {
                serializationFailures++;
                continue;
            }
            if (visibleOnly && ![node[@"intersects_screen"] boolValue]) continue;
            if (clickableOnly && ![node[@"clickable"] boolValue]) continue;
            if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
            // Conservative escaped-JSON and base64 accounting before retaining another row.
            size_t rowBytes = 768;
            for (NSString *key in @[@"label", @"value", @"identifier", @"role"]) {
                NSString *text = node[key];
                size_t bytes = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                if (!TLinkNativeOutputAllowed(bytes)) return TLinkAXError(@"ui_response_too_large", @{@"partial": @YES});
                rowBytes += 6 * bytes;
            }
            estimatedJSONBytes += rowBytes;
            if (!TLinkNativeOutputAllowed(32 * 1024 + 4 * ((estimatedJSONBytes + 2) / 3)))
                return TLinkAXError(@"ui_response_too_large", @{@"partial": @YES});
            [rows addObject:node];
        }
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    const uint64_t finished = TLinkNativeNowNs();
    if (window.remainingSeconds(finished, 1.0) <= 0) truncated = YES;
    NSTimeInterval durationMs = window.elapsedMilliseconds(finished);
    return @{
        @"ok": @YES,
        @"schema": TLinkAXSnapshotSchema,
        @"source": TLinkAXBackendName,
        @"bundle_id": bundleID ?: @"",
        @"pid": @(pid),
        @"captured_at_ms": @((uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0)),
        @"duration_ms": @((NSInteger)llround(durationMs)),
        @"screen": @{
            @"width": @(screen.size.width), @"height": @(screen.size.height),
            @"scale": @([UIScreen mainScreen].scale),
            @"coordinate_space": @"points",
        },
        @"elements": rows,
        @"count": @(rows.count),
        @"scanned_count": @(scanned),
        @"source_count": @(elements.count),
        @"serialization_failure_count": @(serializationFailures),
        @"truncated": @(truncated || scanned < elements.count),
        @"partial": @(serializationFailures > 0 || truncated || scanned < elements.count),
        @"context_changed": @NO,
        @"lock_state": lockState,
    };
}

NSDictionary *TLinkAXCopySnapshot(pid_t pid, NSString *bundleID, NSDictionary *options)
{
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        result = TLinkAXCopySnapshotUnlocked(pid, bundleID ?: @"", options ?: @{});
    });
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    return result ?: TLinkAXError(@"ui_snapshot_failed", @{@"pid": @(pid)});
}

static BOOL TLinkAXTextMatches(NSString *candidate,
                               NSString *expected,
                               NSString *mode,
                               BOOL caseSensitive)
{
    if (expected.length == 0) return YES;
    NSString *left = candidate ?: @"";
    NSString *right = expected;
    if (!caseSensitive) {
        left = [left lowercaseString];
        right = [right lowercaseString];
    }
    if ([mode isEqualToString:@"exact"]) return [left isEqualToString:right];
    if ([mode isEqualToString:@"prefix"]) return [left hasPrefix:right];
    return [left rangeOfString:right].location != NSNotFound;
}

static NSDictionary *TLinkAXFindInSnapshot(NSDictionary *snapshot, NSDictionary *selector)
{
    if (!TLinkAXResultSucceeded(snapshot)) return snapshot;
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    NSString *text = [selector[@"text"] isKindOfClass:[NSString class]] ? selector[@"text"] : @"";
    NSString *identifier = [selector[@"identifier"] isKindOfClass:[NSString class]] ? selector[@"identifier"] : @"";
    NSString *role = [selector[@"role"] isKindOfClass:[NSString class]] ? selector[@"role"] : @"";
    id modeValue = selector[@"match"] ?: selector[@"matchMode"];
    NSString *mode = [modeValue isKindOfClass:[NSString class]]
        ? [modeValue lowercaseString] : @"contains";
    if ([mode isEqualToString:@"equals"]) mode = @"exact";
    if (![@[@"contains", @"exact", @"prefix"] containsObject:mode]) mode = @"contains";
    id caseValue = selector[@"case_sensitive"] ?: selector[@"caseSensitive"];
    id visibleValue = selector[@"visible_only"] ?: selector[@"visibleOnly"];
    id clickableValue = selector[@"clickable_only"] ?: selector[@"clickableOnly"];
    BOOL caseSensitive = [caseValue boolValue];
    BOOL visibleOnly = visibleValue ? [visibleValue boolValue] : YES;
    BOOL clickableOnly = [clickableValue boolValue];
    NSInteger requestedIndex = TLinkAXBoundedInteger(selector[@"index"], 0, 0, 999);
    NSUInteger matchCount = 0;
    NSDictionary *selectedElement = nil;
    for (NSDictionary *element in snapshot[@"elements"]) {
        if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
        @autoreleasepool {
            if (visibleOnly && ![element[@"intersects_screen"] boolValue]) continue;
            if (clickableOnly && ![element[@"clickable"] boolValue]) continue;
            if (identifier.length > 0 &&
                !TLinkAXTextMatches(element[@"identifier"], identifier, mode, caseSensitive)) continue;
            if (role.length > 0 &&
                !TLinkAXTextMatches(element[@"role"], role, @"exact", caseSensitive)) continue;
            if (text.length > 0) {
                BOOL labelMatch = TLinkAXTextMatches(element[@"label"], text, mode, caseSensitive);
                BOOL valueMatch = TLinkAXTextMatches(element[@"value"], text, mode, caseSensitive);
                if (!labelMatch && !valueMatch) continue;
            }
            if (matchCount == (NSUInteger)requestedIndex) selectedElement = element;
            ++matchCount;
        }
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    NSDictionary *element = selectedElement;
    NSMutableDictionary *result = [snapshot mutableCopy];
    [result removeObjectForKey:@"elements"];
    result[@"schema"] = @"ui_find_v1";
    result[@"selector"] = selector ?: @{};
    result[@"found"] = @(element != nil);
    result[@"match_count"] = @(matchCount);
    result[@"element"] = element ?: @{};
    return result;
}

NSDictionary *TLinkAXFindElement(pid_t pid, NSString *bundleID, NSDictionary *selector)
{
    if (![selector isKindOfClass:[NSDictionary class]]) {
        return TLinkAXError(@"ui_selector_invalid", @{@"pid": @(pid)});
    }
    NSString *text = [selector[@"text"] isKindOfClass:[NSString class]] ? selector[@"text"] : @"";
    NSString *identifier = [selector[@"identifier"] isKindOfClass:[NSString class]] ? selector[@"identifier"] : @"";
    NSString *role = [selector[@"role"] isKindOfClass:[NSString class]] ? selector[@"role"] : @"";
    if (text.length == 0 && identifier.length == 0 && role.length == 0) {
        return TLinkAXError(@"ui_selector_requires_text_identifier_or_role", @{@"pid": @(pid)});
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"max_elements"] = selector[@"max_elements"] ?: selector[@"maxElements"] ?: @250;
    options[@"max_scanned_elements"] = selector[@"max_scanned_elements"] ?: selector[@"maxScannedElements"] ?: @(kTLinkAXDefaultMaxScannedElements);
    options[@"timeout_ms"] = selector[@"timeout_ms"] ?: selector[@"timeoutMs"] ?: @1500;
    options[@"allow_locked"] = selector[@"allow_locked"] ?: selector[@"allowLocked"] ?: @NO;
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        NSDictionary *snapshot = TLinkAXCopySnapshotUnlocked(pid, bundleID ?: @"", options);
        result = TLinkAXFindInSnapshot(snapshot, selector);
    });
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"partial": @YES});
    return result ?: TLinkAXError(@"ui_find_failed", @{@"pid": @(pid)});
}

BOOL TLinkAXResultCompleteForAction(NSDictionary *result)
{
    if (!TLinkAXResultSucceeded(result)) return NO;
    id partial = result[@"partial"];
    id truncated = result[@"truncated"];
    return [partial isKindOfClass:[NSNumber class]] &&
           [truncated isKindOfClass:[NSNumber class]] &&
           ![partial boolValue] && ![truncated boolValue];
}

NSDictionary *TLinkAXElementAtPoint(pid_t pid, NSString *bundleID, CGPoint point)
{
    if (pid <= 0 || !isfinite(point.x) || !isfinite(point.y)) {
        return TLinkAXError(@"ui_hit_test_invalid_request", @{@"pid": @(pid)});
    }
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
    TLinkAXAdmission::Lease admission(TLinkAXAdmissionState());
    if (!admission.held()) return TLinkAXError(@"ui_ax_busy", @{@"partial": @YES, @"retryable": @YES});
    __block NSDictionary *result = nil;
    TLinkNativeDispatchSync(TLinkAXQueue(), ^{
        NSDictionary *lockState = TLinkAXLockState();
        if (TLinkNativeStopped()) {
            result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
            return;
        }
        if ([lockState[@"screen_off"] boolValue]) {
            result = TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if ([lockState[@"locked"] boolValue]) {
            result = TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        BOOL prepared = TLinkAXPrepare();
        if (TLinkNativeStopped()) {
            result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
            return;
        }
        if (!prepared || !sTLinkAXHitTest) {
            result = TLinkAXError(@"ui_hit_test_unavailable", @{@"pid": @(pid)});
            return;
        }
        CGRect screen = [UIScreen mainScreen].bounds;
        if (!CGRectContainsPoint(screen, point)) {
            result = TLinkAXError(@"ui_point_out_of_bounds", @{@"pid": @(pid)});
            return;
        }
        TLinkAXElementRef root = NULL;
        TLinkAXElementRef hit = NULL;
        @try {
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            root = sTLinkAXCreateApp(pid);
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (!root) {
                result = TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
                return;
            }
            auto budget = TLinkCurrentNativeBudget();
            double timeout = budget ? budget->remainingSeconds(0.5) : 0.5;
            if (timeout <= 0 || TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, (float)timeout);
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            int error = sTLinkAXHitTest(root, &hit, (float)point.x, (float)point.y);
            CFRelease(root);
            root = NULL;
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            if (error != 0 || !hit) {
                result = TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid), @"ax_error": @(error)});
                return;
            }
            NSDictionary *element = TLinkAXSerializeElement(hit, screen, 0);
            CFRelease(hit);
            hit = NULL;
            if (TLinkNativeStopped()) {
                result = TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
                return;
            }
            result = @{
                @"ok": @YES,
                @"schema": @"ui_hit_test_v1",
                @"source": TLinkAXBackendName,
                @"bundle_id": bundleID ?: @"",
                @"pid": @(pid),
                @"point": @{@"x": @(point.x), @"y": @(point.y)},
                @"coordinate_space": @"points",
                @"element": element ?: @{},
                @"found": @(element != nil),
                @"context_changed": @NO,
            };
        } @catch (__unused NSException *exception) {
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        } @finally {
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
        }
    });
    if (TLinkNativeStopped()) return TLinkAXError(@"ui_cancelled_or_timed_out", @{@"pid": @(pid)});
    return result ?: TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid)});
}
