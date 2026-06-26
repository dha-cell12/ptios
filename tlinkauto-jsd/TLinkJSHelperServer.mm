#import "TLinkJSHelperServer.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#import <JavaScriptCore/JavaScriptCore.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <math.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <signal.h>
#include <atomic>

static NSString * const kTLinkJSHelperSocketPath = @"/var/mobile/Library/TLinkauto/run/js-helper.sock";
static NSString * const kTLinkJSHelperPidPath = @"/var/mobile/Library/TLinkauto/run/js-helper.pid";
static NSString * const kTLinkJSHelperVersion = @"1.0.0";
static const unsigned long long kTLinkJSHelperMaxBundleFileBytes = 512 * 1024;
static const unsigned long long kTLinkJSHelperMaxConsoleLogBytes = 512 * 1024;
static const double kTLinkJSHelperWatchdogInterval = 0.1;

typedef bool (*TLinkJSHelperShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkJSHelperSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkJSHelperShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkJSHelperClearExecutionTimeLimitFn)(JSContextGroupRef group);

struct TLinkJSHelperCancelState {
    std::atomic<bool> stopped;
};

static bool TLinkJSHelperShouldTerminate(JSContextRef ctx, void *opaque) {
    (void)ctx;
    TLinkJSHelperCancelState *state = (TLinkJSHelperCancelState *)opaque;
    return state && state->stopped.load(std::memory_order_acquire);
}

@interface TLinkJSHelperServer () {
    TLinkJSHelperCancelState *_cancelState;
    TLinkJSHelperSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkJSHelperClearExecutionTimeLimitFn _clearExecutionTimeLimit;
}
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, strong) NSDate *startedAt;
@property(nonatomic, strong) dispatch_queue_t executionQueue;
@property(nonatomic, strong) NSCondition *sleepCondition;
@property(nonatomic, copy) NSString *activeSessionId;
@property(nonatomic, copy) NSString *activeRunId;
@property(nonatomic, copy) NSString *activeState;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic, copy) NSString *lastConsoleLogPath;
@property(nonatomic, copy) NSString *lastConsoleLatestLogPath;
@property(nonatomic, strong) NSCondition *rpcCondition;
@property(nonatomic, copy) NSDictionary *pendingNativeRequest;
@property(nonatomic, strong) NSMutableDictionary *nativeResponses;
@end

@implementation TLinkJSHelperServer

