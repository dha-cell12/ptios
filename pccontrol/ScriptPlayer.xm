#import "ScriptPlayer.h"
#import "TLinkDiagnostic.h"
#include "Play.h"
#include "SocketServer.h"
#include "Process.h"
#include "Task.h"
#include "AlertBox.h"
#include "Config.h"
#include "Common.h"
#include "RuntimeUtils.h"
#import "TLinkautoJSRuntime.h"
#import "TLinkTaskContext.h"
#import "../shared/TLinkRootfullLicensePolicy.h"
#import "../shared/TLinkRunHistory.h"
#import "Screen.h"
#include <os/lock.h>
#include "../shared/TLinkPlaybackState.h"
#include "../shared/TLinkRawPlayback.h"
#include "Touch.h"

// BEGIN playback session implementation (compiled with runtime doubles by the macOS harness).
@interface TLinkPlaybackSession : TLinkScriptSession {
@public
    TLinkRawTouches touches;
}
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *entryPath;
@property (nonatomic, copy) NSString *foregroundApp;
@property (nonatomic, copy) NSDictionary *manifest;
@property (nonatomic, assign) int repeatsRemaining;
@property (nonatomic, assign) uint64_t repeatDelayNs;
@property (nonatomic, assign) double speed;
@property (nonatomic, assign) BOOL switchApp;
@property (nonatomic, assign) BOOL raw;
@property (nonatomic, assign) BOOL preparing;
@property (nonatomic, assign) BOOL licenseRevoked;
@property (nonatomic, strong) dispatch_semaphore_t wake;
@property (nonatomic, copy) NSString *historyRunId;
@property (nonatomic, copy) NSString *consoleLogPath;
@end
@implementation TLinkPlaybackSession
@end

static NSError *tlinkPlaybackError(NSString *message) {
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"-1;;%@\r\n", message]}];
}

static BOOL tlinkautoJavaScriptRuntimeEnabled(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:SCRIPT_PLAY_CONFIG_PATH]) {
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:SCRIPT_PLAY_CONFIG_PATH];
        id value = config[@"javascript_runtime_enabled"] ?: config[@"javascriptRuntimeEnabled"];
        if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    }
    return YES;
}

static NSDictionary *tlinkautoReadManifest(NSString *bundlePath) {
    NSString *manifestPath = [bundlePath stringByAppendingPathComponent:@"manifest.json"];
    NSData *data = [NSData dataWithContentsOfFile:manifestPath];
    if (!data) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) return nil;
    return (NSDictionary *)obj;
}

static NSString *tlinkautoStringValue(id value) {
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    return nil;
}

@implementation ScriptPlayer {
    os_unfair_lock _playerLock;
    TLinkPlaybackState _playback;
    TLinkPlaybackSession *_currentSession;
    TLinkautoJSRuntime *_currentRuntime;
    dispatch_queue_t _playbackQueue;
    dispatch_source_t _repeatTimer;
    dispatch_source_t _licenseHeartbeat;
    uint64_t _licenseHeartbeatGeneration;
    uint64_t _licenseHeartbeatCheckCount;
    uint64_t _licenseRevocationCount;
    uint64_t _lastCompletedGeneration;
    // Main-thread-only UI. A queued cleanup may only hide its own generation's window.
    UIWindow *_playIndicator;
    UIView *circleView;
    uint64_t _indicatorGeneration;
    // Legacy setters configure an idle launch only. Production Play.xm submits a whole tuple.
    NSString *scriptBundlePath;
    int repeatTime;
    double interval;
    double speed;
    BOOL switchAppBeforePlaying;
}

