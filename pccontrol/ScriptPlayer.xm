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

static BOOL isPlaying = false;

typedef NS_ENUM(NSInteger, TLinkScriptState) {
    TLinkScriptStateIdle = 0,
    TLinkScriptStateScheduled,
    TLinkScriptStateRunning,
    TLinkScriptStateStopping
};

@implementation ScriptPlayer
{
    int repeatTime;
    float interval;
    float speed;
    NSString* scriptBundlePath;
    UIWindow *_playIndicator;
    int currentScriptType; // -1 none, 0 upcoming, 1 raw, 3 js
    NSTimer *replayTimer;
    UIView *circleView;
    Boolean scriptPlayForceStop;
    Boolean switchAppBeforePlaying;
    NSDictionary *currentManifest;

    os_unfair_lock _playerLock;
    TLinkScriptState _state;
    TLinkScriptSession *_currentSession;
    TLinkautoJSRuntime *_currentRuntime;
    dispatch_queue_t _jsSerialQueue;
    dispatch_source_t _licenseHeartbeat;
    uint64_t _licenseHeartbeatGeneration;
    uint64_t _licenseHeartbeatCheckCount;
    uint64_t _licenseRevocationCount;
    BOOL _licenseRevokedCurrentRun;
    NSString *_historyRunId;
    NSString *_historyConsoleLogPath;
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

- (BOOL)isPlaying { return isPlaying; }

- (NSString*)getCurrentBundlePath { return scriptBundlePath ?: @""; }

- (NSDictionary *)licenseRuntimeDiagnostics {
    os_unfair_lock_lock(&_playerLock);
    NSDictionary *diagnostics = @{
        @"heartbeat_active": @(_licenseHeartbeat != nil),
        @"heartbeat_interval_ms": @1000,
        @"generation": @(_licenseHeartbeatGeneration),
        @"check_count": @(_licenseHeartbeatCheckCount),
        @"revocation_count": @(_licenseRevocationCount),
        @"revoked_current_run": @(_licenseRevokedCurrentRun),
    };
    os_unfair_lock_unlock(&_playerLock);
    return diagnostics;
}

- (void)beginRunHistoryIfNeeded:(NSString *)entryPath {
    @synchronized (self) {
        if (_historyRunId.length > 0) return;
        NSDictionary *record = TLinkRunHistoryBegin(@"rootfull",
                                                     scriptBundlePath ?: @"",
                                                     entryPath ?: @"",
                                                     @{
                                                         @"repeat_times": @(repeatTime),
                                                         @"interval": @(interval),
                                                         @"speed": @(speed),
                                                     });
        _historyRunId = [record[@"run_id"] copy];
        _historyConsoleLogPath = @"";
    }
}

- (void)finishRunHistoryWithState:(NSString *)state error:(NSString *)error {
    NSString *runId = nil;
    NSString *consolePath = nil;
    @synchronized (self) {
        runId = _historyRunId;
        consolePath = _historyConsoleLogPath;
        _historyRunId = nil;
        _historyConsoleLogPath = nil;
    }
    if (runId.length == 0) return;

    NSString *screenshotPath = @"";
    NSString *screenshotError = @"";
    BOOL failed = [state isEqualToString:@"failed"] || [state isEqualToString:@"license_revoked"];
    if (failed) {
        screenshotPath = [TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.png", runId]];
        NSError *captureError = nil;
        NSString *saved = [Screen screenShotToPath:screenshotPath region:CGRectZero error:&captureError];
        if (saved.length == 0) {
            screenshotError = captureError.localizedDescription ?: @"capture_failed";
            screenshotPath = @"";
        }
    }
    TLinkRunHistoryFinish(runId,
                          state ?: @"finished",
                          error ?: @"",
                          @[],
                          consolePath ?: @"",
                          screenshotPath,
                          screenshotError,
                          @{});
}

- (void)stopLicenseHeartbeatForGeneration:(uint64_t)generation {
    dispatch_source_t timer = nil;
    os_unfair_lock_lock(&_playerLock);
    if (generation == 0 || _licenseHeartbeatGeneration == generation) {
        timer = _licenseHeartbeat;
        _licenseHeartbeat = nil;
        _licenseHeartbeatGeneration = 0;
    }
    os_unfair_lock_unlock(&_playerLock);
    if (timer) dispatch_source_cancel(timer);
}

- (void)handleLicenseHeartbeatForGeneration:(uint64_t)generation {
    os_unfair_lock_lock(&_playerLock);
    BOOL current = generation != 0 &&
                   _licenseHeartbeatGeneration == generation &&
                   _licenseHeartbeat != nil &&
                   isPlaying;
    if (current) _licenseHeartbeatCheckCount++;
    os_unfair_lock_unlock(&_playerLock);
    if (!current) return;

    NSString *denial = nil;
    if (TLinkRootfullLicenseComponentAllowed(@"script",
                                             @"script_runtime",
                                             &denial)) {
        return;
    }

    TLinkautoJSRuntime *runtime = nil;
    os_unfair_lock_lock(&_playerLock);
    if (_licenseHeartbeatGeneration != generation || !isPlaying) {
        os_unfair_lock_unlock(&_playerLock);
        return;
    }
    _licenseRevocationCount++;
    _licenseRevokedCurrentRun = YES;
    repeatTime = 0;
    scriptPlayForceStop = true;
    if (_currentSession) [_currentSession.cancellationToken cancel];
    runtime = _currentRuntime;
    if (currentScriptType == 3) _state = TLinkScriptStateStopping;
    os_unfair_lock_unlock(&_playerLock);

    NSString *message = [NSString stringWithFormat:
        @"license_revoked_during_execution %@",
        denial ?: @"license_required"];
    setLastScriptError(message);
    JS_DIAG("LICENSE_REVOKED", "%s", [message UTF8String]);
    NSLog(@"com.tlinkauto.script: %@", message);
    [self stopLicenseHeartbeatForGeneration:generation];
    if (runtime) [runtime requestStop];
}

- (void)startLicenseHeartbeatForGeneration:(uint64_t)generation {
    if (generation == 0) return;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0,
                                                     0,
                                                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (!timer) return;
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                              NSEC_PER_SEC,
                              100 * NSEC_PER_MSEC);
    __weak ScriptPlayer *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        ScriptPlayer *strongSelf = weakSelf;
        if (strongSelf) [strongSelf handleLicenseHeartbeatForGeneration:generation];
    });

    dispatch_source_t previous = nil;
    os_unfair_lock_lock(&_playerLock);
    previous = _licenseHeartbeat;
    _licenseHeartbeat = timer;
    _licenseHeartbeatGeneration = generation;
    _licenseRevokedCurrentRun = NO;
    os_unfair_lock_unlock(&_playerLock);
    if (previous) dispatch_source_cancel(previous);
    dispatch_resume(timer);
}