- (instancetype)init
{
    self = [super init];
    if (self) {
        _helperInstanceId = [[NSUUID UUID] UUIDString];
        _startedAt = [NSDate date];
        _executionQueue = dispatch_queue_create("com.tlinkauto.js-helper.execution", DISPATCH_QUEUE_SERIAL);
        _sleepCondition = [[NSCondition alloc] init];
        _rpcCondition = [[NSCondition alloc] init];
        _nativeResponses = [NSMutableDictionary dictionary];
        _activeState = kTLinkJSHelperStateIdle;
        _cancelState = new TLinkJSHelperCancelState();
        _cancelState->stopped.store(false, std::memory_order_relaxed);
        _setExecutionTimeLimit = (TLinkJSHelperSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkJSHelperClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
    }
    return self;
}

- (void)dealloc
{
    delete _cancelState;
}

static NSString *TLinkJSHelperSanitizeFileComponent(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return @"script";
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    NSString *joined = [[value componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    return [joined length] > 0 ? joined : @"script";
}

static int TLinkJSHelperHardwareKeyType(NSString *key) {
    NSString *k = [[key ?: @""] lowercaseString];
    if ([k isEqualToString:@"home"]) return 1;
    if ([k isEqualToString:@"volume-up"] || [k isEqualToString:@"volumeup"]) return 2;
    if ([k isEqualToString:@"volume-down"] || [k isEqualToString:@"volumedown"]) return 3;
    if ([k isEqualToString:@"lock"] || [k isEqualToString:@"power"]) return 4;
    return -1;
}

static int TLinkJSHelperHardwareKeyAction(NSString *action) {
    NSString *a = [[action ?: @""] lowercaseString];
    if ([a isEqualToString:@"up"]) return 0;
    if ([a isEqualToString:@"down"]) return 1;
    return -1;
}

static int TLinkJSHelperTouchIndicatorAction(NSString *action) {
    NSString *a = [[action ?: @""] lowercaseString];
    if ([a isEqualToString:@"show"]) return 1;
    if ([a isEqualToString:@"hide"]) return 0;
    if ([a isEqualToString:@"reload"]) return 2;
    return -1;
}

- (NSDictionary *)statusPayload
{
    NSTimeInterval uptimeMs = [[NSDate date] timeIntervalSinceDate:self.startedAt] * 1000.0;
    NSMutableDictionary *payload = [@{
        @"state": self.activeState ?: kTLinkJSHelperStateIdle,
        @"activeSessionId": self.activeSessionId ?: [NSNull null],
        @"runId": self.activeRunId ?: @"",
        @"uptimeMs": @((long long)uptimeMs),
        @"lastError": self.lastError ?: @"",
        @"consoleLogPath": self.lastConsoleLogPath ?: @"",
        @"consoleLatestLogPath": self.lastConsoleLatestLogPath ?: @"",
    } mutableCopy];
    [self.rpcCondition lock];
    if (self.pendingNativeRequest) {
        payload[@"nativeRPCRequest"] = self.pendingNativeRequest;
    }
    [self.rpcCondition unlock];
    return payload;
}

- (NSDictionary *)executeNativeRPCMethod:(NSString *)method arguments:(NSArray *)arguments sessionId:(NSString *)sessionId
{
    if (![method isKindOfClass:[NSString class]] || [method length] == 0) {
        return @{ @"ok": @NO, @"error": @"native RPC method is required" };
    }
    NSString *requestId = [[NSUUID UUID] UUIDString];
    NSDictionary *request = @{
        kTLinkJSHelperKeyRequestId: requestId,
        @"method": method,
        @"arguments": arguments ?: @[],
        @"sessionId": sessionId ?: @"",
    };
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    [self.rpcCondition lock];
    while (self.pendingNativeRequest && !_cancelState->stopped.load(std::memory_order_acquire)) {
        if (![self.rpcCondition waitUntilDate:deadline]) break;
    }
    if (self.pendingNativeRequest || _cancelState->stopped.load(std::memory_order_acquire)) {
        [self.rpcCondition unlock];
        return @{ @"ok": @NO, @"error": @"native RPC unavailable" };
    }
    self.pendingNativeRequest = request;
    [self.rpcCondition broadcast];
    while (!_cancelState->stopped.load(std::memory_order_acquire)) {
        NSDictionary *response = self.nativeResponses[requestId];
        if (response) {
            [self.nativeResponses removeObjectForKey:requestId];
            self.pendingNativeRequest = nil;
            [self.rpcCondition broadcast];
            [self.rpcCondition unlock];
            return response;
        }
        if (![self.rpcCondition waitUntilDate:deadline]) break;
    }
    self.pendingNativeRequest = nil;
    [self.rpcCondition broadcast];
    [self.rpcCondition unlock];
    return @{ @"ok": @NO, @"error": @"native RPC timed out" };
}

- (NSString *)consoleLogPathForBundlePath:(NSString *)bundlePath runId:(NSString *)runId latest:(BOOL)latest
{
    NSString *dir = [bundlePath stringByAppendingPathComponent:@"_logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    if (latest) return [dir stringByAppendingPathComponent:@"latest-helper.log"];
    return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-helper.log", TLinkJSHelperSanitizeFileComponent(runId)]];
}

- (void)appendLine:(NSString *)line toPath:(NSString *)path
{
    if (![line isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSString class]] || [path length] == 0) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @finally {
        [handle closeFile];
    }
}

- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath bundlePath:(NSString *)bundlePath
{
    NSString *root = [bundlePath stringByStandardizingPath];
    if (![root isKindOfClass:[NSString class]] || [root length] == 0) return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) return @{ @"ok": @NO, @"error": @"module path is required" };
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) return @{ @"ok": @NO, @"error": @"module path must be bundle-relative" };
    NSString *candidate = [[root stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) return @{ @"ok": @NO, @"error": @"module path escapes bundle" };
    NSString *extension = [[candidate pathExtension] lowercaseString];
    if (!([extension isEqualToString:@"js"] || [extension isEqualToString:@"json"])) return @{ @"ok": @NO, @"error": @"module extension must be .js or .json" };
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:nil];
    if (!attrs) return @{ @"ok": @NO, @"error": @"module file not found", @"path": candidate ?: @"" };
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxBundleFileBytes) return @{ @"ok": @NO, @"error": @"module file is too large", @"path": candidate ?: @"" };
    NSError *err = nil;
    NSString *source = [NSString stringWithContentsOfFile:candidate encoding:NSUTF8StringEncoding error:&err];
    if (!source) return @{ @"ok": @NO, @"error": err.localizedDescription ?: @"failed to read module", @"path": candidate ?: @"" };
    return @{ @"ok": @YES, @"path": candidate, @"id": [candidate substringFromIndex:[prefix length]] ?: relativePath, @"source": source };
}