- (id)init {
    self = [super init];
    if (self) {
        _playerLock = OS_UNFAIR_LOCK_INIT;
        _playbackQueue = dispatch_queue_create("com.tlinkauto.playback", DISPATCH_QUEUE_SERIAL);
        speed = 1;
    }
    return self;
}
- (id)initWithPath:(NSString *)path {
    self = [self init];
    if (self) scriptBundlePath = [path copy];
    return self;
}
- (BOOL)isPlaying {
    os_unfair_lock_lock(&_playerLock);
    BOOL busy = _playback.busy();
    os_unfair_lock_unlock(&_playerLock);
    return busy;
}
- (BOOL)canStartScheduledScript {
    os_unfair_lock_lock(&_playerLock);
    BOOL allowed = !_playback.busy();
    os_unfair_lock_unlock(&_playerLock);
    return allowed;
}
- (NSString *)getCurrentBundlePath {
    os_unfair_lock_lock(&_playerLock);
    NSString *path = _currentSession.bundlePath ?: @"";
    os_unfair_lock_unlock(&_playerLock);
    return path;
}
- (void)setPath:(NSString *)path {
    os_unfair_lock_lock(&_playerLock);
    if (!_playback.busy()) scriptBundlePath = [path copy];
    os_unfair_lock_unlock(&_playerLock);
}
- (void)setRepeatTime:(int)value {
    os_unfair_lock_lock(&_playerLock);
    if (!_playback.busy()) repeatTime = value;
    os_unfair_lock_unlock(&_playerLock);
}
- (void)setInterval:(float)value {
    os_unfair_lock_lock(&_playerLock);
    if (!_playback.busy()) interval = value;
    os_unfair_lock_unlock(&_playerLock);
}
- (void)setSpeed:(float)value {
    os_unfair_lock_lock(&_playerLock);
    if (!_playback.busy()) speed = value;
    os_unfair_lock_unlock(&_playerLock);
}
- (void)setSwitchApp:(BOOL)value {
    os_unfair_lock_lock(&_playerLock);
    if (!_playback.busy()) switchAppBeforePlaying = value;
    os_unfair_lock_unlock(&_playerLock);
}
- (int)play:(NSError **)error {
    os_unfair_lock_lock(&_playerLock);
    NSString *path = scriptBundlePath;
    int repeats = repeatTime;
    double delay = interval, playSpeed = speed;
    BOOL switchApp = switchAppBeforePlaying;
    os_unfair_lock_unlock(&_playerLock);
    return [self playPath:path repeatTime:repeats interval:delay speed:playSpeed switchApp:switchApp error:error];
}

- (NSDictionary *)licenseRuntimeDiagnostics {
    os_unfair_lock_lock(&_playerLock);
    NSDictionary *diagnostics = @{
        @"heartbeat_active": @(_licenseHeartbeat != nil), @"heartbeat_interval_ms": @1000,
        @"generation": @(_licenseHeartbeatGeneration), @"check_count": @(_licenseHeartbeatCheckCount),
        @"revocation_count": @(_licenseRevocationCount),
        @"revoked_current_run": @(_currentSession.licenseRevoked),
        @"playback_generation": @(_currentSession.generation),
        @"playback_phase": @((int)_playback.phase()),
    };
    os_unfair_lock_unlock(&_playerLock);
    return diagnostics;
}

- (void)updateIndicatorForSession:(TLinkPlaybackSession *)session waiting:(BOOL)waiting {
    dispatch_async(dispatch_get_main_queue(), ^{
        os_unfair_lock_lock(&self->_playerLock);
        BOOL current = self->_currentSession == session && ![session.cancellationToken isCancelled] &&
                       self->_playback.phase() != TLinkPlaybackPhase::Finishing;
        os_unfair_lock_unlock(&self->_playerLock);
        if (!current) return;
        if (self->_indicatorGeneration != session.generation) {
            self->_playIndicator.hidden = YES;
            self->_playIndicator = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
            self->_playIndicator.windowLevel = UIWindowLevelStatusBar;
            self->_playIndicator.backgroundColor = [UIColor clearColor];
            self->_playIndicator.userInteractionEnabled = NO;
            self->circleView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
            self->circleView.layer.cornerRadius = 10;
            [self->_playIndicator addSubview:self->circleView];
            self->_indicatorGeneration = session.generation;
        }
        self->circleView.backgroundColor = waiting ? [UIColor orangeColor] : [UIColor greenColor];
        self->_playIndicator.hidden = NO;
    });
}
- (void)hideIndicatorForSession:(TLinkPlaybackSession *)session {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_indicatorGeneration != session.generation) return;
        self->_playIndicator.hidden = YES;
        self->_playIndicator = nil;
        self->circleView = nil;
        self->_indicatorGeneration = 0;
    });
}
- (void)showError:(NSString *)message forSession:(TLinkPlaybackSession *)session {
    dispatch_async(dispatch_get_main_queue(), ^{
        os_unfair_lock_lock(&self->_playerLock);
        BOOL current = self->_currentSession == session ||
            (!self->_currentSession && self->_lastCompletedGeneration == session.generation);
        os_unfair_lock_unlock(&self->_playerLock);
        if (current) showAlertBox(session.raw ? @"Error" : @"JavaScript Error", message, 999);
    });
}

