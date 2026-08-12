#ifndef TLINK_SMART_WAIT_PRELUDE_H
#define TLINK_SMART_WAIT_PRELUDE_H

#import <Foundation/Foundation.h>

// ES5-only on purpose: this prelude must run on the oldest JavaScriptCore
// supported by both the rootfull and TrollStore runtimes.
static inline NSString *TLinkSmartWaitPreludeSource(void)
{
    return [NSString stringWithUTF8String:R"TLINKWAIT(
(function(global){
  'use strict';
  var nativeDevice = global.device;
  if (!nativeDevice) throw new Error('Smart Wait requires device');
  var api = global.TLinkauto || {};
  var RESULT_SCHEMA = 'smart_wait_result_v1';
  var API_VERSION = 1;

  function finite(value, fallback){
    var number = Number(value);
    return isFinite(number) ? number : fallback;
  }

  function boundedInteger(value, fallback, minimum, maximum){
    var number = Math.floor(finite(value, fallback));
    if (number < minimum) number = minimum;
    if (number > maximum) number = maximum;
    return number;
  }

  function normalizeOptions(options, visual){
    options = options || {};
    return {
      timeoutMs: boundedInteger(options.timeoutMs, 5000, 0, 300000),
      intervalMs: boundedInteger(options.intervalMs, 200, 20, 10000),
      stableFrames: boundedInteger(options.stableFrames, 1, 1, 10),
      ignoreErrors: options.ignoreErrors == null ? !!visual : !!options.ignoreErrors,
      throwOnTimeout: !!options.throwOnTimeout
    };
  }

  function errorText(error){
    if (!error) return 'unknown_error';
    return String(error.message || error.errorMessage || error.error || error.raw || error);
  }

  function requireOk(value, operation){
    if (!value || value.ok === false) {
      throw new Error(operation + ': ' + errorText(value));
    }
    return value;
  }

  function stopRequested(){
    try {
      return typeof nativeDevice.shouldStop === 'function' && !!nativeDevice.shouldStop();
    } catch (_) {
      return false;
    }
  }

  function pause(milliseconds){
    if (milliseconds <= 0) return;
    if (typeof nativeDevice.sleep === 'function') {
      var sleepResult = nativeDevice.sleep(milliseconds / 1000.0);
      if (sleepResult && sleepResult.ok === false) throw new Error('smart_wait_cancelled');
      return;
    }
    if (typeof global.sleep === 'function') {
      global.sleep(milliseconds);
      return;
    }
    throw new Error('Smart Wait requires sleep');
  }

  function finish(kind, ok, timedOut, cancelled, attempts, start, stableMatches, value, lastError){
    return {
      schema: RESULT_SCHEMA,
      kind: kind,
      ok: !!ok,
      found: !!ok,
      timedOut: !!timedOut,
      cancelled: !!cancelled,
      attempts: attempts,
      elapsedMs: Math.max(0, Date.now() - start),
      stableMatches: stableMatches,
      value: value == null ? null : value,
      lastError: lastError || ''
    };
  }

  function waitUntil(predicate, options){
    if (typeof predicate !== 'function') throw new Error('waitUntil requires a predicate function');
    var opts = normalizeOptions(options, false);
    var kind = options && options.kind ? String(options.kind) : 'wait_until';
    var start = Date.now();
    var attempts = 0;
    var stableMatches = 0;
    var lastValue = null;
    var lastError = '';

    while (true) {
      if (stopRequested()) return finish(kind, false, false, true, attempts, start, stableMatches, lastValue, lastError);
      attempts++;
      try {
        var value = predicate(attempts);
        if (value) {
          stableMatches++;
          lastValue = value;
          if (stableMatches >= opts.stableFrames) {
            return finish(kind, true, false, false, attempts, start, stableMatches, value, lastError);
          }
        } else {
          stableMatches = 0;
          lastValue = value;
        }
      } catch (error) {
        stableMatches = 0;
        lastError = errorText(error);
        if (!opts.ignoreErrors) throw error;
      }

      var elapsed = Date.now() - start;
      if (elapsed >= opts.timeoutMs) break;
      try {
        pause(Math.min(opts.intervalMs, opts.timeoutMs - elapsed));
      } catch (sleepError) {
        if (errorText(sleepError) === 'smart_wait_cancelled' || stopRequested()) {
          return finish(kind, false, false, true, attempts, start, stableMatches, lastValue, lastError);
        }
        throw sleepError;
      }
    }

    var result = finish(kind, false, true, false, attempts, start, stableMatches, lastValue, lastError);
    if (opts.throwOnTimeout) {
      var timeoutError = new Error(kind + ' timed out after ' + result.elapsedMs + 'ms');
      timeoutError.result = result;
      throw timeoutError;
    }
    return result;
  }

  function visualOptions(options, kind){
    var out = {};
    options = options || {};
    for (var key in options) {
      if (Object.prototype.hasOwnProperty.call(options, key)) out[key] = options[key];
    }
    out.kind = kind;
    if (out.ignoreErrors == null) out.ignoreErrors = true;
    return out;
  }

  function frameOptions(options){
    var intervalMs = boundedInteger(options && options.intervalMs, 200, 20, 10000);
    return { gray: true, bgra: false, ttlMs: Math.max(1000, intervalMs + 500) };
  }

  function regionOptions(options){
    var region = options && options.region;
    return {
      x: region && region.length > 0 ? finite(region[0], 0) : finite(options && options.x, 0),
      y: region && region.length > 1 ? finite(region[1], 0) : finite(options && options.y, 0),
      width: region && region.length > 2 ? finite(region[2], 0) : finite(options && options.width, 0),
      height: region && region.length > 3 ? finite(region[3], 0) : finite(options && options.height, 0)
    };
  }

  function imageMatchOptions(options){
    var region = regionOptions(options);
    return {
      x: region.x,
      y: region.y,
      width: region.width,
      height: region.height,
      acceptable: finite(options && options.acceptable, 0.9),
      scaleMin: finite(options && options.scaleMin, 1.0),
      scaleMax: finite(options && options.scaleMax, 1.0),
      scaleStep: finite(options && options.scaleStep, 1.0),
      pixelSkip: boundedInteger(options && options.pixelSkip, 0, 0, 64),
      coord: options && options.coord ? String(options.coord) : 'pixel',
      maxAgeMs: boundedInteger(options && options.maxAgeMs, 1000, 100, 10000)
    };
  }

  function ocrOptions(options){
    var region = regionOptions(options);
    return {
      x: region.x,
      y: region.y,
      width: region.width,
      height: region.height,
      lang: options && options.lang ? String(options.lang) : 'eng',
      oem: boundedInteger(options && options.oem, 1, 0, 3),
      psm: boundedInteger(options && options.psm, 7, 0, 13),
      whitelist: options && options.whitelist ? String(options.whitelist) : '',
      scaleUp: boundedInteger(options && options.scaleUp, 2, 1, 4),
      thresholdMode: boundedInteger(options && options.thresholdMode, 0, 0, 3),
      coord: options && options.coord ? String(options.coord) : 'pixel',
      maxAgeMs: boundedInteger(options && options.maxAgeMs, 1000, 100, 10000)
    };
  }

  function parseColor(color){
    function channel(value){
      var number = Number(value);
      if (!isFinite(number) || number < 0 || number > 255) {
        throw new Error('waitForColor channels must be between 0 and 255');
      }
      return Math.round(number);
    }
    if (typeof color === 'string') {
      var match = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(color);
      if (!match) throw new Error('waitForColor requires #RRGGBB or RGB object');
      return { red: parseInt(match[1], 16), green: parseInt(match[2], 16), blue: parseInt(match[3], 16) };
    }
    if (color && typeof color.length === 'number' && color.length >= 3) {
      return { red: channel(color[0]), green: channel(color[1]), blue: channel(color[2]) };
    }
    if (color && typeof color === 'object') {
      return {
        red: channel(color.red == null ? color.r : color.red),
        green: channel(color.green == null ? color.g : color.green),
        blue: channel(color.blue == null ? color.b : color.blue)
      };
    }
    throw new Error('waitForColor requires #RRGGBB or RGB object');
  }

  function waitForApp(bundleId, options){
    if (!bundleId) throw new Error('waitForApp requires bundleId');
    var waitOptions = visualOptions(options, 'wait_for_app');
    var result = waitUntil(function(){
      var current = requireOk(nativeDevice.frontMostAppId(), 'frontMostAppId failed');
      return current.bundleId === bundleId ? current : false;
    }, waitOptions);
    result.bundleId = String(bundleId);
    return result;
  }

  function waitForColor(x, y, color, options){
    var expected = parseColor(color);
    var tolerance = Math.max(0, finite(options && options.tolerance, 0));
    var waitOptions = visualOptions(options, 'wait_for_color');
    var result = waitUntil(function(){
      var current = requireOk(nativeDevice.pickColor(x, y), 'pickColor failed');
      var matched = Math.abs(Number(current.red) - expected.red) <= tolerance &&
                    Math.abs(Number(current.green) - expected.green) <= tolerance &&
                    Math.abs(Number(current.blue) - expected.blue) <= tolerance;
      return matched ? current : false;
    }, waitOptions);
    result.expected = expected;
    result.tolerance = tolerance;
    result.x = Number(x);
    result.y = Number(y);
    return result;
  }

  function waitForImageState(path, options, wantPresent, kind){
    if (!path) throw new Error(kind + ' requires image path');
    var image = requireOk(nativeDevice.openImage(String(path)), 'openImage failed');
    var matchOptions = imageMatchOptions(options || {});
    var waitOptions = visualOptions(options, kind);
    try {
      var result = waitUntil(function(){
        var frame = requireOk(nativeDevice.captureFrame(frameOptions(options)), 'captureFrame failed');
        try {
          var match = requireOk(nativeDevice.findImageInFrame(frame.id, image.id, matchOptions), 'findImageInFrame failed');
          var present = !!(match.matched || match.found);
          if (wantPresent ? present : !present) return wantPresent ? match : { gone: true, lastMatch: match };
          return false;
        } finally {
          nativeDevice.releaseFrame(frame.id);
        }
      }, waitOptions);
      result.locator = { type: 'image', path: String(path) };
      if (!wantPresent) {
        result.gone = result.ok;
        result.found = false;
      }
      return result;
    } finally {
      nativeDevice.releaseImage(image.id);
    }
  }

  function waitForImage(path, options){
    return waitForImageState(path, options || {}, true, 'wait_for_image');
  }

  function waitUntilGone(path, options){
    return waitForImageState(path, options || {}, false, 'wait_until_gone');
  }

  function textMatched(actual, expected, options){
    var caseSensitive = !!(options && options.caseSensitive);
    var mode = options && options.matchMode ? String(options.matchMode) : 'contains';
    var left = String(actual == null ? '' : actual);
    var right = String(expected);
    if (!caseSensitive && mode !== 'regex') {
      left = left.toLowerCase();
      right = right.toLowerCase();
    }
    if (mode === 'equals') return left === right;
    if (mode === 'regex') return new RegExp(right, caseSensitive ? '' : 'i').test(left);
    return left.indexOf(right) >= 0;
  }

  function waitForText(text, options){
    if (text == null || String(text).length === 0) throw new Error('waitForText requires non-empty text');
    options = options || {};
    var waitOptions = visualOptions(options, 'wait_for_text');
    var result = waitUntil(function(){
      var frame = requireOk(nativeDevice.captureFrame(frameOptions(options)), 'captureFrame failed');
      try {
        var ocr = requireOk(nativeDevice.ocrFrame(frame.id, ocrOptions(options)), 'ocrFrame failed');
        return textMatched(ocr.text, text, options) ? ocr : false;
      } finally {
        nativeDevice.releaseFrame(frame.id);
      }
    }, waitOptions);
    result.locator = {
      type: 'text',
      text: String(text),
      matchMode: options.matchMode || 'contains',
      caseSensitive: !!options.caseSensitive
    };
    return result;
  }

  function tapWhenVisible(path, options){
    options = options || {};
    var result = waitForImage(path, options);
    result.kind = 'tap_when_visible';
    result.tapped = false;
    if (!result.ok || !result.value) return result;
    var x = finite(result.value.centerX, finite(result.value.x, 0) + finite(result.value.width, 0) / 2) + finite(options.offsetX, 0);
    var y = finite(result.value.centerY, finite(result.value.y, 0) + finite(result.value.height, 0) / 2) + finite(options.offsetY, 0);
    var tap = nativeDevice.tap(x, y);
    result.tap = tap;
    result.tapX = x;
    result.tapY = y;
    result.tapped = !!(tap && tap.ok !== false);
    if (!result.tapped) {
      result.ok = false;
      result.lastError = 'tap failed: ' + errorText(tap);
    }
    return result;
  }

  api.smartWaitVersion = API_VERSION;
  api.smartWaitSchema = RESULT_SCHEMA;
  api.waitUntil = waitUntil;
  api.waitForApp = waitForApp;
  api.waitForColor = waitForColor;
  api.waitForImage = waitForImage;
  api.waitForText = waitForText;
  api.waitUntilGone = waitUntilGone;
  api.tapWhenVisible = tapWhenVisible;
  global.TLinkauto = api;

  var aliases = {
    waitUntil: waitUntil,
    waitForApp: waitForApp,
    waitForColor: waitForColor,
    waitForImage: waitForImage,
    waitForText: waitForText,
    waitUntilGone: waitUntilGone,
    tapWhenVisible: tapWhenVisible
  };
  for (var alias in aliases) {
    if (!Object.prototype.hasOwnProperty.call(aliases, alias)) continue;
    try { nativeDevice[alias] = aliases[alias]; } catch (_) {}
  }
})(this);
)TLINKWAIT"];
}

#endif