- (void)setPath:(NSString*)path {
    if (isPlaying) return;
    scriptBundlePath = path;
}

- (void)setRepeatTime:(int)rt {
    if (isPlaying) return;
    repeatTime = rt;
}

- (void)setInterval:(float)intv {
    if (isPlaying) return;
    interval = intv;
}

- (void)setSpeed:(float)sp {
    if (isPlaying) return;
    speed = sp;
}

- (void)setSwitchApp:(BOOL)value {
    if (isPlaying) return;
    switchAppBeforePlaying = value;
}

- (id)init {
    self = [super init];
    if (self) {
        _playerLock = OS_UNFAIR_LOCK_INIT;
        _jsSerialQueue = dispatch_queue_create("com.tlinkauto.js.serial", DISPATCH_QUEUE_SERIAL);
        _state = TLinkScriptStateIdle;
        [self clear];
    }
    return self;
}

- (id)initWithPath:(NSString*)path {
    self = [self init];
    if (self) {
        scriptBundlePath = path;
        currentScriptType = -1;
    }
    return self;
}

-(int)runScript:(NSError**)error {
    if (!scriptBundlePath) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. ScriptBundlePath not set.\r\n"}];
        return -1;
    }

    BOOL isDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptBundlePath isDirectory:&isDir] || !isDir) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Path not found or it is not a directory.\r\n"}];
        [self finishRunHistoryWithState:@"failed" error:@"Unable to run the script. Path not found or it is not a directory."];
        return -1;
    }

    NSString *infoFilePath = [NSString stringWithFormat:@"%@/info.plist", scriptBundlePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:infoFilePath isDirectory:&isDir]) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Info.plist not found.\r\n"}];
        [self finishRunHistoryWithState:@"failed" error:@"Unable to run the script. Info.plist not found."];
        return -1;
    }
    NSDictionary *scriptInfo = [NSDictionary dictionaryWithContentsOfFile:infoFilePath];
    NSDictionary *manifest = tlinkautoReadManifest(scriptBundlePath);
    currentManifest = manifest ?: @{};
    
    NSString *entryFileName = tlinkautoStringValue(manifest[@"entry"]) ?: scriptInfo[@"Entry"];
    if (!entryFileName || [entryFileName length] == 0) {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Script entry is missing.\r\n"}];
        [self finishRunHistoryWithState:@"failed" error:@"Script entry is missing."];
        return -1;
    }
    NSString *fileExtension = [entryFileName pathExtension];
    NSString *runtime = [tlinkautoStringValue(manifest[@"runtime"]) lowercaseString];
    NSNumber *apiVersion = [manifest[@"apiVersion"] respondsToSelector:@selector(intValue)] ? manifest[@"apiVersion"] : nil;
    NSString *foregroundApp = scriptInfo[@"FrontApp"];

    dispatch_async(dispatch_get_main_queue(), ^{
        _playIndicator = [[UIWindow alloc] initWithFrame:CGRectMake(0,0,10*2,10*2)];
        _playIndicator.windowLevel = UIWindowLevelStatusBar;
        _playIndicator.hidden = NO;
        [_playIndicator setBackgroundColor:[UIColor clearColor]];
        [_playIndicator setUserInteractionEnabled:NO];

        circleView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10*2,10*2)];
        circleView.layer.cornerRadius = 10;
        circleView.backgroundColor = [UIColor greenColor];
        [_playIndicator addSubview:circleView];
    });

    NSString *entryFilePath = [scriptBundlePath stringByAppendingPathComponent:entryFileName];
    [self beginRunHistoryIfNeeded:entryFilePath];

    if ([fileExtension isEqualToString:@"raw"]) {
        currentScriptType = 1;
        uint64_t generation = mach_absolute_time();
        isPlaying = true;
        [self startLicenseHeartbeatForGeneration:generation];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            NSError *err = nil;
            [self playFromRawFile:entryFilePath foregroundApp:foregroundApp err:&err];
            [self stopLicenseHeartbeatForGeneration:generation];
        }); 
        return 0;
    } else if ([runtime isEqualToString:@"javascriptcore"] || [fileExtension isEqualToString:@"js"]) {
        if (!tlinkautoJavaScriptRuntimeEnabled()) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;JavaScriptCore runtime is disabled.\r\n"}];
            [self finishRunHistoryWithState:@"failed" error:@"JavaScriptCore runtime is disabled."];
            [self clear];
            return -1;
        }
        if (apiVersion && [apiVersion intValue] != 1) {
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported JavaScript API version: %@\r\n", apiVersion]}];
            [self finishRunHistoryWithState:@"failed" error:[NSString stringWithFormat:@"Unsupported JavaScript API version: %@", apiVersion]];
            [self clear];
            return -1;
        }
        currentScriptType = 3;
        
        os_unfair_lock_lock(&_playerLock);
        
        if (_state != TLinkScriptStateIdle) {
            os_unfair_lock_unlock(&_playerLock);
            if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Script is already running.\r\n"}];
            [self finishRunHistoryWithState:@"failed" error:@"Script is already running."];
            return -1;
        }
        _state = TLinkScriptStateScheduled;
        
        TLinkScriptSession *session = [[TLinkScriptSession alloc] init];
        session.generation = (uint64_t)[[NSDate date] timeIntervalSince1970] * 1000000;
        session.cancellationToken = [[TLinkCancellationToken alloc] init];
        session.taskContext = [[TLinkTaskExecutionContext alloc] init];
        session.taskContext.cancellationToken = session.cancellationToken;
        
        _currentSession = session;
        isPlaying = true;
        os_unfair_lock_unlock(&_playerLock);
        [self startLicenseHeartbeatForGeneration:session.generation];

        dispatch_async(_jsSerialQueue, ^{
            [self executeJSIteration:session filePath:entryFilePath foregroundApp:foregroundApp];
        });
        return 0;
    } else if ([runtime isEqualToString:@"python"] || [fileExtension isEqualToString:@"py"]) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Python script support has been removed. Please migrate this script to JavaScript.\r\n"}];
        setLastScriptError(@"Python script support has been removed. Please migrate this script to JavaScript.");
        [self finishRunHistoryWithState:@"failed" error:getLastScriptError()];
        [self clear];
        return -1;
    }
    
    if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Unsupported script entry extension: %@\r\n", fileExtension ?: @""]}];
    [self finishRunHistoryWithState:@"failed" error:[NSString stringWithFormat:@"Unsupported script entry extension: %@", fileExtension ?: @""]];
    [self clear];
    return -1;
}