- (void)beginRunHistoryForSession:(TLinkPlaybackSession *)session entryPath:(NSString *)entryPath {
    NSDictionary *record = TLinkRunHistoryBegin(@"rootfull", session.bundlePath, entryPath, @{
        @"repeat_times": @(session.repeatsRemaining),
        @"interval": @((double)session.repeatDelayNs / NSEC_PER_SEC), @"speed": @(session.speed),
    });
    session.historyRunId = [record[@"run_id"] copy];
}
- (void)finishRunHistoryForSession:(TLinkPlaybackSession *)session state:(NSString *)state error:(NSString *)error {
    NSString *runId = session.historyRunId;
    if (runId.length == 0) return;
    session.historyRunId = nil;
    NSString *screenshotPath = @"", *screenshotError = @"";
    if ([state isEqualToString:@"failed"] || [state isEqualToString:@"license_revoked"]) {
        screenshotPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.png", runId]];
        NSError *captureError = nil;
        NSString *saved = [Screen screenShotToPath:screenshotPath region:CGRectZero error:&captureError];
        if (saved.length == 0) { screenshotError = captureError.localizedDescription ?: @"capture_failed"; screenshotPath = @""; }
    }
    TLinkRunHistoryFinish(runId, state, error ?: @"", @[], session.consoleLogPath ?: @"",
                         screenshotPath, screenshotError, @{});
}

- (void)stopLicenseHeartbeatForGeneration:(uint64_t)generation {
    os_unfair_lock_lock(&_playerLock);
    dispatch_source_t timer = nil;
    if (_licenseHeartbeatGeneration == generation) {
        timer = _licenseHeartbeat; _licenseHeartbeat = nil; _licenseHeartbeatGeneration = 0;
    }
    os_unfair_lock_unlock(&_playerLock);
    if (timer) dispatch_source_cancel(timer);
}
- (void)requestStopSession:(TLinkPlaybackSession *)session revoked:(BOOL)revoked message:(NSString *)message {
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session || !_playback.stop(session.generation)) {
        os_unfair_lock_unlock(&_playerLock); return;
    }
    if (revoked && !session.licenseRevoked) {
        session.licenseRevoked = YES;
        _licenseRevocationCount++;
        setLastScriptError(message ?: @"license_revoked_during_execution");
    }
    [session.cancellationToken cancel];
    dispatch_source_t repeat = _repeatTimer; _repeatTimer = nil;
    TLinkautoJSRuntime *runtime = _currentRuntime;
    BOOL preparing = session.preparing;
    os_unfair_lock_unlock(&_playerLock);
    if (repeat) dispatch_source_cancel(repeat);
    [self stopLicenseHeartbeatForGeneration:session.generation];
    dispatch_semaphore_signal(session.wake);
    if (runtime) [runtime requestStop];
    // Preparing callers retain ownership until their file/history setup has returned.
    // All other cleanup queues behind the active RAW/JS iteration, never ahead of it.
    if (!preparing) dispatch_async(_playbackQueue, ^{
        @autoreleasepool { [self finishSessionIfCurrent:session state:@"cancelled" error:@""]; }
    });
}
- (void)handleLicenseHeartbeatForGeneration:(uint64_t)generation {
    os_unfair_lock_lock(&_playerLock);
    TLinkPlaybackSession *session = _currentSession;
    BOOL current = session && session.generation == generation && _licenseHeartbeat != nil &&
        _playback.phase() != TLinkPlaybackPhase::Finishing && ![session.cancellationToken isCancelled];
    if (current) _licenseHeartbeatCheckCount++;
    os_unfair_lock_unlock(&_playerLock);
    if (!current) return;
    NSString *denial = nil;
    if (TLinkRootfullLicenseComponentAllowed(@"script", @"script_runtime", &denial)) return;
    NSString *message = [NSString stringWithFormat:@"license_revoked_during_execution %@", denial ?: @"license_required"];
    [self requestStopSession:session revoked:YES message:message];
}
- (void)startLicenseHeartbeatForSession:(TLinkPlaybackSession *)session {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (!timer) return;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, 100 * NSEC_PER_MSEC);
    __weak ScriptPlayer *weakSelf = self;
    const uint64_t generation = session.generation;
    dispatch_source_set_event_handler(timer, ^{
        @autoreleasepool { [weakSelf handleLicenseHeartbeatForGeneration:generation]; }
    });
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession == session && ![session.cancellationToken isCancelled] &&
        _playback.phase() != TLinkPlaybackPhase::Finishing) {
        _licenseHeartbeat = timer; _licenseHeartbeatGeneration = generation;
    } else dispatch_source_cancel(timer);
    dispatch_resume(timer); // Sources are always resumed before either local/installed ownership can disappear.
    os_unfair_lock_unlock(&_playerLock);
}

