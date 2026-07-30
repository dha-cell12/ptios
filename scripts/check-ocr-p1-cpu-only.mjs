import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/ocr-p1-cpu-only.json"));

assert.equal(fixture.phase, "P1");
assert.equal(fixture.task, 27);
assert.equal(fixture.profileFieldIndex, 8);
assert.equal(fixture.defaultProfile, "app_cpu");
assert.deepEqual(fixture.allowedProfiles, ["app_cpu", "worker_cpu"]);

function task27Parts(request) {
  const line = request.replace(/\r?\n$/, "");
  assert.ok(line.startsWith("27"), "fixture must use task 27");
  return line.slice(2).split(";;");
}

const legacyParts = task27Parts(fixture.legacyRequest);
assert.equal(legacyParts.length, 8);
assert.equal(legacyParts[fixture.profileFieldIndex], undefined);
for (const request of [fixture.appCPURequest, fixture.workerCPURequest]) {
  const parts = task27Parts(request);
  assert.equal(parts.length, 9);
  assert.ok(fixture.allowedProfiles.includes(parts[fixture.profileFieldIndex]));
}

const [
  server,
  app,
  serverMakefile,
  appMakefile,
  collector,
  p1Doc,
  findingsDoc,
  buildWorkflow,
  trollstoreWorkflow,
] = await Promise.all([
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/app/AppDelegate.mm"),
  read("stream-app/streamd/Makefile"),
  read("stream-app/app/Makefile"),
  read("scripts/Collect-TLinkOCRBaseline.ps1"),
  read("docs/ocr-p1-cpu-only.md"),
  read("docs/ocr-p1-device-findings.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
]);

assert.match(server, /parts\.count >= 9[\s\S]*?parts\[8\][\s\S]*?: @"app_cpu"/);
assert.match(server, /isEqualToString:@"app_cpu"[\s\S]*?isEqualToString:@"worker_cpu"/);
assert.match(server, /vision_profile_app_cpu[\s\S]*?return TLinkRunAppSideVisionOCR/);
assert.match(server, /vision_profile_worker_cpu[\s\S]*?VNRecognizeTextRequest/);
assert.match(server, /vision_cpu_configure[\s\S]*?TLinkConfigureVisionRequestCPUOnly/);
assert.match(server, /supportedComputeStageDevicesAndReturnError/);
assert.match(server, /setComputeDevice:cpuDevice forComputeStage:stage/);
assert.match(server, /request\.usesCPUOnly = YES/);
assert.match(server, /@"ocrVisionState": @"experimental"/);
assert.match(server, /@"ocrVisionProfile": @"app_cpu_default_worker_cpu_opt_in"/);
assert.match(server, /@"ocrVisionCPUOnly": @\(YES\)/);
assert.match(app, /TLinkConfigureVisionRequestCPUOnly/);
assert.match(app, /supportedComputeStageDevicesAndReturnError/);
assert.match(app, /setComputeDevice:cpuDevice forComputeStage:stage/);
assert.match(app, /request\.usesCPUOnly = YES/);
assert.match(app, /profile=app_cpu CPU-only request configured/);

assert.match(serverMakefile, /streamd_FRAMEWORKS = .* Vision CoreML /);
assert.match(appMakefile, /StreamControl_FRAMEWORKS = .* Vision CoreML /);
assert.match(server, /#import <CoreML\/CoreML\.h>/);
assert.match(app, /#import <CoreML\/CoreML\.h>/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(server.includes(`${key}=${value}`), `task 97 is missing ${key}=${value}`);
}

assert.match(collector, /\[ValidateSet\("app_cpu", "worker_cpu"\)\]/);
assert.match(collector, /\[string\]\$VisionProfile = "app_cpu"/);
assert.match(collector, /\$visionTask = "271;;\$rect[\s\S]*;;;;\$VisionProfile"/);
assert.match(collector, /vision_profile = \$VisionProfile/);
assert.match(p1Doc, /app_cpu/);
assert.match(p1Doc, /worker_cpu/);
assert.match(findingsDoc, /\*\*Deferred on 2026-07-31\.\*\*/);
assert.match(findingsDoc, /signal=11 phase=vision_perform_requests/);
assert.match(findingsDoc, /Fast pipeline remained blocked for at least twenty seconds/i);
assert.match(findingsDoc, /all production automation should use task `91`/i);
assert.match(buildWorkflow, /node scripts\/check-ocr-p1-cpu-only\.mjs/);
assert.match(trollstoreWorkflow, /node scripts\/check-ocr-p1-cpu-only\.mjs/);

console.log("OCR P1 CPU-only OK: app_cpu default, worker_cpu opt-in, legacy task 27 response preserved");