- (BOOL)interruptibleSleepMs:(double)ms context:(JSContext *)context
{
    if (!isfinite(ms) || ms < 0) {
        context.exception = [JSValue valueWithNewErrorFromMessage:@"sleep(ms) requires a finite non-negative number" inContext:context];
        return NO;
    }
    if (ms > 24.0 * 60.0 * 60.0 * 1000.0) ms = 24.0 * 60.0 * 60.0 * 1000.0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(ms / 1000.0)];
    [self.sleepCondition lock];
    while (!_cancelState->stopped.load(std::memory_order_acquire)) {
        if (![self.sleepCondition waitUntilDate:deadline]) break;
    }
    [self.sleepCondition unlock];
    if (_cancelState->stopped.load(std::memory_order_acquire)) {
        context.exception = [JSValue valueWithNewErrorFromMessage:@"Script aborted" inContext:context];
        return NO;
    }
    return YES;
}

- (void)runSessionId:(NSString *)sessionId scriptPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest runId:(NSString *)runId
{
    @autoreleasepool {
        NSLog(@"tlinkauto-jsd: starting session=%@ script=%@ bundle=%@", sessionId, scriptPath, bundlePath);
        NSString *logPath = [self consoleLogPathForBundlePath:bundlePath runId:runId latest:NO];
        NSString *latestPath = [self consoleLogPathForBundlePath:bundlePath runId:runId latest:YES];
        self.lastConsoleLogPath = logPath;
        self.lastConsoleLatestLogPath = latestPath;
        NSString *header = [NSString stringWithFormat:@"[%@] helper run %@ started\n", [NSDate date], runId];
        [header writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [header writeToFile:latestPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSError *readError = nil;
        NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:&readError];
        if (!script) {
            self.lastError = readError.localizedDescription ?: @"failed to read script";
            self.activeState = kTLinkJSHelperStateFailed;
            NSLog(@"tlinkauto-jsd: read script failed session=%@ error=%@", sessionId, self.lastError);
            return;
        }

        self.activeState = kTLinkJSHelperStateRunning;
        NSLog(@"tlinkauto-jsd: evaluating session=%@", sessionId);
        JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
        JSContext *ctx = [[JSContext alloc] initWithVirtualMachine:vm];
        __weak TLinkJSHelperServer *weakSelf = self;
        ctx.exceptionHandler = ^(JSContext *context, JSValue *exception) {
            context.exception = exception;
            weakSelf.lastError = [exception toString] ?: @"JavaScript exception";
            NSLog(@"tlinkauto-jsd: exception session=%@ error=%@", sessionId, weakSelf.lastError);
        };
        ctx[@"manifest"] = manifest ?: @{};
        ctx[@"sleep"] = ^(double ms) {
            [weakSelf interruptibleSleepMs:ms context:[JSContext currentContext]];
        };
        ctx[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
            NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n", [NSDate date], runId ?: @"", level ?: @"log", message ?: @""];
            [weakSelf appendLine:line toPath:logPath];
            [weakSelf appendLine:line toPath:latestPath];
            NSLog(@"tlinkauto-jsd[%@][%@]: %@", runId ?: @"", level ?: @"log", message ?: @"");
        };
        ctx[@"_tlinkautoLoadBundleText"] = ^NSDictionary *(NSString *relativePath) {
            return [weakSelf bundleTextForRelativePath:relativePath bundlePath:bundlePath];
        };
        JSValue *device = [JSValue valueWithNewObjectInContext:ctx];
        device[@"runtimeInfo"] = ^NSDictionary *{
            return @{
                @"engine": @"JavaScriptCore",
                @"runtimeLocation": @"helper-process-prototype",
                @"apiVersion": @1,
                @"helperInstanceId": weakSelf.helperInstanceId ?: @"",
                @"sessionId": sessionId ?: @"",
                @"runId": runId ?: @"",
                @"consoleLogPath": logPath ?: @"",
                @"consoleLatestLogPath": latestPath ?: @"",
                @"nativeAPIs": @NO,
                @"nativeRPC": @YES,
            };
        };
        device[@"toast"] = ^NSDictionary *(NSString *message, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"toast" arguments:@[message ?: @"", options ?: @{}] sessionId:sessionId];
        };
        device[@"tap"] = ^NSDictionary *(double x, double y) {
            return [weakSelf executeNativeRPCMethod:@"tap" arguments:@[@(x), @(y)] sessionId:sessionId];
        };
        device[@"swipe"] = ^NSDictionary *(double x1, double y1, double x2, double y2, double duration) {
            return [weakSelf executeNativeRPCMethod:@"swipe" arguments:@[@(x1), @(y1), @(x2), @(y2), @(duration)] sessionId:sessionId];
        };
        device[@"longPress"] = ^NSDictionary *(double x, double y, double duration) {
            return [weakSelf executeNativeRPCMethod:@"longPress" arguments:@[@(x), @(y), @(duration)] sessionId:sessionId];
        };
        device[@"gesture"] = ^NSDictionary *(NSArray *points, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"gesture" arguments:@[points ?: @[], options ?: @{}] sessionId:sessionId];
        };
        device[@"pickColor"] = ^NSDictionary *(double x, double y) {
            return [weakSelf executeNativeRPCMethod:@"pickColor" arguments:@[@(x), @(y)] sessionId:sessionId];
        };
        device[@"getScreenSize"] = ^NSDictionary *{
            return [weakSelf executeNativeRPCMethod:@"getScreenSize" arguments:@[] sessionId:sessionId];
        };
        device[@"screenshotTo"] = ^NSDictionary *(NSString *path) {
            return [weakSelf executeNativeRPCMethod:@"screenshotTo" arguments:@[path ?: @""] sessionId:sessionId];
        };
        device[@"screenshotRegion"] = ^NSDictionary *(NSString *path, NSDictionary *options) {
            return [weakSelf executeNativeRPCMethod:@"screenshotRegion" arguments:@[path ?: @"", options ?: @{}] sessionId:sessionId];
        };
        device[@"frontMostAppId"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"frontMostAppId" arguments:@[] sessionId:sessionId]; };
        device[@"frontMostPid"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"frontMostPid" arguments:@[] sessionId:sessionId]; };
        device[@"orientation"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"orientation" arguments:@[] sessionId:sessionId]; };
        device[@"openApp"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"openApp" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"killApp"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"killApp" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appState"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appState" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appInfo"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appInfo" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appPid"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appPid" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"appPaths"] = ^NSDictionary *(NSString *bundleId) { return [weakSelf executeNativeRPCMethod:@"appPaths" arguments:@[bundleId ?: @""] sessionId:sessionId]; };
        device[@"listBundles"] = ^NSDictionary *(BOOL withInfo) { return [weakSelf executeNativeRPCMethod:@"listBundles" arguments:@[@(withInfo)] sessionId:sessionId]; };
        device[@"openUrl"] = ^NSDictionary *(NSString *url) { return [weakSelf executeNativeRPCMethod:@"openUrl" arguments:@[url ?: @""] sessionId:sessionId]; };
        device[@"wifi"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@55, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setWifi"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@55, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"bluetooth"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@56, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setBluetooth"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@56, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"airplaneMode"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@57, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setAirplaneMode"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@57, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"cellularData"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@58, @"enabled", [NSNull null]] sessionId:sessionId]; };
        device[@"setCellularData"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"connectivity" arguments:@[@58, @"enabled", @(enabled)] sessionId:sessionId]; };
        device[@"rootDir"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"rootDir" arguments:@[] sessionId:sessionId]; };
        device[@"currentDir"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"currentDir" arguments:@[] sessionId:sessionId]; };
        device[@"botPath"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"botPath" arguments:@[] sessionId:sessionId]; };
        device[@"info"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"info" arguments:@[] sessionId:sessionId]; };
        device[@"batteryInfo"] = ^NSDictionary *{ return [weakSelf executeNativeRPCMethod:@"batteryInfo" arguments:@[] sessionId:sessionId]; };
        device[@"hardwareKey"] = ^NSDictionary *(NSString *key, NSString *action) {
            return [weakSelf executeNativeRPCMethod:@"hardwareKey" arguments:@[@(TLinkJSHelperHardwareKeyAction(action)), @(TLinkJSHelperHardwareKeyType(key))] sessionId:sessionId];
        };
        device[@"pressHardwareKey"] = ^NSDictionary *(NSString *key) {
            return [weakSelf executeNativeRPCMethod:@"pressHardwareKey" arguments:@[@(TLinkJSHelperHardwareKeyType(key))] sessionId:sessionId];
        };
        device[@"keepAwake"] = ^NSDictionary *(BOOL enabled) { return [weakSelf executeNativeRPCMethod:@"keepAwake" arguments:@[@(enabled)] sessionId:sessionId]; };
        device[@"touchIndicator"] = ^NSDictionary *(NSString *action) { return [weakSelf executeNativeRPCMethod:@"touchIndicator" arguments:@[@(TLinkJSHelperTouchIndicatorAction(action))] sessionId:sessionId]; };
        device[@"runShell"] = ^NSDictionary *(NSString *command, double timeoutSeconds) { return [weakSelf executeNativeRPCMethod:@"runShell" arguments:@[command ?: @"", @(timeoutSeconds)] sessionId:sessionId]; };
        ctx[@"device"] = device;
        NSString *consolePrelude = @"(function(){function fmt(args){return Array.prototype.map.call(args,function(v){try{if(typeof v==='string')return v;return JSON.stringify(v);}catch(e){return String(v);}}).join(' ');}this.console={log:function(){_tlinkautoLog('log',fmt(arguments));},info:function(){_tlinkautoLog('info',fmt(arguments));},warn:function(){_tlinkautoLog('warn',fmt(arguments));},error:function(){_tlinkautoLog('error',fmt(arguments));}};})();";
        NSString *modulePrelude = @"(function(){var cache=Object.create(null);var stack=[];function dirname(p){var i=p.lastIndexOf('/');return i>=0?p.slice(0,i):'';}function normalize(base,req){if(typeof req!=='string'||!req)throw new Error('module path is required');var input=req;if(req.indexOf('./')===0||req.indexOf('../')===0)input=(base?dirname(base)+'/':'')+req;var out=[];input.split('/').forEach(function(part){if(!part||part==='.')return;if(part==='..')out.pop();else out.push(part);});return out.join('/');}function candidates(id){if(/\\.(js|json)$/.test(id))return[id];return[id+'.js',id+'.json',id+'/index.js'];}function loadRecord(id){var last='';var list=candidates(id);for(var i=0;i<list.length;i++){var rec=_tlinkautoLoadBundleText(list[i]);if(rec&&rec.ok)return rec;last=rec&&rec.error?rec.error:'module not found';}throw new Error('Cannot load module '+id+': '+last);}this.require=function(request){var id=normalize(stack.length?stack[stack.length-1]:'',request);var rec=loadRecord(id);if(cache[rec.id])return cache[rec.id].exports;var module={id:rec.id,filename:rec.path,exports:{}};cache[rec.id]=module;if(/\\.json$/.test(rec.id)){module.exports=JSON.parse(rec.source);return module.exports;}stack.push(rec.id);try{var fn=new Function('exports','module','require','device','sleep',rec.source+'\\n//# sourceURL='+rec.path);fn(module.exports,module,this.require,device,sleep);}finally{stack.pop();}return module.exports;};this.include=function(request){var id=normalize(stack.length?stack[stack.length-1]:'',request);var rec=loadRecord(id);return(0,eval)(rec.source+'\\n//# sourceURL='+rec.path);};})();";
        JSContextGroupRef group = JSContextGetGroup([ctx JSGlobalContextRef]);
        if (_setExecutionTimeLimit) _setExecutionTimeLimit(group, kTLinkJSHelperWatchdogInterval, TLinkJSHelperShouldTerminate, _cancelState);
        @try {
            NSLog(@"tlinkauto-jsd: evaluate console prelude session=%@", sessionId);
            [ctx evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto-helper://console-prelude.js"]];
            if (!ctx.exception) {
                NSLog(@"tlinkauto-jsd: evaluate module prelude session=%@", sessionId);
                [ctx evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto-helper://module-prelude.js"]];
            }
            if (!ctx.exception) {
                NSLog(@"tlinkauto-jsd: evaluate main script session=%@", sessionId);
                [ctx evaluateScript:script withSourceURL:[NSURL fileURLWithPath:scriptPath]];
            }
        } @finally {
            if (_clearExecutionTimeLimit) _clearExecutionTimeLimit(group);
        }
        if (_cancelState->stopped.load(std::memory_order_acquire)) {
            self.activeState = kTLinkJSHelperStateCancelled;
        } else if (ctx.exception) {
            self.lastError = [ctx.exception toString] ?: self.lastError ?: @"JavaScript exception";
            self.activeState = kTLinkJSHelperStateFailed;
        } else {
            self.activeState = kTLinkJSHelperStateCompleted;
        }
        NSLog(@"tlinkauto-jsd: finished session=%@ state=%@ error=%@", sessionId, self.activeState, self.lastError ?: @"");
        if (![self.activeSessionId isEqualToString:sessionId]) return;
    }
}

