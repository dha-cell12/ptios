// macOS-only: compile the actual player with Foundation/dispatch, fake UI and native task/runtime hooks.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <os/lock.h>
#import "../pccontrol/ScriptPlayer.h"
#import "../pccontrol/TLinkTaskContext.h"
#import "../shared/TLinkLicenseVerifier.h"
#include "../shared/TLinkPlaybackState.h"
#include "../shared/TLinkRawPlayback.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <unistd.h>
#define CGRectMake NSMakeRect
#define CGRectZero NSZeroRect
#define TASK_USLEEP 18
static NSString *SCRIPT_PLAY_CONFIG_PATH;
static const double UIWindowLevelStatusBar = 1;
@interface TestLayer : NSObject
@property (nonatomic) double cornerRadius;
@end
@implementation TestLayer
@end
@interface UIColor : NSObject
+ (instancetype)clearColor;
+ (instancetype)greenColor;
+ (instancetype)orangeColor;
@end
@implementation UIColor
+ (instancetype)clearColor { return [[self alloc] init]; }
+ (instancetype)greenColor { return [[self alloc] init]; }
+ (instancetype)orangeColor { return [[self alloc] init]; }
@end
@interface UIView : NSObject
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic, strong) TestLayer *layer;
- (instancetype)initWithFrame:(NSRect)frame;
- (void)addSubview:(UIView *)view;
@end
@implementation UIView
- (instancetype)initWithFrame:(NSRect)frame { (void)frame; self = [super init]; if (self) _layer = [[TestLayer alloc] init]; return self; }
- (void)addSubview:(UIView *)view { (void)view; }
@end
@interface UIWindow : UIView
@property (nonatomic) BOOL hidden;
@property (nonatomic) double windowLevel;
@end
@implementation UIWindow
@end