- (void)finishSessionIfCurrent:(TLinkPlaybackSession *)session state:(NSString *)state error:(NSString *)error {
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session || !_playback.beginFinish(session.generation)) {
        os_unfair_lock_unlock(&_playerLock); return;
    }
    if (session.licenseRevoked) { state = @"license_revoked"; error = getLastScriptError(); }
    else if ([session.cancellationToken isCancelled]) { state = @"cancelled"; error = @""; }
    dispatch_source_t repeat = _repeatTimer; _repeatTimer = nil;
    os_unfair_lock_unlock(&_playerLock);
    if (repeat) dispatch_source_cancel(repeat);
    [self stopLicenseHeartbeatForGeneration:session.generation];
    @try {
        // Cleanup UPs cannot be denied as new script work: these fingers were observed only
        // after successful injection, and cleanup is complete before a new session is admitted.
        if (!session->touches.release([](const uint8_t *bytes, size_t length) {
            return performTouchFromRawData(bytes, length);
        })) { state = @"failed"; error = @"Unable to release RAW touch state during cleanup."; }
        if (error.length) setLastScriptError(error);
        [self finishRunHistoryForSession:session state:state error:error];
        if ([state isEqualToString:@"failed"] && error.length) [self showError:error forSession:session];
    } @catch (NSException *exception) {
        setLastScriptError(exception.reason ?: @"Playback cleanup failed.");
    } @finally {
        [self hideIndicatorForSession:session];
        os_unfair_lock_lock(&_playerLock);
        _currentRuntime = nil;
        _currentSession = nil;
        scriptBundlePath = nil; repeatTime = 0; interval = 0; speed = 1;
        _lastCompletedGeneration = session.generation;
        _playback.finish(session.generation); // Last model mutation; never publish idle before cleanup.
        os_unfair_lock_unlock(&_playerLock);
    }
}

