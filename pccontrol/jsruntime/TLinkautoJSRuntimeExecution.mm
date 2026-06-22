#import "TLinkautoJSRuntimeExecution.h"
#import "TLinkautoJSBridge.h"
#import "../Task.h"
#import "../RuntimeUtils.h"

@implementation TLinkautoJSRuntimeExecution {
    TLinkautoJSCancellationToken *_cancellationToken;
    TLinkautoJSCWatchdog *_watchdog;
    JSVirtualMachine *_jsVirtualMachine;
    TLinkautoJSBridge *_bridge;
    NSString *_bundlePath;
    NSDictionary *_manifest;
}

- (instancetype)initWithRunId:(NSString *)runId
                   generation:(uint64_t)generation
                   bundlePath:(NSString *)bundlePath
                     manifest:(NSDictionary *)manifest
               taskDispatcher:(id<TLinkautoJSTaskDispatcher>)taskDispatcher {
    self = [super init];
    if (self) {
        _runId = [runId copy];
        _generation = generation;
        _bundlePath = [bundlePath copy];
        _manifest = [manifest copy];
        _taskDispatcher = taskDispatcher;

        _sleepCondition = [[NSCondition alloc] init];
        _cancellationToken = [[TLinkautoJSCancellationToken alloc] init];
        _watchdog = [[TLinkautoJSCWatchdog alloc] initWithToken:_cancellationToken];
        _logSink = [[TLinkautoJSFileLogSink alloc] initWithRunId:_runId bundlePath:_bundlePath];
        _handleRegistry = [[TLinkautoJSHandleRegistry alloc] init];

        _jsVirtualMachine = [[JSVirtualMachine alloc] init];
        _jsContext = [[JSContext alloc] initWithVirtualMachine:_jsVirtualMachine];

        _bridge = [[TLinkautoJSBridge alloc] initWithExecution:self];
        [_bridge injectIntoContext:_jsContext];
    }
    return self;
}

- (BOOL)isAborted {
    return [_cancellationToken isCancelled];
}

- (void)requestStop {
    [_cancellationToken cancel];
    [_sleepCondition lock];
    [_sleepCondition broadcast];
    [_sleepCondition unlock];
}