static std::atomic_bool holdTask{false}, holdHistory{false}, holdPreparation{false}, holdJS{false}, allowLicense{true};
static std::atomic_int tasks{0}, upEvents{0}, historyBegins{0}, historyFinishes{0}, runtimeStops{0};
static dispatch_semaphore_t taskEntered, taskRelease, historyEntered, historyRelease, prepareEntered, prepareRelease;
static dispatch_semaphore_t waitEntered, jsEntered, jsRelease;
static NSString *lastError, *lastState;
static void wait(dispatch_semaphore_t gate) { assert(dispatch_semaphore_wait(gate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0); }
static void setLastScriptError(NSString *message) { lastError = [message copy]; }
static NSString *getLastScriptError(void) { return lastError ?: @""; }
static void showAlertBox(NSString *title, NSString *message, int code) { (void)title; (void)message; (void)code; }
static int bringAppForeground(NSString *app) { (void)app; return 0; }
static BOOL TLinkRootfullLicenseComponentAllowed(NSString *feature, NSString *source, NSString **denial) {
    (void)feature; (void)source; if (!allowLicense && denial) *denial = @"license_required"; return allowLicense.load();
}
static std::atomic<bool> fastAuthorization{false};
static TLinkLicenseAutomationAuthorization capturedAuthorization;
static NSString *capturedOwner;
TLinkLicenseAutomationAuthorization TLinkLicenseAutomationAuthorizationForOwner(NSString *owner) {
    NSString *bound = [owner copy];
    return ^BOOL(NSString *candidate) { return fastAuthorization.load() && allowLicense.load() && [bound isEqual:candidate]; };
}
static BOOL TLinkRootfullLicenseTaskAllowed(int task, NSString **denial) {
    if (task == 18) dispatch_semaphore_signal(waitEntered);
    if (!allowLicense && denial) *denial = @"license_required";
    return allowLicense.load();
}
static NSDictionary *TLinkRunHistoryBegin(NSString *runtime, NSString *bundle, NSString *entry, NSDictionary *settings) {
    (void)runtime; (void)bundle; (void)entry; (void)settings;
    if (holdPreparation) { dispatch_semaphore_signal(prepareEntered); wait(prepareRelease); }
    return @{@"run_id": [NSString stringWithFormat:@"run%d", ++historyBegins]};
}
static NSString *TLinkRunHistoryEvidencePath(void) { return NSTemporaryDirectory(); }
static void TLinkRunHistoryFinish(NSString *run, NSString *state, NSString *error, NSArray *lines, NSString *console,
                                  NSString *screenshot, NSString *captureError, NSDictionary *metadata) {
    (void)run; (void)error; (void)lines; (void)console; (void)screenshot; (void)captureError; (void)metadata;
    if (holdHistory) { dispatch_semaphore_signal(historyEntered); wait(historyRelease); }
    lastState = [state copy]; ++historyFinishes;
}
@interface Screen : NSObject
+ (NSString *)screenShotToPath:(NSString *)path region:(NSRect)region error:(NSError **)error;
@end
@implementation Screen
+ (NSString *)screenShotToPath:(NSString *)path region:(NSRect)region error:(NSError **)error {
    (void)path; (void)region; (void)error; return nil;
}
@end
@interface TLinkautoJSRuntime : NSObject
- (BOOL)runScriptAtPath:(NSString *)path bundlePath:(NSString *)bundle manifest:(NSDictionary *)manifest
               context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
- (void)requestStop;
- (NSString *)currentConsoleLogPath;
@end
@implementation TLinkautoJSRuntime
- (BOOL)runScriptAtPath:(NSString *)path bundlePath:(NSString *)bundle manifest:(NSDictionary *)manifest
               context:(TLinkTaskExecutionContext *)context error:(NSError **)error {
    (void)path; (void)bundle; (void)manifest; (void)error;
    if (holdJS) { dispatch_semaphore_signal(jsEntered); wait(jsRelease); }
    return ![context.cancellationToken isCancelled];
}
- (void)requestStop { ++runtimeStops; }
- (NSString *)currentConsoleLogPath { return @""; }
@end
static bool performTouchFromRawData(const uint8_t *bytes, size_t length) {
    TLinkTouchPoint points[kTLinkTouchMaxCount]; int count = 0;
    assert(TLinkParseTouchPayload(bytes, length, points, &count));
    for (int i = 0; i < count; ++i) if (points[i].type == 0) ++upEvents;
    return true;
}
static void processTaskWithContext(UInt8 *bytes, size_t length, void *stream, TLinkTaskExecutionContext *context) {
    (void)stream;
    ++tasks;
    if (fastAuthorization.load()) { capturedAuthorization = [context.allowsAutomationForOwner copy]; capturedOwner = [context.ownerSessionId copy]; }
    if (length >= 2 && bytes[0] == '1' && bytes[1] == '0') {
        if (performTouchFromRawData(bytes + 2, length - 2) && context.didInjectTouchPayload)
            context.didInjectTouchPayload(bytes + 2, length - 2);
    }
    if (holdTask) { dispatch_semaphore_signal(taskEntered); wait(taskRelease); }
}
#include "PlaybackRuntimeUnderTest.inc"

static NSString *bundle(NSString *root, NSString *name, NSString *contents, NSString *extension) {
    NSString *path = [root stringByAppendingPathComponent:name];
    assert([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *entry = [@"main." stringByAppendingString:extension];
    NSData *info = [NSPropertyListSerialization dataWithPropertyList:@{@"Entry": entry, @"FrontApp": @"test"}
        format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    assert([info writeToFile:[path stringByAppendingPathComponent:@"info.plist"] atomically:YES]);
    assert([contents writeToFile:[path stringByAppendingPathComponent:entry] atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    return path;
}
static void start(ScriptPlayer *player, NSString *path, int repeats = 0, double delay = 0) {
    NSError *error = nil;
    assert([player playPath:path repeatTime:repeats interval:delay speed:1 switchApp:NO error:&error] == 0 && !error);
}
static void reject(ScriptPlayer *player, NSString *path) {
    NSError *error = nil;
    assert([player playPath:path repeatTime:0 interval:0 speed:1 switchApp:NO error:&error] == -1 && error);
}
static void stop(ScriptPlayer *player) {
    NSError *error = nil; [player forceStop:&error]; assert(!error);
}
static void idle(ScriptPlayer *player) {
    for (int i = 0; i < 1000 && [player isPlaying]; ++i) usleep(5000);
    assert(![player isPlaying] && [player canStartScheduledScript]);
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    assert(argc == 2);
    taskEntered = dispatch_semaphore_create(0); taskRelease = dispatch_semaphore_create(0);
    historyEntered = dispatch_semaphore_create(0); historyRelease = dispatch_semaphore_create(0);
    prepareEntered = dispatch_semaphore_create(0); prepareRelease = dispatch_semaphore_create(0);
    waitEntered = dispatch_semaphore_create(0); jsEntered = dispatch_semaphore_create(0); jsRelease = dispatch_semaphore_create(0);
    NSString *root = [NSString stringWithUTF8String:argv[1]];
    SCRIPT_PLAY_CONFIG_PATH = [root stringByAppendingPathComponent:@"absent-settings.plist"];
    NSString *once = bundle(root, @"once", @"12tick\n", @"raw");
    NSString *sleeping = bundle(root, @"sleep", @"182000000000\n12never\n", @"raw");
    NSString *touch = bundle(root, @"touch", @"1011000010000200\n12blocked\n", @"raw");
    NSString *js = bundle(root, @"js", @"// fake runtime", @"js");
    ScriptPlayer *player = [[ScriptPlayer alloc] init];

    holdTask = true; holdHistory = true;
    start(player, once); wait(taskEntered);
    stop(player); stop(player); reject(player, once);
    assert([player isPlaying] && ![player canStartScheduledScript]);
    dispatch_semaphore_signal(taskRelease); wait(historyEntered);
    assert([player isPlaying]); reject(player, once); // Finishing owns state through history I/O.
    holdTask = false; holdHistory = false;
    dispatch_semaphore_signal(historyRelease); idle(player);
    assert([lastState isEqualToString:@"cancelled"]);

    int before = tasks.load(); start(player, once, 2, 0.001); idle(player);
    assert(tasks.load() == before + 3);
    start(player, once, 100, 3600);
    for (int i = 0; i < 1000; ++i) {
        if ([[player licenseRuntimeDiagnostics][@"playback_phase"] intValue] == (int)TLinkPlaybackPhase::Waiting) break;
        usleep(5000);
    }
    assert([[player licenseRuntimeDiagnostics][@"playback_phase"] intValue] == (int)TLinkPlaybackPhase::Waiting);
    before = tasks.load(); stop(player); idle(player); assert(tasks.load() == before);

    start(player, sleeping); wait(waitEntered); stop(player); idle(player);
    assert([lastState isEqualToString:@"cancelled"]);

    holdTask = true; start(player, touch); wait(taskEntered);
    stop(player); reject(player, once); holdTask = false; dispatch_semaphore_signal(taskRelease); idle(player);
    assert(upEvents == 1); // DOWN-only recording is released before idle, without starting another task.

    holdJS = true; start(player, js); wait(jsEntered); stop(player); reject(player, once);
    assert(runtimeStops > 0 && [player isPlaying]); holdJS = false;
    dispatch_semaphore_signal(jsRelease); idle(player);
    start(player, once); idle(player); // JS completion cannot erase the next RAW session.

    holdPreparation = true;
    dispatch_semaphore_t prepared = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool { start(player, once); dispatch_semaphore_signal(prepared); }
    });
    wait(prepareEntered); stop(player); stop(player); reject(player, once);
    holdPreparation = false; dispatch_semaphore_signal(prepareRelease); wait(prepared); idle(player);

    NSError *error = nil;
    assert([player playPath:[root stringByAppendingPathComponent:@"missing"] repeatTime:0 interval:0 speed:1 switchApp:NO error:&error] == -1 && error);
    idle(player);
    allowLicense = false; start(player, sleeping); idle(player); allowLicense = true;
    assert([lastState isEqualToString:@"license_revoked"]);
    start(player, once); idle(player);
    fastAuthorization = true; holdTask = true; start(player, once); wait(taskEntered);
    assert(capturedAuthorization && capturedAuthorization(capturedOwner) && !capturedAuthorization(@"wrong-owner"));
    TLinkLicenseAutomationAuthorization oldAuthorization = [capturedAuthorization copy]; NSString *oldOwner = [capturedOwner copy];
    stop(player); assert(!oldAuthorization(oldOwner));
    holdTask = false; dispatch_semaphore_signal(taskRelease); idle(player);
    start(player, once); idle(player); assert(!capturedAuthorization(capturedOwner) && !oldAuthorization(oldOwner));
    assert(![oldOwner isEqual:capturedOwner]); fastAuthorization = false;
    assert(historyBegins == historyFinishes);
    // Drain queued fake-UI updates after several completed generations. None changes model state.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    assert(![player isPlaying]);
    std::puts("Playback dispatch/ARC passed: stop during task/preparation/history/wait, repeat cancellation, touch release, JS/RAW isolation, license denial and recovery.");
} }