- (int)play:(NSError**)error {
    os_unfair_lock_lock(&_playerLock);
    
    if (_state != TLinkScriptStateIdle || isPlaying) {
        os_unfair_lock_unlock(&_playerLock);
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to run the script. Another script is currently running.\r\n"}];
        return -1;
    }
    os_unfair_lock_unlock(&_playerLock);
    return [self runScript:error];
}

-(void)playFromRawFile:(NSString*) filePath foregroundApp:(NSString*)foregroundApp err:(NSError**)err {
    isPlaying = true;
    if (switchAppBeforePlaying) bringAppForeground(foregroundApp);

    FILE *file = fopen([filePath UTF8String], "r");
    if (!file) {
        showAlertBox(@"Error", [NSString stringWithFormat:@"Cannot play this script because TLinkauto cannot open the file. File path: %@", filePath], 999);
        setLastScriptError([NSString stringWithFormat:@"Cannot open raw script: %@", filePath]);
        isPlaying = false;
        [self stopLicenseHeartbeatForGeneration:0];
        [self finishRunHistoryWithState:@"failed" error:getLastScriptError()];
        return;
    }
    
    char buffer[256];
    
    while (fgets(buffer, sizeof(char)*256, file) != NULL) {
        if (scriptPlayForceStop) {
            scriptPlayForceStop = false;
            break;
        }
        if (speed > 0 && speed != 1) {
            int type, sleepTime;
            sscanf(buffer, "%2d", &type);
            if (type == TASK_USLEEP) {
                sscanf(buffer, "%2d%d", &type, &sleepTime);
                sleepTime = sleepTime / speed;
                processTask((UInt8*)[[NSString stringWithFormat:@"18%d", sleepTime] UTF8String], NULL);
            } else {
                processTask((UInt8*)buffer, NULL);
            }
        } else {
            processTask((UInt8*)buffer, NULL);
        }
    }
    fclose(file);
    [self playHasStopped];
}