- (NSDictionary *)runScriptDirectAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest
{
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *runId = [[NSUUID UUID] UUIDString];
    self.activeSessionId = sessionId;
    self.activeRunId = runId;
    self.lastError = @"";
    self.lastConsoleLogPath = @"";
    self.lastConsoleLatestLogPath = @"";
    self.activeState = kTLinkJSHelperStateStarting;
    _cancelState->stopped.store(false, std::memory_order_release);
    [self runSessionId:sessionId scriptPath:scriptPath bundlePath:bundlePath manifest:manifest ?: @{} runId:runId];
    return [self statusPayload];
}

- (NSDictionary *)startWithRequest:(NSDictionary *)request
{
    if (self.activeSessionId && ([self.activeState isEqualToString:kTLinkJSHelperStateStarting] || [self.activeState isEqualToString:kTLinkJSHelperStateRunning])) {
        return [self errorEnvelopeForRequest:request message:@"helper_busy"];
    }
    NSDictionary *payload = [request[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? request[kTLinkJSHelperKeyPayload] : @{};
    NSString *scriptPath = [payload[@"scriptPath"] isKindOfClass:[NSString class]] ? payload[@"scriptPath"] : @"";
    NSString *bundlePath = [payload[@"bundlePath"] isKindOfClass:[NSString class]] ? payload[@"bundlePath"] : @"";
    NSDictionary *manifest = [payload[@"manifest"] isKindOfClass:[NSDictionary class]] ? payload[@"manifest"] : @{};
    if (![scriptPath length] || ![bundlePath length]) return [self errorEnvelopeForRequest:request message:@"scriptPath and bundlePath are required"];
    NSString *sessionId = [[NSUUID UUID] UUIDString];
    NSString *runId = [[NSUUID UUID] UUIDString];
    self.activeSessionId = sessionId;
    self.activeRunId = runId;
    self.lastError = @"";
    self.lastConsoleLogPath = @"";
    self.lastConsoleLatestLogPath = @"";
    self.activeState = kTLinkJSHelperStateStarting;
    _cancelState->stopped.store(false, std::memory_order_release);
    dispatch_async(self.executionQueue, ^{
        [self runSessionId:sessionId scriptPath:scriptPath bundlePath:bundlePath manifest:manifest runId:runId];
    });
    return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStart helperInstanceId:self.helperInstanceId sessionId:sessionId requestId:request[kTLinkJSHelperKeyRequestId] payload:[self statusPayload]];
}

- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message
{
    NSMutableDictionary *env = [[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdError
                                                           helperInstanceId:self.helperInstanceId
                                                                  sessionId:request[kTLinkJSHelperKeySessionId]
                                                                  requestId:request[kTLinkJSHelperKeyRequestId]
                                                                    payload:@{}] mutableCopy];
    env[kTLinkJSHelperKeyError] = @{ @"message": message ?: @"unknown_error" };
    return env;
}

- (NSDictionary *)handleEnvelope:(NSDictionary *)request
{
    NSError *validationError = nil;
    if (![TLinkJSHelperProtocol validateEnvelope:request error:&validationError]) {
        return [self errorEnvelopeForRequest:request ?: @{} message:validationError.localizedDescription ?: @"invalid_envelope"];
    }

    NSString *command = request[kTLinkJSHelperKeyCommand];
    NSTimeInterval uptimeMs = [[NSDate date] timeIntervalSinceDate:self.startedAt] * 1000.0;
    if ([command isEqualToString:kTLinkJSHelperCmdHandshake]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdHandshake
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:@{
            @"helperVersion": kTLinkJSHelperVersion,
            @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
            @"state": kTLinkJSHelperStateIdle,
            @"uptimeMs": @((long long)uptimeMs),
            @"capabilities": @{
                @"javascriptcore": @YES,
                @"pureJavaScriptExecution": @YES,
                @"executionTimeLimit": @(_setExecutionTimeLimit != NULL && _clearExecutionTimeLimit != NULL),
                @"hardKillRecovery": @NO,
                @"nativeRPC": @YES,
                @"structuredConsole": @NO,
                @"oneActiveSession": @YES,
            },
        }];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStatus]) {
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStatus
                                          helperInstanceId:self.helperInstanceId
                                                 sessionId:request[kTLinkJSHelperKeySessionId]
                                                 requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:[self statusPayload]];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStart]) {
        return [self startWithRequest:request];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdStop]) {
        NSString *requestedSessionId = request[kTLinkJSHelperKeySessionId];
        if (requestedSessionId && self.activeSessionId && ![requestedSessionId isEqualToString:self.activeSessionId]) {
            return [self errorEnvelopeForRequest:request message:@"session_mismatch"];
        }
        if (self.activeSessionId && ([self.activeState isEqualToString:kTLinkJSHelperStateStarting] || [self.activeState isEqualToString:kTLinkJSHelperStateRunning])) {
            self.activeState = kTLinkJSHelperStateStopping;
            _cancelState->stopped.store(true, std::memory_order_release);
            [self.sleepCondition lock];
            [self.sleepCondition broadcast];
            [self.sleepCondition unlock];
        }
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdStop
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:[self statusPayload]];
    }
    if ([command isEqualToString:kTLinkJSHelperCmdNativeRPCResponse]) {
        NSDictionary *payload = [request[kTLinkJSHelperKeyPayload] isKindOfClass:[NSDictionary class]] ? request[kTLinkJSHelperKeyPayload] : @{};
        NSString *nativeRequestId = [payload[kTLinkJSHelperKeyRequestId] isKindOfClass:[NSString class]] ? payload[kTLinkJSHelperKeyRequestId] : @"";
        NSDictionary *result = [payload[@"result"] isKindOfClass:[NSDictionary class]] ? payload[@"result"] : @{};
        [self.rpcCondition lock];
        if ([nativeRequestId length] > 0) {
            self.nativeResponses[nativeRequestId] = result;
        }
        [self.rpcCondition broadcast];
        [self.rpcCondition unlock];
        return [TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdNativeRPCResponse
                                         helperInstanceId:self.helperInstanceId
                                                sessionId:request[kTLinkJSHelperKeySessionId]
                                                requestId:request[kTLinkJSHelperKeyRequestId]
                                                  payload:@{ kTLinkJSHelperKeyRequestId: nativeRequestId ?: @"", @"result": @{ @"ok": @YES, @"accepted": @YES } }];
    }
    return [self errorEnvelopeForRequest:request message:@"unsupported_command"];
}

