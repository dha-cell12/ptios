console.log('compat/smart-wait start');

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

requireCondition(typeof device.waitUntil === 'function', 'device.waitUntil alias missing');
requireCondition(typeof device.waitForApp === 'function', 'device.waitForApp alias missing');
requireCondition(typeof device.waitForColor === 'function', 'device.waitForColor alias missing');
requireCondition(typeof device.waitForImage === 'function', 'device.waitForImage alias missing');
requireCondition(typeof device.waitForText === 'function', 'device.waitForText alias missing');
requireCondition(typeof device.waitUntilGone === 'function', 'device.waitUntilGone alias missing');
requireCondition(typeof device.tapWhenVisible === 'function', 'device.tapWhenVisible alias missing');

var stable = device.waitUntil(function(attempt) {
  return attempt >= 2 ? { ready: true } : false;
}, { timeoutMs: 1000, intervalMs: 20, stableFrames: 2 });
console.log('stable=' + JSON.stringify(stable));
requireCondition(stable.ok && stable.attempts === 3 && stable.stableMatches === 2, 'stable frame accounting failed');

var timeout = device.waitUntil(function() { return false; }, { timeoutMs: 0 });
console.log('timeout=' + JSON.stringify(timeout));
requireCondition(!timeout.ok && timeout.timedOut && timeout.attempts === 1, 'bounded timeout failed');

var foreground = device.frontMostAppId();
console.log('frontmost=' + JSON.stringify(foreground));
if (foreground.ok && foreground.bundleId) {
  var app = device.waitForApp(foreground.bundleId, { timeoutMs: 1000, stableFrames: 1 });
  console.log('app=' + JSON.stringify(app));
  requireCondition(app.ok && app.value.bundleId === foreground.bundleId, 'waitForApp failed');
}

var currentColor = device.pickColor(10, 10);
console.log('picked=' + JSON.stringify(currentColor));
if (currentColor.ok) {
  var color = device.waitForColor(10, 10, currentColor, {
    tolerance: 2,
    timeoutMs: 1000,
    intervalMs: 20,
    stableFrames: 2
  });
  console.log('color=' + JSON.stringify(color));
  requireCondition(color.ok && color.stableMatches === 2, 'waitForColor failed');
}

console.log('compat/smart-wait finished');