- (void)evaluateScriptAtPath:(NSString *)scriptPath error:(NSError **)error {
    [_watchdog installForContext:_jsContext];

    NSString *consolePrelude =
        @"(function(){\n"
         "  function fmt(args){ return Array.prototype.map.call(args, function(v){\n"
         "    try { if (typeof v === 'string') return v; return JSON.stringify(v); }\n"
         "    catch(e) { return String(v); }\n"
         "  }).join(' '); }\n"
         "  this.console = {\n"
         "    log: function(){ _tlinkautoLog('log', fmt(arguments)); },\n"
         "    info: function(){ _tlinkautoLog('info', fmt(arguments)); },\n"
         "    warn: function(){ _tlinkautoLog('warn', fmt(arguments)); },\n"
         "    error: function(){ _tlinkautoLog('error', fmt(arguments)); }\n"
         "  };\n"
         "})();";

    NSString *modulePrelude =
        @"(function(){\n"
         "  var cache = Object.create(null);\n"
         "  var stack = [];\n"
         "  function dirname(path){ var i = path.lastIndexOf('/'); return i >= 0 ? path.slice(0, i) : ''; }\n"
         "  function normalize(base, request){\n"
         "    if (typeof request !== 'string' || !request) throw new Error('module path is required');\n"
         "    var input = request;\n"
         "    if (request.indexOf('./') === 0 || request.indexOf('../') === 0) {\n"
         "      input = (base ? dirname(base) + '/' : '') + request;\n"
         "    }\n"
         "    var parts = input.split('/');\n"
         "    var out = [];\n"
         "    for(var i=0; i<parts.length; i++){\n"
         "      var p = parts[i];\n"
         "      if(!p || p === '.') continue;\n"
         "      if(p === '..') out.pop();\n"
         "      else out.push(p);\n"
         "    }\n"
         "    return out.join('/');\n"
         "  }\n"
         "  this.require = function(request){\n"
         "    var base = stack.length > 0 ? stack[stack.length - 1] : '';\n"
         "    var id = normalize(base, request);\n"
         "    if (cache[id]) return cache[id].exports;\n"
         "    var res = device.readText(id + '.js');\n"
         "    if (!res.ok) { res = device.readText(id + '/index.js'); if (res.ok) id = id + '/index'; }\n"
         "    if (!res.ok) { res = device.readText(id + '.json'); if (res.ok) return JSON.parse(res.text); }\n"
         "    if (!res.ok) throw new Error('Cannot find module: ' + request);\n"
         "    var mod = { exports: {} };\n"
         "    cache[id] = mod;\n"
         "    stack.push(id);\n"
         "    try {\n"
         "      var fn = new Function('exports', 'require', 'module', '__filename', '__dirname', res.text);\n"
         "      fn(mod.exports, require, mod, id + '.js', dirname(id));\n"
         "    } finally {\n"
         "      stack.pop();\n"
         "    }\n"
         "    return mod.exports;\n"
         "  };\n"
         "  this.include = function(request){\n"
         "    var base = stack.length > 0 ? stack[stack.length - 1] : '';\n"
         "    var id = normalize(base, request);\n"
         "    var res = device.readText(id + '.js');\n"
         "    if (!res.ok) throw new Error('Cannot find file: ' + request);\n"
         "    var fn = new Function(res.text);\n"
         "    fn();\n"
         "  };\n"
         "})();";

    NSString *helperPrelude =
        @"(function(){\n"
         "  function normalizeOptions(options, defaults){\n"
         "    options = options || {};\n"
         "    var out = {};\n"
         "    Object.keys(defaults).forEach(function(k){ out[k] = options[k] == null ? defaults[k] : options[k]; });\n"
         "    return out;\n"
         "  }\n"
         "  var api = this.TLinkauto || {};\n"
         "  api.version = '1.0';\n"
         "  api.assert = function(condition, message){\n"
         "    if (!condition) throw new Error('Assertion failed: ' + (message || ''));\n"
         "  };\n"
         "  api.ensureOk = function(result, message){\n"
         "    if (!result || !result.ok) throw new Error((message || 'Operation failed') + ': ' + (result ? result.error : 'unknown'));\n"
         "    return result;\n"
         "  };\n"
         "  api.waitUntil = function(predicate, options){\n"
         "    options = normalizeOptions(options, { timeoutMs: 5000, intervalMs: 200 });\n"
         "    var end = Date.now() + options.timeoutMs;\n"
         "    var attempt = 1;\n"
         "    while (Date.now() < end) {\n"
         "      var res = predicate(attempt++);\n"
         "      if (res) return res;\n"
         "      device.sleep(options.intervalMs);\n"
         "    }\n"
         "    return null;\n"
         "  };\n"
         "  api.retry = function(action, options){\n"
         "    options = normalizeOptions(options, { retries: 3, delayMs: 1000 });\n"
         "    var lastErr;\n"
         "    for (var i = 1; i <= options.retries; i++) {\n"
         "      try {\n"
         "        var res = action(i);\n"
         "        if (res && res.ok !== false) return { ok: true, value: res, attempts: i };\n"
         "        lastErr = res ? res.error : 'unknown failure';\n"
         "      } catch (e) {\n"
         "        lastErr = String(e);\n"
         "      }\n"
         "      if (i < options.retries) device.sleep(options.delayMs);\n"
         "    }\n"
         "    return { ok: false, error: lastErr, attempts: options.retries };\n"
         "  };\n"
         "  api.waitForApp = function(bundleId, options){\n"
         "    options = normalizeOptions(options, { timeoutMs: 10000, intervalMs: 500 });\n"
         "    return api.waitUntil(function(){\n"
         "      var state = device.appState(bundleId);\n"
         "      var active = device.frontMostAppId();\n"
         "      return state.ok && state.state >= 4 && active.ok && active.bundleId === bundleId;\n"
         "    }, options);\n"
         "  };\n"
         "  api.waitForColor = function(x, y, targetColor, options){\n"
         "    options = normalizeOptions(options, { timeoutMs: 5000, intervalMs: 200, tolerance: 0 });\n"
         "    return api.waitUntil(function(){\n"
         "      var c = device.pickColor(x, y);\n"
         "      if (!c.ok) return false;\n"
         "      var dr = Math.abs(c.red - targetColor.red);\n"
         "      var dg = Math.abs(c.green - targetColor.green);\n"
         "      var db = Math.abs(c.blue - targetColor.blue);\n"
         "      return dr <= options.tolerance && dg <= options.tolerance && db <= options.tolerance;\n"
         "    }, options);\n"
         "  };\n"
         "  api.withFrame = function(options, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withFrame requires a callback');\n"
         "    var frame = api.ensureOk(device.captureFrame(options || {}), 'captureFrame failed');\n"
         "    try { return callback(frame); }\n"
         "    finally { device.releaseFrame(frame.id); }\n"
         "  };\n"
         "  api.withImage = function(path, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withImage requires a callback');\n"
         "    var img = api.ensureOk(device.openImage(path), 'openImage failed');\n"
         "    try { return callback(img); }\n"
         "    finally { device.releaseImage(img.id); }\n"
         "  };\n"
         "  api.withCapturedImage = function(x, y, w, h, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withCapturedImage requires a callback');\n"
         "    var img = api.ensureOk(device.captureImage(x, y, w, h), 'captureImage failed');\n"
         "    try { return callback(img); }\n"
         "    finally { device.releaseImage(img.id); }\n"
         "  };\n"
         "  this.TLinkauto = api;\n"
         "})();";

    [_jsContext evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://console-prelude.js"]];
    [_jsContext evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://module-prelude.js"]];
    [_jsContext evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];

    // Inject log callback manually to pipe console logs to our native LogSink
    __weak typeof(self) weakSelf = self;
    _jsContext[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
        [weakSelf.logSink logWithLevel:level message:message];
    };

    NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:error];
    if (script) {
        NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath];
        [_jsContext evaluateScript:script withSourceURL:sourceURL];
    }

    [_watchdog clearForContext:_jsContext];

    // Cleanup handles
    [_handleRegistry releaseAll];
    [_logSink close];
}

@end
