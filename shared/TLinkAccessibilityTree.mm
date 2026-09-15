#import "TLinkAccessibilityTree.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import <math.h>
#import <mach/mach.h>

NSString *const TLinkAXSnapshotSchema = @"ui_snapshot_v1";
NSString *const TLinkAXBackendName = @"axruntime_numeric_v1";

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
    NSArray<NSString *> *names = @[
        @"com.apple.private.accessibility.inspection",
        @"com.apple.accessibility.api",
        @"com.apple.private.accessibility.look-me-up-setup",
    ];
    NSMutableDictionary *entitlements = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        id value = TLinkAXEntitlementValue(name);
        entitlements[name] = @([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
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
        @"entitlements": entitlements,
        @"lock_state": lockState,
        @"default_max_elements": @250,
        @"hard_max_elements": @1000,
        @"default_timeout_ms": @1500,
    };
}

static NSString *TLinkAXFrontmostBundleID(void)
{
    void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
    if (!sbs) return nil;
    const char *symbols[] = {
        "SBSCopyFrontmostApplicationDisplayIdentifier",
        "SBSCopyFrontmostApplicationDisplayIdentifierForMainDisplay",
        "SBSGetMostElevatedApplicationBundleIdentifier",
        "SBSGetMostElevatedApplicationDisplayIdentifier",
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

NSDictionary *TLinkAXCopyFrontmostContext(void)
{
    NSString *bundleID = TLinkAXFrontmostBundleID();
    if (bundleID.length == 0) {
        return TLinkAXError(@"ui_frontmost_bundle_unavailable", nil);
    }
    pid_t pid = TLinkAXPIDForBundleID(bundleID);
    if (pid <= 0) {
        return TLinkAXError(@"ui_frontmost_pid_unavailable", @{@"bundle_id": bundleID});
    }
    return @{
        @"ok": @YES,
        @"bundle_id": bundleID,
        @"pid": @(pid),
        @"source": @"springboardservices_process_scan_v1",
    };
}

static id TLinkAXAttribute(TLinkAXElementRef element, uint32_t key, int *errorOut)
{
    if (!element || !sTLinkAXCopyAttribute) return nil;
    CFTypeRef value = NULL;
    int error = sTLinkAXCopyAttribute(element, (CFStringRef)(uintptr_t)key, &value);
    if (errorOut) *errorOut = error;
    if (error != 0) {
        if (value) CFRelease(value);
        return nil;
    }
    return value ? CFBridgingRelease(value) : nil;
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
                                             NSUInteger index)
{
    if (!element) return nil;
    @try {
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(element, 0.10f);
        id frameValue = TLinkAXAttribute(element, 2003, NULL);
        CGRect frame = CGRectZero;
        if (!frameValue ||
            !sTLinkAXValueGetValue((__bridge CFTypeRef)frameValue, 3, &frame) ||
            !isfinite(frame.origin.x) || !isfinite(frame.origin.y) ||
            !isfinite(frame.size.width) || !isfinite(frame.size.height)) {
            return nil;
        }

        id label = TLinkAXAttribute(element, 2001, NULL);
        id value = TLinkAXAttribute(element, 2006, NULL);
        id identifier = TLinkAXAttribute(element, 5019, NULL);
        id traitsValue = TLinkAXAttribute(element, 2004, NULL);
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
        id pointValue = TLinkAXAttribute(element, 2007, NULL);
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
    id timeoutValue = options[@"timeout_ms"] ?: options[@"timeoutMs"];
    id visibleValue = options[@"visible_only"] ?: options[@"visibleOnly"];
    id clickableValue = options[@"clickable_only"] ?: options[@"clickableOnly"];
    NSInteger maxElements = TLinkAXBoundedInteger(maxElementsValue, 250, 1, 1000);
    NSInteger timeoutMs = TLinkAXBoundedInteger(timeoutValue, 1500, 100, 3000);
    BOOL visibleOnly = visibleValue ? [visibleValue boolValue] : YES;
    BOOL clickableOnly = [clickableValue boolValue];
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime deadline = started + ((double)timeoutMs / 1000.0);

    TLinkAXElementRef root = NULL;
    CFTypeRef rawElements = NULL;
    @try {
        root = sTLinkAXCreateApp(pid);
        if (!root) return TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
        if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, MIN(0.5f, (float)timeoutMs / 1000.0f));
        int error = sTLinkAXCopyAttribute(root, (CFStringRef)(uintptr_t)3015, &rawElements);
        CFRelease(root);
        root = NULL;
        if (error != 0 || !rawElements || CFGetTypeID(rawElements) != CFArrayGetTypeID()) {
            if (rawElements) CFRelease(rawElements);
            return TLinkAXError(@"ui_element_query_failed", @{@"pid": @(pid), @"ax_error": @(error)});
        }
    } @catch (__unused NSException *exception) {
        if (root) CFRelease(root);
        if (rawElements) CFRelease(rawElements);
        return TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
    }

    NSArray *elements = CFBridgingRelease(rawElements);
    CGRect screen = [UIScreen mainScreen].bounds;
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:MIN((NSUInteger)maxElements, elements.count)];
    NSUInteger scanned = 0;
    NSUInteger serializationFailures = 0;
    BOOL truncated = NO;
    for (id object in elements) {
        if (rows.count >= (NSUInteger)maxElements || CFAbsoluteTimeGetCurrent() >= deadline) {
            truncated = YES;
            break;
        }
        scanned++;
        NSDictionary *node = TLinkAXSerializeElement((__bridge TLinkAXElementRef)object, screen, scanned - 1);
        if (!node) {
            serializationFailures++;
            continue;
        }
        if (visibleOnly && ![node[@"intersects_screen"] boolValue]) continue;
        if (clickableOnly && ![node[@"clickable"] boolValue]) continue;
        [rows addObject:node];
    }
    NSTimeInterval durationMs = (CFAbsoluteTimeGetCurrent() - started) * 1000.0;
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
    __block NSDictionary *result = nil;
    dispatch_sync(TLinkAXQueue(), ^{
        result = TLinkAXCopySnapshotUnlocked(pid, bundleID ?: @"", options ?: @{});
    });
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
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *element in snapshot[@"elements"]) {
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
        [matches addObject:element];
    }
    NSDictionary *element = requestedIndex < (NSInteger)matches.count ? matches[(NSUInteger)requestedIndex] : nil;
    NSMutableDictionary *result = [snapshot mutableCopy];
    [result removeObjectForKey:@"elements"];
    result[@"schema"] = @"ui_find_v1";
    result[@"selector"] = selector ?: @{};
    result[@"found"] = @(element != nil);
    result[@"match_count"] = @(matches.count);
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
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[@"max_elements"] = selector[@"max_elements"] ?: selector[@"maxElements"] ?: @250;
    options[@"timeout_ms"] = selector[@"timeout_ms"] ?: selector[@"timeoutMs"] ?: @1500;
    options[@"allow_locked"] = selector[@"allow_locked"] ?: selector[@"allowLocked"] ?: @NO;
    __block NSDictionary *result = nil;
    dispatch_sync(TLinkAXQueue(), ^{
        NSDictionary *snapshot = TLinkAXCopySnapshotUnlocked(pid, bundleID ?: @"", options);
        result = TLinkAXFindInSnapshot(snapshot, selector);
    });
    return result ?: TLinkAXError(@"ui_find_failed", @{@"pid": @(pid)});
}

