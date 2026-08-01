import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/zoom-p1-contract-v1.json"));

assert.equal(fixture.phase, 1);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.state, "experimental");
assert.equal(fixture.implemented, true);
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.task, 64);
assert.equal(fixture.wire, "task64_additive_zoom_v1");
assert.deepEqual(fixture.fingerCounts, [2, 3]);
assert.deepEqual(fixture.defaults, { angleDegrees: 0, baseFinger: 0 });
assert.equal(fixture.geometry.mode, "radial_linear_interpolation_v1");
assert.equal(fixture.geometry.stepCountIncludesEndpoints, true);
assert.equal(fixture.dispatch.mode, "legacy_multitouch_parent_frames");
assert.equal(fixture.dispatch.allFingersInEveryFrame, true);
assert.equal(fixture.dispatch.validation, "preflight_bounds_v1");
assert.equal(fixture.dispatch.cleanup, "all_fingers_up_on_exception_v1");
assert.equal(fixture.dispatch.successResponse, "0");
assert.deepEqual(fixture.legacyCompatibility, {
  task10Unchanged: true,
  task64SingleFingerUnchanged: true,
  task65SequentialBatchUnchanged: true,
});

const [
  rootTask,
  rootTouch,
  rootServer,
  trollServer,
  trollTouch,
  pythonClient,
  pythonTasks,
  deviceTest,
  phase1Doc,
  phase0Doc,
  trollStatusDoc,
  plan,
  rootWorkflow,
  trollWorkflow,
  trollPolicy,
  rootPolicy,
  rootNativeRequestHeader,
  rootNativeRequestImplementation,
  rootDeviceHeader,
  rootRuntime,
  rootBridge,
  rootJSHelper,
] = await Promise.all([
  read("pccontrol/Task.xm"),
  read("pccontrol/Touch.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/streamd/TouchInjector.mm"),
  read("webtango/tlinkauto/client.py"),
  read("webtango/tlinkauto/tasktypes.py"),
  read("scripts/Test-TLinkZoomPhase1.ps1"),
  read("docs/zoom-p1-multitouch.md"),
  read("docs/zoom-p0-baseline.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
  read("license-task-policy.json"),
  read("shared/TLinkRootfullLicensePolicy.mm"),
  read("pccontrol/jsruntime/TLinkJSNativeRequest.h"),
  read("pccontrol/jsruntime/TLinkJSNativeRequest.mm"),
  read("pccontrol/jsruntime/TLinkautoDeviceBridge.h"),
  read("pccontrol/TLinkautoJSRuntime.mm"),
  read("pccontrol/jsruntime/TLinkInProcessNativeBridge.mm"),
  read("tlinkauto-jsd/TLinkJSHelperServer.mm"),
]);

function assertZoomImplementation(label, source, names) {
  assert.match(source, names.handler, `${label} Zoom handler is missing`);
  assert.match(source, /parts\.count < 8 \|\| parts\.count > 10/);
  assert.match(source, /scanDouble:&parsed/);
  assert.match(source, /scanLongLong:&parsed/);
  assert.match(source, /!scanner\.isAtEnd \|\| !isfinite\(parsed\)/);
  assert.match(source, /durationMs < 50 \|\| durationMs > 5000/);
  assert.match(source, /fingerCount != 2 && fingerCount != 3/);
  assert.match(source, /steps < 2 \|\| steps > 120/);
  assert.match(source, /startRadius <= 0\.0 \|\| endRadius <= 0\.0/);
  assert.match(source, /baseFinger < 0 \|\| baseFinger \+ fingerCount > 20/);
  assert.match(source, /points\[finger\]\.x < 0\.0[\s\S]*points\[finger\]\.y >= screenHeight/);
  assert.match(source, /double t = \(double\)step \/ \(double\)\(steps - 1\)/);
  assert.match(source, /cos\(angle\) \* radius/);
  assert.match(source, /sin\(angle\) \* radius/);
  assert.match(source, /durationMs \* 1000 \/ \(steps - 1\)/);
  assert.match(source, names.downFrame);
  assert.match(source, names.moveFrame);
  assert.match(source, names.upFrame);
  assert.match(source, names.exceptionCleanup);
  assert.match(source, /zoom_dispatch_exception/);

  const preflight = source.indexOf("for (int step = 0; step < steps; step++)");
  const down = source.search(names.downFrame);
  assert.ok(preflight >= 0 && down > preflight, `${label} must preflight all geometry before DOWN`);
}

assertZoomImplementation("rootfull", rootTask, {
  handler: /static bool zx_handleNativeZoom/,
  downFrame: /zx_performTouchFrame\(TOUCH_DOWN/,
  moveFrame: /zx_performTouchFrame\(TOUCH_MOVE/,
  upFrame: /zx_performTouchFrame\(TOUCH_UP/,
  exceptionCleanup: /if \(fingersDown\) zx_performTouchFrame\(TOUCH_UP/,
});
assertZoomImplementation("TrollStore", trollServer, {
  handler: /static BOOL TLinkHandleNativeZoom/,
  downFrame: /TLinkPerformTouchFrame\(POC_TOUCH_DOWN/,
  moveFrame: /TLinkPerformTouchFrame\(POC_TOUCH_MOVE/,
  upFrame: /TLinkPerformTouchFrame\(POC_TOUCH_UP/,
  exceptionCleanup: /if \(fingersDown\) TLinkPerformTouchFrame\(POC_TOUCH_UP/,
});

for (const [label, source, frameName, rawName] of [
  ["rootfull", rootTask, "zx_performTouchFrame", "performTouchFromRawData"],
  ["TrollStore", trollServer, "TLinkPerformTouchFrame", "POCPerformTouchFromRawData"],
]) {
  const start = source.indexOf(`static void ${frameName}`);
  const end = source.indexOf("\n}\n", start) + 3;
  const frame = source.slice(start, end);
  assert.ok(start >= 0 && end > start, `${label} multi-touch frame helper is missing`);
  assert.match(frame, /stringWithFormat:@"%d", count/);
  assert.match(frame, /for \(int i = 0; i < count; i\+\+\)/);
  assert.match(frame, new RegExp(`${rawName}\\(`));
}

assert.match(rootTouch, /for \(int i = 0; i < touchCount; i\+\+\)/);
assert.match(trollTouch, /for \(int i = 0; i < touchCount; i\+\+\)/);
assert.match(rootTask, /Native gesture format: finger;;duration_ms;;x,y\|x,y\|\.\.\./);
assert.match(trollServer, /Native gesture format: finger;;duration_ms;;x,y\|x,y\|\.\.\./);
assert.doesNotMatch(rootTask, /zoom_not_implemented_phase0/);
assert.doesNotMatch(trollServer, /zoom_not_implemented_phase0/);

const trollPolicyObject = JSON.parse(trollPolicy);
assert.ok(trollPolicyObject.task_features?.automation?.includes(64));
assert.match(rootPolicy, /\{64, "automation"\}/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 is missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 is missing ${marker}`);
  assert.ok(phase1Doc.includes(marker), `Zoom P1 documentation is missing ${marker}`);
}
assert.match(rootTask, /@"zoom": @\{[\s\S]*?@"phase": @1[\s\S]*?@"state": @"experimental"[\s\S]*?@"implemented": @1/);
assert.match(trollServer, /@"zoom": @\(YES\)/);
assert.match(trollServer, /@"zoomState": @"experimental"/);
assert.match(trollServer, /@"zoomDeviceValidated": @\(NO\)/);

assert.match(pythonTasks, /TASK_NATIVE_GESTURE = 64/);
assert.match(pythonClient, /def zoom\(self, center_x, center_y, start_radius, end_radius,/);
assert.match(pythonClient, /tasktypes\.TASK_NATIVE_GESTURE,[\s\S]*?"zoom"/);
assert.match(rootNativeRequestHeader, /extern NSString \* const TLinkJSNativeMethodZoom/);
assert.match(rootNativeRequestImplementation, /TLinkJSNativeMethodZoom = @"zoom"/);
assert.match(rootDeviceHeader, /JSExportAs\(zoom,/);
assert.match(rootRuntime, /TLinkJSNativeMethodGesture, TLinkJSNativeMethodZoom/);
assert.match(rootRuntime, /- \(NSDictionary \*\)zoom:\(double\)centerX[\s\S]*TLinkJSNativeMethodZoom/);
assert.match(rootBridge, /\[method isEqualToString:TLinkJSNativeMethodZoom\][\s\S]*?TASK_NATIVE_GESTURE/);
assert.match(rootJSHelper, /device\[@"zoom"\]/);
assert.match(rootJSHelper, /\[method isEqualToString:@"zoom"\] \? 7\.0 : 5\.0/);
assert.match(trollServer, /device\[@"zoom"\][\s\S]*?TLinkScriptTaskResult\(weakSession, 64, payload\)/);
assert.match(deviceTest, /\[switch\]\$RunGesture/);
assert.match(deviceTest, /if \(\$RunGesture\)/);
assert.match(deviceTest, /zoom_finger_count_unsupported allowed=2,3/);
assert.match(deviceTest, /\[string\]\$Direction = "both"/);
assert.match(phase1Doc, /client disconnect does not interrupt/i);
assert.match(phase1Doc, /device\.zoom\(375, 667, 60, 160/);
assert.match(phase0Doc, /Historical baseline/i);
assert.match(trollStatusDoc, /Zoom P1/);
assert.match(plan, /Zoom P1/);
assert.match(rootWorkflow, /node scripts\/check-zoom-p1-multitouch\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-zoom-p1-multitouch\.mjs/);

console.log("Zoom P1 multi-touch OK: strict preflight, synchronized 2/3-finger frames, cleanup and clients wired");