- (void)executeJSIteration:(TLinkScriptSession *)session filePath:(NSString *)filePath foregroundApp:(NSString *)foregroundApp {
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session || [session.cancellationToken isCancelled]) {
        os_unfair_lock_unlock(&_playerLock);
        return;
    }
    TLinkautoJSRuntime *runtime = [[TLinkautoJSRuntime alloc] init];
    _currentRuntime = runtime;
    _state = TLinkScriptStateRunning;
    os_unfair_lock_unlock(&_playerLock);

    if (self->switchAppBeforePlaying) {
        bringAppForeground(foregroundApp);
    }

    NSError *runError = nil;
    BOOL ok = [runtime runScriptAtPath:filePath bundlePath:scriptBundlePath manifest:currentManifest context:session.taskContext error:&runError];
    @synchronized (self) {
        _historyConsoleLogPath = [[runtime currentConsoleLogPath] copy] ?: @"";
    }
    
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession != session) {
        os_unfair_lock_unlock(&_playerLock);
        return;
    }
    _currentRuntime = nil; // Clear for replay
    if ([session.cancellationToken isCancelled]) {
        os_unfair_lock_unlock(&_playerLock);
        [self finishSessionIfCurrent:session outcome:NO];
        return;
    }
    
    if (repeatTime > 0) {
        repeatTime--;
        os_unfair_lock_unlock(&_playerLock);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->circleView.backgroundColor = [UIColor orangeColor];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), _jsSerialQueue, ^{
            [self executeJSIteration:session filePath:filePath foregroundApp:foregroundApp];
        });
    } else {
        os_unfair_lock_unlock(&_playerLock);
        if (!ok && runError) {
            setLastScriptError([runError localizedDescription]);
            if (![session.cancellationToken isCancelled]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    showAlertBox(@"JavaScript Error", [runError localizedDescription], 999);
                });
            }
        }
        [self finishSessionIfCurrent:session outcome:ok];
    }
}