- (NSData *)readAllFromClient:(int)client
{
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    while (true) {
        ssize_t n = read(client, buffer, sizeof(buffer));
        if (n > 0) {
            [data appendBytes:buffer length:(NSUInteger)n];
            if (data.length > 1024 * 1024) break;
            if (memchr(buffer, '\n', (size_t)n)) break;
            continue;
        }
        break;
    }
    return data;
}

- (void)handleClient:(int)client
{
    @autoreleasepool {
        NSData *requestData = [self readAllFromClient:client];
        NSError *err = nil;
        NSDictionary *request = [TLinkJSHelperProtocol deserializeEnvelope:requestData error:&err];
        NSDictionary *response = request ? [self handleEnvelope:request] : [self errorEnvelopeForRequest:@{} message:err.localizedDescription ?: @"invalid_json"];
        NSMutableData *responseData = [[TLinkJSHelperProtocol serializeEnvelope:response error:nil] mutableCopy];
        if (responseData) {
            const uint8_t newline = '\n';
            [responseData appendBytes:&newline length:1];
            const uint8_t *bytes = (const uint8_t *)responseData.bytes;
            NSUInteger remaining = responseData.length;
            while (remaining > 0) {
                ssize_t written = write(client, bytes, remaining);
                if (written <= 0) break;
                bytes += written;
                remaining -= (NSUInteger)written;
            }
        }
        close(client);
    }
}

