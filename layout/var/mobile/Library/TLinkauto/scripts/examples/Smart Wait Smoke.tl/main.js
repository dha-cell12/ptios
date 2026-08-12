console.log('smart-wait/rootfull start');

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

requireCondition(typeof device.waitUntil === 'function', 'device.waitUntil alias missing');
requireCondition(TLinkauto.smartWaitSchema === 'smart_wait_result_v1', 'Smart Wait schema missing');

var stable = device.waitUntil(function(attempt) {
  return attempt >= 2 ? { ready: true } : false;
}, { timeoutMs: 1000, intervalMs: 20, stableFrames: 2 });
console.log('stable=' + JSON.stringify(stable));
requireCondition(stable.ok && stable.attempts === 3 && stable.stableMatches === 2, 'stable frame accounting failed');

var timeout = device.waitUntil(function() { return false; }, { timeoutMs: 0 });
console.log('timeout=' + JSON.stringify(timeout));
requireCondition(!timeout.ok && timeout.timedOut && timeout.attempts === 1, 'bounded timeout failed');

var foreground = device.frontMostAppId();
if (foreground.ok && foreground.bundleId) {
  var app = device.waitForApp(foreground.bundleId, { timeoutMs: 1000 });
  console.log('app=' + JSON.stringify(app));
  requireCondition(app.ok, 'waitForApp failed');
}

var currentColor = device.pickColor(10, 10);
if (currentColor.ok) {
  var color = device.waitForColor(10, 10, currentColor, {
    tolerance: 2,
    timeoutMs: 1000,
    intervalMs: 20,
    stableFrames: 2
  });
  console.log('color=' + JSON.stringify(color));
  requireCondition(color.ok, 'waitForColor failed');
}

console.log('smart-wait/rootfull finished');
