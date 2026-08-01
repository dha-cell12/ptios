import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/zoom-p0-contract-v1.json"));

assert.equal(fixture.phase, 0);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.state, "contract_only");
assert.equal(fixture.task, 64);
assert.deepEqual(fixture.legacyTask64, {
  format: "finger;;duration_ms;;x,y|x,y|...",
  unchanged: true,
  singleFinger: true,
});
assert.equal(fixture.reservedZoom.discriminator, "zoom");
assert.equal(
  fixture.reservedZoom.format,
  "zoom;;center_x;;center_y;;start_radius;;end_radius;;duration_ms;;finger_count;;steps[;;angle_degrees;;base_finger]",
);
assert.deepEqual(fixture.reservedZoom.fingerCounts, [2, 3]);
assert.equal(fixture.reservedZoom.direction.spread, "end_radius_gt_start_radius");
assert.equal(fixture.reservedZoom.direction.pinch, "end_radius_lt_start_radius");
assert.equal(fixture.reservedZoom.stablePhase0Error, "zoom_not_implemented_phase0");
assert.deepEqual(fixture.reservedZoom.defaults, { angleDegrees: 0, baseFinger: 0 });
assert.deepEqual(fixture.limits, {
  durationMs: { min: 50, max: 5000 },
  steps: { min: 2, max: 120 },
  radius: { minExclusive: 0 },
  angleDegrees: { min: -360, max: 360 },
});
assert.deepEqual(fixture.rawFoundation, {
  task: 10,
  recordWidth: 13,
  recordFormat: "type:1,index:2,x_tenths:5,y_tenths:5",
  wireCountDigits: 1,
  wireMaxTouchesPerFrame: 9,
  backendMaxFingerIndex: 20,
  simultaneousParentEvent: true,
  touchTypes: { up: 0, down: 1, move: 2 },
});

const [
  rootTouch,
  trollTouch,
  rootTask,
  rootServer,
  trollServer,
  pythonClient,
  deviceTest,
  baselineDoc,
  trollStatusDoc,
  plan,
  rootWorkflow,
  trollWorkflow,
  trollPolicy,
  rootPolicy,
] = await Promise.all([
  read("pccontrol/Touch.xm"),
  read("stream-app/streamd/TouchInjector.mm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("webtango/tlinkauto/client.py"),
  read("scripts/Test-TLinkZoomPhase0.ps1"),
  read("docs/zoom-p0-baseline.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
  read("license-task-policy.json"),
  read("shared/TLinkRootfullLicensePolicy.mm"),
]);

for (const [label, source] of [["rootfull", rootTouch], ["TrollStore", trollTouch]]) {
  assert.match(source, /#define MAX_FINGER_INDEX 20/, `${label} finger-index ceiling changed`);
  assert.match(source, /a\[0\] < '0'.*a\[0\] > '9'|dataArray\[0\] < '0'.*dataArray\[0\] > '9'/s,
    `${label} must retain the one-digit task 10 touch count`);
  assert.match(source, /IOHIDEventCreateDigitizerEvent/, `${label} must create a parent digitizer event`);
  assert.match(source, /for \(int i = 0; i < touchCount; i\+\+\)/,
    `${label} must append all frame fingers to one parent`);
  assert.match(source, /IOHIDEventAppendEvent\(parent,/,
    `${label} must append child digitizer events to the parent`);
}
assert.match(pythonClient, /def touch_with_list\(self, touch_list: list\):/);
assert.match(pythonClient, /str\(len\(touch_list\)\) \+ event_data/);

const trollPolicyObject = JSON.parse(trollPolicy);
assert.ok(
  trollPolicyObject.task_features?.automation?.includes(64),
  "TrollStore task 64 must remain covered by the automation license gate",
);
assert.match(rootPolicy, /\{64, "automation"\}/);

assert.match(rootTask, /\[\[parts\[0\] lowercaseString\] isEqualToString:@"zoom"\]/);
assert.match(rootTask, /@"-1;;zoom_not_implemented_phase0\\r\\n"/);
assert.match(rootTask, /Native gesture format: finger;;duration_ms;;x,y\|x,y\|\.\.\./);
assert.match(rootTask, /@"zoom": @\{[\s\S]*?@"phase": @0[\s\S]*?@"state": @"contract_only"[\s\S]*?@"legacy_task64_unchanged": @1/);

assert.match(trollServer, /\[\[parts\[0\] lowercaseString\] isEqualToString:@"zoom"\]/);
assert.match(trollServer, /@"zoom_not_implemented_phase0"/);
assert.match(trollServer, /Native gesture format: finger;;duration_ms;;x,y\|x,y\|\.\.\./);
assert.match(trollServer, /@"zoom": @\(NO\)/);
assert.match(trollServer, /@"zoomState": @"contract_only"/);
assert.match(trollServer, /@"zoomFingerCounts": @\[@2, @3\]/);

const fields = fixture.requiredCapabilityFields;
for (const [key, value] of Object.entries(fields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 is missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 is missing ${marker}`);
  assert.ok(baselineDoc.includes(marker), `Zoom P0 documentation is missing ${marker}`);
}

assert.doesNotMatch(rootTask, /zx_handleNativeZoom/);
assert.doesNotMatch(trollServer, /TLinkHandleNativeZoom/);
assert.match(deviceTest, /gesture_dispatched = \$false/);
assert.match(deviceTest, /64zoom;;500;;900;;60;;160;;300;;2;;20/);
assert.match(deviceTest, /-1;;zoom_not_implemented_phase0/);
assert.match(baselineDoc, /does not synthesize a zoom\s+gesture yet/i);
assert.match(baselineDoc, /no\s+HID event is dispatched/i);
assert.match(baselineDoc, /Task `64` remains under[\s\S]*`automation` gate/i);
assert.match(trollStatusDoc, /Zoom P0/);
assert.match(plan, /Zoom P0/);
assert.match(rootWorkflow, /node scripts\/check-zoom-p0-baseline\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-zoom-p0-baseline\.mjs/);

console.log(
  "Zoom P0 baseline OK: task 64 additive contract reserved; task 10 multi-touch foundation and legacy task 64 frozen",
);