- (void)run
{
    NSString *runDir = [kTLinkJSHelperSocketPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:nil error:nil];

    int pidFd = open([kTLinkJSHelperPidPath fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0644);
    if (pidFd < 0 && errno == EEXIST) {
        NSString *pidText = [NSString stringWithContentsOfFile:kTLinkJSHelperPidPath encoding:NSUTF8StringEncoding error:nil];
        pid_t existingPid = (pid_t)[pidText intValue];
        if (existingPid > 0 && existingPid != getpid() && kill(existingPid, 0) == 0) {
            NSLog(@"tlinkauto-jsd: helper pid %d is already running", existingPid);
            return;
        }
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        pidFd = open([kTLinkJSHelperPidPath fileSystemRepresentation], O_CREAT | O_EXCL | O_WRONLY, 0644);
    }
    if (pidFd < 0) {
        NSLog(@"tlinkauto-jsd: pid file create failed: %d", errno);
        return;
    }

    NSString *pidLine = [NSString stringWithFormat:@"%d", getpid()];
    NSData *pidData = [pidLine dataUsingEncoding:NSUTF8StringEncoding];
    if (pidData) write(pidFd, pidData.bytes, pidData.length);

    unlink([kTLinkJSHelperSocketPath fileSystemRepresentation]);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        NSLog(@"tlinkauto-jsd: socket failed: %d", errno);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, [kTLinkJSHelperSocketPath fileSystemRepresentation], sizeof(addr.sun_path) - 1);
    if (bind(server, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        NSLog(@"tlinkauto-jsd: bind failed: %d", errno);
        close(server);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }
    chmod([kTLinkJSHelperSocketPath fileSystemRepresentation], 0666);
    chmod([kTLinkJSHelperPidPath fileSystemRepresentation], 0644);
    if (listen(server, 8) != 0) {
        NSLog(@"tlinkauto-jsd: listen failed: %d", errno);
        close(server);
        close(pidFd);
        unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
        return;
    }

    NSLog(@"tlinkauto-jsd: ready instance=%@ socket=%@", self.helperInstanceId, kTLinkJSHelperSocketPath);
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            NSLog(@"tlinkauto-jsd: accept failed: %d", errno);
            break;
        }
        [self handleClient:client];
    }
    close(server);
    unlink([kTLinkJSHelperSocketPath fileSystemRepresentation]);
    close(pidFd);
    unlink([kTLinkJSHelperPidPath fileSystemRepresentation]);
}

@end