- (int)playPath:(NSString *)path repeatTime:(int)repeats interval:(double)delay speed:(double)playSpeed
     switchApp:(BOOL)switchApp error:(NSError **)error {
    if (error) *error = nil;
    uint64_t delayNs = 0;
    if (path.length == 0 || !TLinkPlaybackDelay(delay, &delayNs)) {
        if (error) *error = tlinkPlaybackError(@"A script path and finite, nonnegative repeat interval are required.");
        return -1;
    }
    TLinkPlaybackSession *session = [[TLinkPlaybackSession alloc] init];
    session.bundlePath = path; session.repeatsRemaining = repeats; session.repeatDelayNs = delayNs;
    session.speed = std::isfinite(playSpeed) && playSpeed > 0 ? playSpeed : 1;
    session.switchApp = switchApp; session.preparing = YES;
    session.wake = dispatch_semaphore_create(0);
    session.cancellationToken = [[TLinkCancellationToken alloc] init];
    session.taskContext = [[TLinkTaskExecutionContext alloc] init];
    session.taskContext.cancellationToken = session.cancellationToken;
    os_unfair_lock_lock(&_playerLock);
    session.generation = _playback.reserve();
    if (!session.generation) {
        os_unfair_lock_unlock(&_playerLock);
        if (error) *error = tlinkPlaybackError(@"Unable to run the script. Another script is currently running or stopping.");
        return -1;
    }
    _currentSession = session;
    os_unfair_lock_unlock(&_playerLock);
    @try {
        return [self prepareSession:session error:error];
    } @catch (NSException *exception) {
        NSString *message = exception.reason ?: @"Unable to prepare script.";
        [self finishSessionIfCurrent:session state:@"failed" error:message];
        if (error) *error = tlinkPlaybackError(message);
        return -1;
    }
}
- (int)prepareSession:(TLinkPlaybackSession *)session error:(NSError **)error {
    NSString *failure = nil;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:session.bundlePath isDirectory:&isDir] || !isDir)
        failure = @"Unable to run the script. Path not found or it is not a directory.";
    NSString *infoPath = [session.bundlePath stringByAppendingPathComponent:@"info.plist"];
    if (!failure && ![[NSFileManager defaultManager] fileExistsAtPath:infoPath])
        failure = @"Unable to run the script. Info.plist not found.";
    NSDictionary *scriptInfo = failure ? nil : [NSDictionary dictionaryWithContentsOfFile:infoPath];
    NSDictionary *manifest = failure ? nil : tlinkautoReadManifest(session.bundlePath);
    NSString *entryName = tlinkautoStringValue(manifest[@"entry"]) ?: tlinkautoStringValue(scriptInfo[@"Entry"]);
    if (!failure && entryName.length == 0) failure = @"Script entry is missing.";
    if (!failure) {
        session.entryPath = [session.bundlePath stringByAppendingPathComponent:entryName];
        session.foregroundApp = tlinkautoStringValue(scriptInfo[@"FrontApp"]);
        session.manifest = manifest ?: @{};
        [self beginRunHistoryForSession:session entryPath:session.entryPath];
        session.raw = [entryName.pathExtension isEqualToString:@"raw"];
        NSString *runtime = [tlinkautoStringValue(manifest[@"runtime"]) lowercaseString];
        if (!session.raw) {
            if (![runtime isEqualToString:@"javascriptcore"] && ![entryName.pathExtension isEqualToString:@"js"])
                failure = @"Unsupported script entry. Python support has been removed; use RAW or JavaScript.";
            else if (!tlinkautoJavaScriptRuntimeEnabled()) failure = @"JavaScriptCore runtime is disabled.";
            else if ([manifest[@"apiVersion"] respondsToSelector:@selector(intValue)] && [manifest[@"apiVersion"] intValue] != 1)
                failure = @"Unsupported JavaScript API version.";
            if (session.repeatsRemaining < 0) session.repeatsRemaining = 0; // Preserve existing JS behavior.
        } else {
            // RAW has no cumulative native deadline/output sink. Reuse its cancellation-only
            // budget so dense touch playback does not allocate a budget for every record.
            [session.taskContext setNativeBudget:TLinkTaskBudget(session.taskContext)];
            __weak TLinkPlaybackSession *weakSession = session;
            session.taskContext.didInjectTouchPayload = ^(const uint8_t *bytes, size_t length) {
                TLinkPlaybackSession *owner = weakSession;
                if (owner) owner->touches.observe(bytes, length);
            };
        }
    }
    if (failure) {
        [self finishSessionIfCurrent:session state:@"failed" error:failure];
        if (error) *error = tlinkPlaybackError(failure);
        return -1;
    }
    [self startLicenseHeartbeatForSession:session];
    [self updateIndicatorForSession:session waiting:NO];
    os_unfair_lock_lock(&_playerLock);
    session.preparing = NO;
    BOOL ready = ![session.cancellationToken isCancelled] && _playback.ready(session.generation);
    os_unfair_lock_unlock(&_playerLock);
    if (!ready) { [self finishSessionIfCurrent:session state:@"cancelled" error:@""]; return 0; }
    dispatch_async(_playbackQueue, ^{
        @autoreleasepool { [self executeIteration:session]; }
    });
    return 0;
}
- (BOOL)beginIteration:(TLinkPlaybackSession *)session {
    os_unfair_lock_lock(&_playerLock);
    BOOL current = _currentSession == session;
    BOOL run = current && ![session.cancellationToken isCancelled] && _playback.enter(session.generation);
    dispatch_source_t timer = current ? _repeatTimer : nil;
    if (current) _repeatTimer = nil;
    os_unfair_lock_unlock(&_playerLock);
    if (timer) dispatch_source_cancel(timer);
    if (!run) [self finishSessionIfCurrent:session state:@"cancelled" error:@""];
    return run;
}
- (void)executeIteration:(TLinkPlaybackSession *)session {
    if (![self beginIteration:session]) return;
    [self updateIndicatorForSession:session waiting:NO];
    BOOL ok = YES;
    NSString *failure = nil;
    FILE *file = NULL;
    @try {
        if (session.switchApp && ![session.cancellationToken isCancelled]) bringAppForeground(session.foregroundApp);
        if (![session.cancellationToken isCancelled] && session.raw) {
            file = fopen(session.entryPath.UTF8String, "rb");
            TLinkRawResult result = TLinkRunRaw(file, session.speed,
                [&] { return [session.cancellationToken isCancelled] != NO; },
                [&](uint64_t ns) {
                    @autoreleasepool {
                        NSString *denial = nil;
                        if (!TLinkRootfullLicenseTaskAllowed(TASK_USLEEP, &denial)) {
                            [self requestStopSession:session revoked:YES message:denial]; return false;
                        }
                        if ([session.cancellationToken isCancelled]) return false;
                        dispatch_semaphore_wait(session.wake, dispatch_time(DISPATCH_TIME_NOW, (int64_t)ns));
                        return [session.cancellationToken isCancelled] == NO;
                    }
                },
                [&](uint8_t *bytes, size_t length) {
                    @autoreleasepool { processTaskWithContext(bytes, length, NULL, session.taskContext); }
                });
            ok = result == TLinkRawResult::Finished || result == TLinkRawResult::Cancelled;
            if (!ok) failure = result == TLinkRawResult::ReadError ? @"Cannot read RAW script." : @"Invalid or overlong RAW record.";
        } else if (![session.cancellationToken isCancelled]) {
            TLinkautoJSRuntime *runtime = [[TLinkautoJSRuntime alloc] init];
            os_unfair_lock_lock(&_playerLock);
            BOOL run = _currentSession == session && ![session.cancellationToken isCancelled];
            if (run) _currentRuntime = runtime;
            os_unfair_lock_unlock(&_playerLock);
            if (run) {
                NSError *runError = nil;
                ok = [runtime runScriptAtPath:session.entryPath bundlePath:session.bundlePath manifest:session.manifest
                                     context:session.taskContext error:&runError];
                session.consoleLogPath = [runtime currentConsoleLogPath];
                if (!ok) failure = runError.localizedDescription ?: @"JavaScript execution failed.";
            }
        }
    } @catch (NSException *exception) { ok = NO; failure = exception.reason ?: @"Script execution failed."; }
    @finally {
        if (file) fclose(file);
        os_unfair_lock_lock(&_playerLock);
        if (_currentSession == session) _currentRuntime = nil;
        os_unfair_lock_unlock(&_playerLock);
    }
    [self completeIteration:session success:ok error:failure];
}
- (void)completeIteration:(TLinkPlaybackSession *)session success:(BOOL)ok error:(NSString *)error {
    os_unfair_lock_lock(&_playerLock);
    BOOL current = _currentSession == session;
    BOOL repeat = current && ![session.cancellationToken isCancelled] && (!session.raw || ok) &&
                  session.repeatsRemaining != 0 && _playback.wait(session.generation);
    dispatch_source_t timer = nil;
    if (repeat) {
        if (session.repeatsRemaining > 0) session.repeatsRemaining--;
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _playbackQueue);
        if (timer) {
            _repeatTimer = timer;
            const uint64_t ns = session.repeatDelayNs;
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)ns), DISPATCH_TIME_FOREVER,
                                      ns / 10 < 100 * NSEC_PER_MSEC ? ns / 10 : 100 * NSEC_PER_MSEC);
            __weak ScriptPlayer *weakSelf = self;
            dispatch_source_set_event_handler(timer, ^{
                @autoreleasepool { [weakSelf executeIteration:session]; }
            });
            dispatch_resume(timer);
        }
    }
    os_unfair_lock_unlock(&_playerLock);
    if (timer) { [self updateIndicatorForSession:session waiting:YES]; return; }
    if (repeat) { ok = NO; error = @"Unable to schedule script repeat."; }
    [self finishSessionIfCurrent:session state:ok ? @"finished" : @"failed" error:error];
}
- (void)forceStop:(NSError **)error {
    if (error) *error = nil;
    os_unfair_lock_lock(&_playerLock);
    TLinkPlaybackSession *session = _currentSession;
    os_unfair_lock_unlock(&_playerLock);
    if (!session) {
        if (error) *error = tlinkPlaybackError(@"Cannot stop script. No script is playing.");
        return;
    }
    [self requestStopSession:session revoked:NO message:nil];
}
@end
// END playback session implementation.