NSDictionary *TLinkAXElementAtPoint(pid_t pid, NSString *bundleID, CGPoint point)
{
    if (pid <= 0 || !isfinite(point.x) || !isfinite(point.y)) {
        return TLinkAXError(@"ui_hit_test_invalid_request", @{@"pid": @(pid)});
    }
    __block NSDictionary *result = nil;
    dispatch_sync(TLinkAXQueue(), ^{
        NSDictionary *lockState = TLinkAXLockState();
        if ([lockState[@"screen_off"] boolValue]) {
            result = TLinkAXError(@"ui_screen_off", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if ([lockState[@"locked"] boolValue]) {
            result = TLinkAXError(@"ui_screen_locked", @{@"pid": @(pid), @"lock_state": lockState});
            return;
        }
        if (!TLinkAXPrepare() || !sTLinkAXHitTest) {
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
            root = sTLinkAXCreateApp(pid);
            if (!root) {
                result = TLinkAXError(@"ui_ax_application_unavailable", @{@"pid": @(pid)});
                return;
            }
            if (sTLinkAXSetTimeout) sTLinkAXSetTimeout(root, 0.5f);
            int error = sTLinkAXHitTest(root, &hit, (float)point.x, (float)point.y);
            CFRelease(root);
            root = NULL;
            if (error != 0 || !hit) {
                if (hit) CFRelease(hit);
                result = TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid), @"ax_error": @(error)});
                return;
            }
            NSDictionary *element = TLinkAXSerializeElement(hit, screen, 0);
            CFRelease(hit);
            hit = NULL;
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
            if (root) CFRelease(root);
            if (hit) CFRelease(hit);
            result = TLinkAXError(@"ui_ax_exception", @{@"pid": @(pid)});
        }
    });
    return result ?: TLinkAXError(@"ui_hit_test_failed", @{@"pid": @(pid)});
}