- (void)finishSessionIfCurrent:(TLinkScriptSession *)session outcome:(BOOL)ok {
    [self stopLicenseHeartbeatForGeneration:session.generation];
    os_unfair_lock_lock(&_playerLock);
    if (_currentSession == session) {
        _currentSession = nil;
        _currentRuntime = nil;
        _state = TLinkScriptStateIdle;
        isPlaying = false;
    }
    os_unfair_lock_unlock(&_playerLock);

    NSString *state = ok ? @"finished" : @"failed";
    NSString *error = ok ? @"" : getLastScriptError();
    if ([session.cancellationToken isCancelled]) {
        if (_licenseRevokedCurrentRun) {
            state = @"license_revoked";
            error = getLastScriptError();
        } else {
            state = @"cancelled";
            error = @"";
        }
    }
    [self finishRunHistoryWithState:state error:error];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self clearLegacyState];
    });
}

- (void)clearLegacyState {
    repeatTime = 0;
    interval = 0.0f;
    speed = 1.0f;
    scriptBundlePath = nil;
    currentScriptType = -1;
    if (_playIndicator) {
        _playIndicator.hidden = YES;
        _playIndicator = nil;
    }
    if (replayTimer) {
        [replayTimer invalidate];
        replayTimer = nil;
    }
}

- (void)replay:(NSTimer*)nstimer {
    NSError *err = nil;
    [self runScript:&err];
    CFRunLoopStop(CFRunLoopGetCurrent());
}

-(void) playHasStopped {
    if (repeatTime != 0) {    
        dispatch_async(dispatch_get_main_queue(), ^{
            circleView.backgroundColor = [UIColor orangeColor];
        });
        replayTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(replay:) userInfo:nil repeats:NO];
        repeatTime--;
        currentScriptType = 0;
        CFRunLoopRun();
    } else {
        if (_licenseRevokedCurrentRun) {
            [self finishRunHistoryWithState:@"license_revoked" error:getLastScriptError()];
        } else {
            [self finishRunHistoryWithState:@"finished" error:@""];
        }
        [self clear];
    }
}

- (void)clear {
    [self stopLicenseHeartbeatForGeneration:0];
    repeatTime = 0;
    interval = 0.0f;
    speed = 1.0f;
    scriptBundlePath = nil;
    isPlaying = false;
    currentScriptType = -1;

    dispatch_async(dispatch_get_main_queue(), ^{
        _playIndicator.hidden = YES;
        _playIndicator = nil;
    });

    if (replayTimer) [replayTimer invalidate];
    replayTimer = nil;
}

- (void)forceStop:(NSError**)error {
    os_unfair_lock_lock(&_playerLock);
    if (_state == TLinkScriptStateIdle && !isPlaying) {
        os_unfair_lock_unlock(&_playerLock);
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Cannot stop script. No script is playing.\r\n"}];
        return;
    }

    if (currentScriptType == 3) {
        if (_state == TLinkScriptStateScheduled) {
            [_currentSession.cancellationToken cancel];
            _currentSession = nil;
            _state = TLinkScriptStateIdle;
            isPlaying = false;
            os_unfair_lock_unlock(&_playerLock);
            [self finishRunHistoryWithState:@"cancelled" error:@""];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self clearLegacyState];
            });
        } else if (_state == TLinkScriptStateRunning) {
            [_currentSession.cancellationToken cancel];
            if (_currentRuntime) {
                __strong TLinkautoJSRuntime *runtime = _currentRuntime;
                _state = TLinkScriptStateStopping;
                os_unfair_lock_unlock(&_playerLock);
                [runtime requestStop];
            } else {
                TLinkScriptSession *session = _currentSession;
                os_unfair_lock_unlock(&_playerLock);
                dispatch_async(_jsSerialQueue, ^{
                    [self finishSessionIfCurrent:session outcome:NO];
                });
            }
        } else if (_state == TLinkScriptStateStopping) {
            [_currentSession.cancellationToken cancel];
            os_unfair_lock_unlock(&_playerLock);
        } else {
            os_unfair_lock_unlock(&_playerLock);
        }
    } else {
        os_unfair_lock_unlock(&_playerLock);
        if (currentScriptType == 0) {
            [self finishRunHistoryWithState:@"cancelled" error:@""];
            [self clear];
        } else if (currentScriptType == 1) {
            scriptPlayForceStop = true;
            [self finishRunHistoryWithState:@"cancelled" error:@""];
            [self clear];
        }
    }
}
@end
