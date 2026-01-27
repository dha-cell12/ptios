#include "Process.h"
#include "Common.h"
#include "Screen.h"
#include <objc/message.h>
#include <dlfcn.h>
@import Foundation;
@import UIKit;
int (*openApp)(CFStringRef, Boolean);

static void* sbServices = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (id)applicationWithBundleIdentifier:(NSString*)bundleIdentifier;
@end

// Forward declaration (used by helper functions below).
static SBApplication *getApplicationForBundleId(NSString *bundleId);

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString*)identifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSString *bundleVersion;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
@end

static NSString *zx_pathFromURLLike(id urlLike)
{
    if (!urlLike || urlLike == (id)kCFNull) {
        return @"";
    }
    if ([urlLike isKindOfClass:[NSURL class]]) {
        return [(NSURL *)urlLike path] ?: @"";
    }
    if ([urlLike respondsToSelector:@selector(path)]) {
        NSString *p = ((NSString *(*)(id, SEL))objc_msgSend)(urlLike, @selector(path));
        return p ?: @"";
    }
    return @"";
}

static NSString *zx_safeString(id v)
{
    if (!v || v == (id)kCFNull) {
        return @"";
    }
    if ([v isKindOfClass:[NSString class]]) {
        return (NSString *)v;
    }
    return [v description] ?: @"";
}

static pid_t zx_pidForBundleId(NSString *bundleId)
{
    if (!bundleId || [bundleId length] == 0) {
        return 0;
    }
    SBApplication *app = getApplicationForBundleId(bundleId);
    if (!app) {
        return 0;
    }

    SEL pidSel = NSSelectorFromString(@"pid");
    if ([app respondsToSelector:pidSel]) {
        int pidVal = ((int (*)(id, SEL))objc_msgSend)(app, pidSel);
        return pidVal > 0 ? pidVal : 0;
    }
    SEL procIdSel = NSSelectorFromString(@"processIdentifier");
    if ([app respondsToSelector:procIdSel]) {
        int pidVal = ((int (*)(id, SEL))objc_msgSend)(app, procIdSel);
        return pidVal > 0 ? pidVal : 0;
    }
    SEL processSel = NSSelectorFromString(@"process");
    if ([app respondsToSelector:processSel]) {
        id proc = ((id (*)(id, SEL))objc_msgSend)(app, processSel);
        if (proc) {
            if ([proc respondsToSelector:procIdSel]) {
                int pidVal = ((int (*)(id, SEL))objc_msgSend)(proc, procIdSel);
                return pidVal > 0 ? pidVal : 0;
            }
            if ([proc respondsToSelector:pidSel]) {
                int pidVal = ((int (*)(id, SEL))objc_msgSend)(proc, pidSel);
                return pidVal > 0 ? pidVal : 0;
            }
        }
    }
    return 0;
}

int switchProcessForegroundFromRawData(UInt8 *eventData)
{
    return bringAppForeground([NSString stringWithFormat:@"%s", eventData]);
}

int bringAppForeground(NSString *appIdentifier)
{
    CFStringRef appBundleName = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@"), appIdentifier);
    //[NSString stringWithFormat:@"%s", eventData];
    NSLog(@"### com.zjx.springboard: Switch to application: %@", appBundleName);
    if (!openApp)
        openApp = (int(*)(CFStringRef, Boolean))dlsym(sbServices,"SBSLaunchApplicationWithIdentifier");

    return openApp(appBundleName, false);
}

id getFrontMostApplication()
{
    //TODO: might cause problem here. Both _accessibilityFrontMostApplication failed or front most application springboard will cause app be nil.
    __block id app = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        @try{
            SpringBoard *springboard = (SpringBoard*)[%c(SpringBoard) sharedApplication];
            app = [springboard _accessibilityFrontMostApplication];
            //NSLog(@"com.zjx.springboard: app: %@, id: %@", app, [app displayIdentifier]);
        }
        @catch (NSException *exception) {
            NSLog(@"com.zjx.springboard: Debug: %@", exception.reason);
        }
        });
    return app;
}

