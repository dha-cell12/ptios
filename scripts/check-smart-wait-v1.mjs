import assert from "node:assert/strict";
import vm from "node:vm";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/smart-wait-v1.json"));

assert.equal(fixture.phase, 1);
assert.equal(fixture.state, "implemented");
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.resultSchema, "smart_wait_result_v1");
assert.equal(fixture.timeoutPolicy.attemptAtTimeoutZero, 1);

const [
  preludeHeader,
  rootRuntime,
  rootTask,
  rootServer,
  trollRuntime,
  webSdk,
  ide,
  trollExample,
  rootExample,
  scriptsController,
  docs,
  status,
  plan,
  rootWorkflow,
  trollWorkflow,
] = await Promise.all([
  read("shared/TLinkSmartWaitPrelude.h"),
  read("pccontrol/jsruntime/TLinkJSRuntimeCore.mm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("webtango/src/services/tlinkautoSdk.ts"),
  read("webtango/src/ide/AutomationIdeApp.tsx"),
  read("stream-app/app/CompatibilityExamples/09 Smart Wait.js"),
  read("layout/var/mobile/Library/TLinkauto/scripts/examples/Smart Wait Smoke.tl/main.js"),
  read("stream-app/app/ScriptsViewController.mm"),
  read("docs/smart-wait-visual-locator-v1.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
]);

const scriptMatch = preludeHeader.match(/R"TLINKWAIT\(\r?\n([\s\S]*?)\r?\n\)TLINKWAIT"/);
assert.ok(scriptMatch, "shared Smart Wait JavaScript prelude is not extractable");
const prelude = scriptMatch[1];

for (const method of fixture.methods) {
  assert.ok(prelude.includes(`api.${method} = ${method}`), `prelude does not export TLinkauto.${method}`);
  assert.ok(prelude.includes(`${method}: ${method}`), `prelude does not alias device.${method}`);
  assert.ok(webSdk.includes(`async ${method}`), `WebTango SDK does not expose ${method}`);
  assert.ok(ide.includes(`device.${method}`), `WebTango IDE does not expose ${method}`);
}

for (const field of fixture.resultFields) {
  assert.ok(prelude.includes(`${field}:`), `prelude result is missing ${field}`);
  assert.ok(webSdk.includes(`${field}:`), `WebTango result is missing ${field}`);
}

assert.match(rootRuntime, /#import "\.\.\/\.\.\/shared\/TLinkSmartWaitPrelude\.h"/);
assert.match(rootRuntime, /evaluateScript:TLinkSmartWaitPreludeSource\(\)/);
assert.match(trollRuntime, /#import "\.\.\/\.\.\/shared\/TLinkSmartWaitPrelude\.h"/);
assert.match(trollRuntime, /evaluateScript:TLinkSmartWaitPreludeSource\(\)/);
assert.match(prelude, /finally \{\s*nativeDevice\.releaseFrame\(frame\.id\);\s*\}/);
assert.match(prelude, /finally \{\s*nativeDevice\.releaseImage\(image\.id\);\s*\}/);
assert.match(prelude, /stableFrames: boundedInteger\(options\.stableFrames, 1, 1, 10\)/);
assert.match(prelude, /timeoutMs: boundedInteger\(options\.timeoutMs, 5000, 0, 300000\)/);
assert.match(webSdk, /async findImageObjectInFrame\(/);
assert.match(webSdk, /await this\.releaseFrame\(frame\)\.catch\(\(\) => \{\}\)/);
assert.match(webSdk, /await this\.releaseImage\(image\)\.catch\(\(\) => \{\}\)/);

for (const source of [rootTask, rootServer, trollRuntime, docs]) {
  assert.ok(source.includes("smart_wait_result_v1"), "Smart Wait schema marker missing");
  assert.ok(source.includes("rootfull_js_trollstore_js_webtango_v1"), "Smart Wait client marker missing");
}
for (const source of [rootServer, trollRuntime, docs]) {
  for (const marker of [
    "smartWaitState=implemented",
    "smartWaitPhase=1",
    "smartWaitSchema=smart_wait_result_v1",
    "smartWaitDeviceValidated=0",
  ]) {
    assert.ok(source.includes(marker), `capability marker missing: ${marker}`);
  }
}

assert.match(trollExample, /stable\.attempts === 3/);
assert.match(trollExample, /timeout\.attempts === 1/);
assert.match(rootExample, /TLinkauto\.smartWaitSchema/);
assert.match(scriptsController, /lastScript = \[suitePath stringByAppendingPathComponent:@"10 Failure Evidence\.tl"\]/);
assert.match(scriptsController, /installCompatibilityExamples:[\s\S]*?fileExistsAtPath:scriptPath[\s\S]*?continue;/);
assert.match(status, /Smart Wait v1/);
assert.match(plan, /Smart Wait v1/);
assert.match(rootWorkflow, /node scripts\/check-smart-wait-v1\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-smart-wait-v1\.mjs/);

let nextFrameId = 1;
let matchSequence = [];
let ocrSequence = [];
let cancelled = false;
const counters = {
  openImage: 0,
  releaseImage: 0,
  captureFrame: 0,
  releaseFrame: 0,
  tap: 0,
};
const device = {
  shouldStop: () => cancelled,
  sleep: () => ({ ok: !cancelled }),
  frontMostAppId: () => ({ ok: true, bundleId: "com.example.foreground" }),
  pickColor: () => ({ ok: true, red: 10, green: 20, blue: 30 }),
  openImage: () => {
    counters.openImage += 1;
    return { ok: true, id: 7, width: 20, height: 20 };
  },
  releaseImage: () => {
    counters.releaseImage += 1;
    return { ok: true };
  },
  captureFrame: () => {
    counters.captureFrame += 1;
    return { ok: true, id: nextFrameId++, width: 100, height: 100 };
  },
  releaseFrame: () => {
    counters.releaseFrame += 1;
    return { ok: true };
  },
  findImageInFrame: () => {
    const matched = matchSequence.length > 0 ? matchSequence.shift() : false;
    return { ok: true, matched, x: matched ? 10 : -1, y: matched ? 20 : -1, width: 20, height: 10, centerX: 20, centerY: 25, score: matched ? 0.99 : 0 };
  },
  ocrFrame: () => ({ ok: true, text: ocrSequence.length > 0 ? ocrSequence.shift() : "" }),
  tap: () => {
    counters.tap += 1;
    return { ok: true };
  },
};
const context = vm.createContext({ device });
vm.runInContext(prelude, context, { filename: "smart-wait-v1.js" });

for (const method of fixture.methods) {
  assert.equal(typeof context.device[method], "function", `device.${method} alias is not callable`);
  assert.equal(typeof context.TLinkauto[method], "function", `TLinkauto.${method} is not callable`);
}

const stable = context.device.waitUntil((attempt) => attempt >= 2, { timeoutMs: 100, intervalMs: 20, stableFrames: 2 });
assert.equal(stable.ok, true);
assert.equal(stable.attempts, 3);
assert.equal(stable.stableMatches, 2);
assert.equal(stable.schema, fixture.resultSchema);

const timeout = context.device.waitUntil(() => false, { timeoutMs: 0 });
assert.equal(timeout.ok, false);
assert.equal(timeout.timedOut, true);
assert.equal(timeout.attempts, 1);

matchSequence = [false, true, true];
const image = context.device.waitForImage("button.png", { timeoutMs: 100, intervalMs: 20, stableFrames: 2 });
assert.equal(image.ok, true);
assert.equal(image.attempts, 3);
assert.equal(counters.openImage, 1);
assert.equal(counters.releaseImage, 1);
assert.equal(counters.captureFrame, 3);
assert.equal(counters.releaseFrame, 3);

matchSequence = [true, false, false];
const gone = context.device.waitUntilGone("loading.png", { timeoutMs: 100, intervalMs: 20, stableFrames: 2 });
assert.equal(gone.ok, true);
assert.equal(gone.gone, true);
assert.equal(gone.found, false);
assert.equal(counters.openImage, 2);
assert.equal(counters.releaseImage, 2);
assert.equal(counters.captureFrame, 6);
assert.equal(counters.releaseFrame, 6);

ocrSequence = ["Welcome", "Welcome Login", "Welcome Login"];
const text = context.device.waitForText("login", { timeoutMs: 100, intervalMs: 20, stableFrames: 2 });
assert.equal(text.ok, true);
assert.equal(text.attempts, 3);
assert.equal(counters.captureFrame, 9);
assert.equal(counters.releaseFrame, 9);

matchSequence = [true];
const tapped = context.device.tapWhenVisible("button.png", { timeoutMs: 100 });
assert.equal(tapped.ok, true);
assert.equal(tapped.tapped, true);
assert.equal(tapped.tapX, 20);
assert.equal(tapped.tapY, 25);
assert.equal(counters.tap, 1);

const beforeTimeoutResources = { ...counters };
matchSequence = [false];
const missing = context.device.waitForImage("missing.png", { timeoutMs: 0 });
assert.equal(missing.timedOut, true);
assert.equal(missing.attempts, 1);
assert.equal(counters.openImage - beforeTimeoutResources.openImage, 1);
assert.equal(counters.releaseImage - beforeTimeoutResources.releaseImage, 1);
assert.equal(counters.captureFrame - beforeTimeoutResources.captureFrame, 1);
assert.equal(counters.releaseFrame - beforeTimeoutResources.releaseFrame, 1);

assert.throws(
  () => context.device.waitUntil(() => false, { timeoutMs: 0, throwOnTimeout: true }),
  /wait_until timed out/,
);

cancelled = true;
const beforeCancelledResources = { ...counters };
const cancelledImage = context.device.waitForImage("cancelled.png", { timeoutMs: 100 });
assert.equal(cancelledImage.cancelled, true);
assert.equal(cancelledImage.attempts, 0);
assert.equal(counters.openImage - beforeCancelledResources.openImage, 1);
assert.equal(counters.releaseImage - beforeCancelledResources.releaseImage, 1);
assert.equal(counters.captureFrame - beforeCancelledResources.captureFrame, 0);
const stopped = context.device.waitUntil(() => true, { timeoutMs: 100 });
assert.equal(stopped.cancelled, true);
assert.equal(stopped.attempts, 0);

console.log("Smart Wait v1 OK: shared JSC prelude, bounded stable locators, cleanup and WebTango parity");
