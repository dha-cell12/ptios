import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/zoom-p2-observability-v1.json"));

assert.equal(fixture.phase, 2);
assert.equal(fixture.state, "experimental");
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.wire, "task64_additive_zoom_v1");
assert.equal(fixture.diagnosticsSchema, "zoom_runtime_diagnostics_v1");
assert.deepEqual(fixture.results, ["none", "success", "validation_rejected", "dispatch_exception"]);
assert.deepEqual(fixture.directions, ["unknown", "spread", "pinch"]);
assert.equal(fixture.counterInvariants.successfulGestureFrames, "steps+1");
assert.equal(fixture.counterInvariants.validationRejectFrames, 0);
assert.equal(fixture.clients.webtango, "TLinkautoDeviceSdk.zoom");
assert.equal(fixture.clients.webtangoTimeout, "max(3000,duration_ms+2000)");

const [
  rootTask,
  rootServer,
  trollServer,
  wsClient,
  webSdk,
  ideApp,
  ideScreen,
  deviceTest,
  phase2Doc,
  phase1Doc,
  trollStatusDoc,
  plan,
  rootWorkflow,
  trollWorkflow,
] = await Promise.all([
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("webtango/src/TLinkautoWsClient.ts"),
  read("webtango/src/services/tlinkautoSdk.ts"),
  read("webtango/src/ide/AutomationIdeApp.tsx"),
  read("webtango/src/ide/IdeScreenPanel.tsx"),
  read("scripts/Test-TLinkZoomPhase2.ps1"),
  read("docs/zoom-p2-observability-webtango.md"),
  read("docs/zoom-p1-multitouch.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
]);

function assertDiagnostics(label, source, prefix, dictionaryName) {
  for (const counter of [
    "AttemptCount",
    "SuccessCount",
    "ValidationRejectedCount",
    "DispatchExceptionCount",
    "CleanupCount",
    "FrameCount",
  ]) {
    assert.match(source, new RegExp(`static std::atomic<uint64_t> ${prefix}${counter}\\(0\\)`),
      `${label} is missing ${counter}`);
  }
  assert.match(source, new RegExp(`static NSDictionary \\*${dictionaryName}\\(void\\)`));
  assert.match(source, /@"schema": @"zoom_runtime_diagnostics_v1"/);
  for (const field of fixture.diagnosticsFields) {
    assert.ok(source.includes(`@"${field}"`), `${label} diagnostics is missing ${field}`);
  }
  assert.match(source, new RegExp(`${prefix}AttemptCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
  assert.match(source, new RegExp(`${prefix}SuccessCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
  assert.match(source, new RegExp(`${prefix}ValidationRejectedCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
  assert.match(source, new RegExp(`${prefix}DispatchExceptionCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
  assert.match(source, new RegExp(`${prefix}CleanupCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
  assert.match(source, new RegExp(`${prefix}FrameCount\\.fetch_add\\(1, std::memory_order_relaxed\\)`));
}

assertDiagnostics("rootfull", rootTask, "sTLinkZoom", "zx_zoomDiagnostics");
assertDiagnostics("TrollStore", trollServer, "sTLinkZoom", "TLinkZoomDiagnosticsDictionary");
assert.match(rootTask, /@"diagnostics": zx_zoomDiagnostics\(\)/);
assert.match(trollServer, /@"zoomDiagnostics": TLinkZoomDiagnosticsDictionary\(\)/);
assert.match(rootTask, /@"phase": @2/);
assert.match(trollServer, /@"zoomPhase": @2/);
assert.match(rootTask, /timeIntervalSince1970/);
assert.match(trollServer, /sTLinkZoomLastAtMs\.store\(\(uint64_t\)\(\[\[NSDate date\] timeIntervalSince1970\]/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 is missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 is missing ${marker}`);
  assert.ok(phase2Doc.includes(marker), `Zoom P2 documentation is missing ${marker}`);
}

assert.match(wsClient, /async requestWithTimeout\(task: number, timeoutMs: number/);
assert.match(wsClient, /const line = await this\.nextLine\(timeoutMs\)/);
assert.match(webSdk, /export type ZoomOptions/);
assert.match(webSdk, /async zoom\(centerX: number, centerY: number, startRadius: number, endRadius: number/);
assert.match(webSdk, /this\.client\.requestWithTimeout\([\s\S]*?64,[\s\S]*?Math\.max\(3000, durationMs \+ 2000\)/);
assert.match(ideApp, /zoom\(centerX: number, centerY: number, startRadius: number, endRadius: number/);
assert.match(ideApp, /label: 'device\.zoom'/);
assert.match(ideScreen, /const zoomSnippet = \(direction: 'spread' \| 'pinch'\)/);
assert.match(ideScreen, />Zoom in</);
assert.match(ideScreen, />Zoom out</);

assert.match(deviceTest, /Get-TLinkZoomDiagnostics/);
assert.match(deviceTest, /validation frame delta/);
assert.match(deviceTest, /\$gestureCount \* \(\$Steps \+ 1\)/);
assert.match(deviceTest, /last_direction/);
assert.match(phase2Doc, /Counters are process-lifetime evidence/i);
assert.match(phase2Doc, /must still report the visual pinch\/spread result/i);
assert.match(phase1Doc, /Historical implementation milestone/i);
assert.match(trollStatusDoc, /Zoom P2/);
assert.match(plan, /Zoom P2/);
assert.match(rootWorkflow, /node scripts\/check-zoom-p2-observability\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-zoom-p2-observability\.mjs/);

console.log("Zoom P2 observability OK: runtime counters, frame invariants and WebTango clients wired");