static SBApplication *getApplicationForBundleId(NSString *bundleId)
{
    SBApplicationController *controller = [NSClassFromString(@"SBApplicationController") sharedInstance];
    if (!controller)
    {
        return nil;
    }
    if ([controller respondsToSelector:@selector(applicationWithBundleIdentifier:)])
    {
        return [controller applicationWithBundleIdentifier:bundleId];
    }
    return nil;
}

NSString* frontMostAppId(void)
{
    SBApplication *app = getFrontMostApplication();
    if (!app)
    {
        return @"com.apple.springboard";
    }
    return app.bundleIdentifier ?: @"com.apple.springboard";
}

NSString* frontMostAppOrientation(void)
{
    return [NSString stringWithFormat:@"%d", [Screen getScreenOrientation]];
}

static BOOL sendTerminationToApp(SBApplication *app)
{
    if (!app)
    {
        return false;
    }

    SEL killSelector = NSSelectorFromString(@"kill");
    if ([app respondsToSelector:killSelector])
    {
        ((void (*)(id, SEL))objc_msgSend)(app, killSelector);
        return true;
    }

    SEL terminateSelector = NSSelectorFromString(@"terminate");
    if ([app respondsToSelector:terminateSelector])
    {
        ((void (*)(id, SEL))objc_msgSend)(app, terminateSelector);
        return true;
    }

    return false;
}

NSString* killAppFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    SBApplication *app = getApplicationForBundleId(bundleId);
    if (!sendTerminationToApp(app))
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to terminate app.\r\n"}];
        }
        return nil;
    }

    return @"";
}

NSString* appStateFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    SBApplication *app = getApplicationForBundleId(bundleId);
    if (!app)
    {
        return @"0";
    }

    SEL processStateSelector = NSSelectorFromString(@"processState");
    if ([app respondsToSelector:processStateSelector])
    {
        NSInteger state = ((NSInteger (*)(id, SEL))objc_msgSend)(app, processStateSelector);
        return [NSString stringWithFormat:@"%ld", (long)state];
    }

    SEL isRunningSelector = NSSelectorFromString(@"isRunning");
    if ([app respondsToSelector:isRunningSelector])
    {
        BOOL isRunning = ((BOOL (*)(id, SEL))objc_msgSend)(app, isRunningSelector);
        return isRunning ? @"1" : @"0";
    }

    return @"-1";
}

NSString* appInfoFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    NSString *name = proxy.localizedName ?: @"";
    NSString *shortVersion = proxy.shortVersionString ?: @"";
    NSString *bundleVersion = proxy.bundleVersion ?: @"";
    NSString *state = appStateFromRawData(eventData, nil) ?: @"-1";

    return [NSString stringWithFormat:@"%@;;%@;;%@;;%@;;%@", bundleId, name, shortVersion, bundleVersion, state];
}

NSString* appPidFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }
    pid_t pid = zx_pidForBundleId(bundleId);
    return [NSString stringWithFormat:@"%d", pid];
}

NSString* frontMostPidFromRawData(UInt8 *eventData, NSError **error)
{
    (void)eventData;
    NSString *bid = frontMostAppId();
    pid_t pid = zx_pidForBundleId(bid);
    return [NSString stringWithFormat:@"%d", pid];
}

NSString* appPathsFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *bundleId = [NSString stringWithFormat:@"%s", eventData];
    if ([bundleId length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Missing bundle identifier.\r\n"}];
        }
        return nil;
    }

    LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleId];
    if (!proxy) {
        return @";;";
    }

    id bundleURL = nil;
    if ([proxy respondsToSelector:NSSelectorFromString(@"bundleURL")]) {
        bundleURL = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"bundleURL"));
    } else {
        @try { bundleURL = [proxy valueForKey:@"bundleURL"]; } @catch (__unused NSException *e) {}
    }
    NSString *bundlePath = zx_pathFromURLLike(bundleURL);

    id dataURL = nil;
    if ([proxy respondsToSelector:NSSelectorFromString(@"dataContainerURL")]) {
        dataURL = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"dataContainerURL"));
    } else {
        @try { dataURL = [proxy valueForKey:@"dataContainerURL"]; } @catch (__unused NSException *e) {}
        if (!dataURL) {
            @try { dataURL = [proxy valueForKey:@"containerURL"]; } @catch (__unused NSException *e) {}
        }
    }
    NSString *dataPath = zx_pathFromURLLike(dataURL);

    return [NSString stringWithFormat:@"%@;;%@", bundlePath ?: @"", dataPath ?: @""];
}

NSString* listBundlesFromRawData(UInt8 *eventData, NSError **error)
{
    // eventData: "1" => with info
    BOOL withInfo = false;
    if (eventData) {
        NSString *raw = [NSString stringWithFormat:@"%s", eventData];
        withInfo = ([raw intValue] == 1);
    }

    Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsCls || ![wsCls respondsToSelector:@selector(defaultWorkspace)]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;LSApplicationWorkspace unavailable.\r\n"}];
        }
        return nil;
    }
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsCls, @selector(defaultWorkspace));
    if (!ws) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to get LSApplicationWorkspace.\r\n"}];
        }
        return nil;
    }

    NSArray *apps = nil;
    SEL allInstalledSel = NSSelectorFromString(@"allInstalledApplications");
    SEL allSel = NSSelectorFromString(@"allApplications");
    if ([ws respondsToSelector:allInstalledSel]) {
        apps = ((NSArray *(*)(id, SEL))objc_msgSend)(ws, allInstalledSel);
    } else if ([ws respondsToSelector:allSel]) {
        apps = ((NSArray *(*)(id, SEL))objc_msgSend)(ws, allSel);
    }
    if (!apps) {
        apps = @[];
    }

    if (!withInfo) {
        NSMutableArray<NSString *> *bids = [NSMutableArray arrayWithCapacity:[apps count]];
        for (id p in apps) {
            NSString *bid = nil;
            if ([p respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
                bid = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleIdentifier"));
            } else {
                @try { bid = [p valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
            }
            if (bid && [bid length] > 0) {
                [bids addObject:bid];
            }
        }
        return [bids componentsJoinedByString:@",,"];
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithCapacity:[apps count]];
    for (id p in apps) {
        NSString *bid = nil;
        if ([p respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
            bid = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleIdentifier"));
        } else {
            @try { bid = [p valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
        }
        if (!bid || [bid length] == 0) {
            continue;
        }

        NSString *name = @"";
        NSString *shortVersion = @"";
        NSString *bundleVersion = @"";
        if ([p respondsToSelector:NSSelectorFromString(@"localizedName")]) {
            name = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"localizedName")) ?: @"";
        } else {
            @try { name = zx_safeString([p valueForKey:@"localizedName"]); } @catch (__unused NSException *e) {}
        }
        if ([p respondsToSelector:NSSelectorFromString(@"shortVersionString")]) {
            shortVersion = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"shortVersionString")) ?: @"";
        } else {
            @try { shortVersion = zx_safeString([p valueForKey:@"shortVersionString"]); } @catch (__unused NSException *e) {}
        }
        if ([p respondsToSelector:NSSelectorFromString(@"bundleVersion")]) {
            bundleVersion = ((NSString *(*)(id, SEL))objc_msgSend)(p, NSSelectorFromString(@"bundleVersion")) ?: @"";
        } else {
            @try { bundleVersion = zx_safeString([p valueForKey:@"bundleVersion"]); } @catch (__unused NSException *e) {}
        }

        [items addObject:@{
            @"bundle_id": bid,
            @"name": name ?: @"",
            @"short_version": shortVersion ?: @"",
            @"bundle_version": bundleVersion ?: @"",
        }];
    }

    NSDictionary *obj = @{@"items": items};
    NSError *jsonErr = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&jsonErr];
    if (!jsonData || jsonErr) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to encode bundles JSON.\r\n"}];
        }
        return nil;
    }
    return [jsonData base64EncodedStringWithOptions:0];
}
