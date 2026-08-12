import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/run-history-failure-evidence-v1.json"));

assert.equal(fixture.phase, 1);
assert.equal(fixture.state, "implemented");
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.transport, "task60_status_json_v1");
assert.deepEqual(fixture.schemas, { history: "run_history_v1", evidence: "failure_evidence_v1" });
assert.deepEqual(fixture.states, ["running", "finished", "failed", "cancelled", "license_revoked"]);
assert.equal(fixture.retention.maximumRuns, 50);
assert.equal(fixture.retention.statusRuns, 20);
assert.equal(fixture.retention.maximumFailureLogLines, 50);
assert.equal(fixture.retention.maximumLogLineCharacters, 1000);
assert.equal(fixture.retention.maximumErrorCharacters, 4000);
assert.equal(fixture.retention.statusFailureLogLines, 3);
assert.equal(fixture.retention.statusLogLineCharacters, 240);
assert.equal(fixture.retention.statusErrorCharacters, 500);
assert.equal(fixture.retention.maximumConsoleReadBytes, 262144);
assert.equal(fixture.retention.crossProcessSerialization, "flock_history_lock_v1");
assert.deepEqual(fixture.capturePolicy.terminalFailureStates, ["failed", "license_revoked"]);
assert.equal(fixture.capturePolicy.screenshotFailureDoesNotReplaceScriptFailure, true);
assert.equal(fixture.capturePolicy.successStoresEvidence, false);
assert.equal(fixture.capturePolicy.cancelledStoresEvidence, false);

const expectedHistoryFields = ["schema", "run_id", "runtime", "bundle_path", "entry_path", "state", "started_at_ms", "ended_at_ms", "duration_ms", "error", "play_settings", "failure_evidence", "record_path"];
const expectedEvidenceFields = ["schema", "run_id", "captured_at_ms", "error", "log_tail", "log_tail_truncated", "console_log_path", "screenshot_path", "screenshot_captured", "screenshot_error", "metadata_path"];
assert.deepEqual(fixture.historyFields, expectedHistoryFields);
assert.deepEqual(fixture.evidenceFields, expectedEvidenceFields);

const [sharedHeader, sharedImpl, rootMakefile, trollMakefile, rootPlayer, rootTask, rootServer, rootCore,
  trollServer, trollUI, scriptsUI, webSdk, webIde, smoke, rootSmoke, deviceTest, doc, rootWorkflow,
  trollWorkflow, trollStatus, plan] = await Promise.all([
  read("shared/TLinkRunHistory.h"), read("shared/TLinkRunHistory.mm"), read("pccontrol/Makefile"),
  read("stream-app/streamd/Makefile"), read("pccontrol/ScriptPlayer.xm"), read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"), read("pccontrol/jsruntime/TLinkJSRuntimeCore.mm"),
  read("stream-app/streamd/POCSocketServer.mm"), read("stream-app/app/ScriptLogViewController.mm"),
  read("stream-app/app/ScriptsViewController.mm"), read("webtango/src/services/tlinkautoSdk.ts"),
  read("webtango/src/ide/AutomationIdeApp.tsx"), read("stream-app/app/CompatibilityExamples/10 Failure Evidence.js"),
  read("layout/var/mobile/Library/TLinkauto/scripts/examples/Failure Evidence Smoke.tl/main.js"),
  read("scripts/Test-TLinkRunHistoryV1.ps1"), read("docs/run-history-failure-evidence-v1.md"),
  read(".github/workflows/build.yml"), read(".github/workflows/stream-app.yml"),
  read("docs/trollstore-runtime-status.md"), read("plan.md"),
]);

assert.match(sharedHeader, /TLinkRunHistoryBegin/);
assert.match(sharedHeader, /TLinkRunHistoryFinish/);
assert.match(sharedHeader, /TLinkRunHistorySnapshot/);
assert.match(sharedImpl, /@"run_history_v1"/);
assert.match(sharedImpl, /@"failure_evidence_v1"/);
assert.match(sharedImpl, /kTLinkRunHistoryMaxRecords = 50/);
assert.match(sharedImpl, /kTLinkFailureLogTailMaxLines = 50/);
assert.match(sharedImpl, /kTLinkFailureLogLineMaxCharacters = 1000/);
assert.match(sharedImpl, /kTLinkFailureErrorMaxCharacters = 4000/);
assert.match(sharedImpl, /kTLinkStatusLogTailMaxLines = 3/);
assert.match(sharedImpl, /kTLinkStatusLogLineMaxCharacters = 240/);
assert.match(sharedImpl, /kTLinkStatusErrorMaxCharacters = 500/);
assert.match(sharedImpl, /kTLinkFailureConsoleLogMaxBytes = 256 \* 1024/);
assert.match(sharedImpl, /while \(runs\.count > kTLinkRunHistoryMaxRecords\)/);
assert.match(sharedImpl, /TLinkRunHistoryRemoveArtifact\(evidence\[@"screenshot_path"\]\)/);
assert.match(sharedImpl, /BOOL failed = \[terminalState isEqualToString:@"failed"\] \|\| \[terminalState isEqualToString:@"license_revoked"\]/);
assert.match(sharedImpl, /BOOL screenshotPresent = \[screenshotAttributes fileSize\] > 0/);
assert.match(sharedImpl, /screenshotPresent \? screenshotPath : @""/);
assert.match(sharedImpl, /screenshotPresent \? @"" : \(screenshotError \?: @"not_captured"\)/);
assert.match(sharedImpl, /chmod\(screenshotPath\.fileSystemRepresentation, 0640\)/);
assert.match(sharedImpl, /TLinkRunHistoryRedactText/);
assert.match(sharedImpl, /flock\(fd, LOCK_EX\)/);
assert.match(sharedImpl, /TLinkRunHistoryReleaseFileLock\(lockFd\)/);
assert.match(sharedImpl, /Bearer \[REDACTED\]/);
assert.match(sharedImpl, /status_log_tail_truncated/);
assert.match(sharedImpl, /status_error_truncated/);
assert.match(rootMakefile, /\.\.\/shared\/TLinkRunHistory\.mm/);
assert.match(trollMakefile, /\.\.\/\.\.\/shared\/TLinkRunHistory\.mm/);

assert.match(rootPlayer, /TLinkRunHistoryBegin\(@"rootfull"/);
assert.match(rootPlayer, /TLinkRunHistoryFinish\(runId/);
assert.match(rootPlayer, /\[Screen screenShotToPath:screenshotPath region:CGRectZero error:&captureError\]/);
assert.match(rootPlayer, /currentConsoleLogPath/);
assert.match(rootPlayer, /beginRunHistoryIfNeeded:entryFilePath/);
assert.match(rootPlayer, /finishRunHistoryWithState:@"license_revoked" error:getLastScriptError\(\)/);
assert.match(rootCore, /_consoleLogPath = \[dir stringByAppendingPathComponent/);
assert.doesNotMatch(rootCore, /_consoleLogPath = nil;/);
assert.match(rootTask, /@"run_history": TLinkRunHistorySnapshot\(20\)/);

assert.match(trollServer, /TLinkRunHistoryBegin\(@"trollstore"/);
assert.match(trollServer, /TLinkRunHistoryFinish\(runId/);
assert.match(trollServer, /CaptureOutcome \*outcome = TLinkRunCaptureOnMain\(\)/);
assert.match(trollServer, /@"run_history": TLinkRunHistorySnapshot\(20\)/);
assert.match(trollUI, /history: %@ runs \(%@ failed\)/);
assert.match(trollUI, /evidence: screenshot=%@ metadata=%@/);
assert.match(trollUI, /evidence\[@"log_tail"\]/);
assert.match(scriptsUI, /10 Failure Evidence\.tl/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 missing ${marker}`);
  assert.ok(doc.includes(marker), `documentation missing ${marker}`);
}

assert.match(webSdk, /async getRunHistory\(\): Promise<RunHistorySnapshot>/);
assert.match(webSdk, /history\.schema !== 'run_history_v1'/);
assert.match(webSdk, /export type FailureEvidence/);
assert.match(webSdk, /export type RunHistoryRecord/);
assert.match(webSdk, /export type RunHistorySnapshot/);
assert.match(webIde, /device\.getRunHistory/);
for (const source of [smoke, rootSmoke]) {
  assert.match(source, /compat\/failure-evidence start/);
  assert.match(source, /intentional_failure_evidence_smoke_v1/);
}
assert.match(deviceTest, /failure_evidence_v1/);
assert.match(deviceTest, /screenshot_captured/);
assert.match(deviceTest, /screenshot_error/);
assert.match(deviceTest, /10 Failure Evidence\.tl/);
assert.match(doc, /Screenshot failure never replaces the original script failure/i);
assert.match(rootWorkflow, /node scripts\/check-run-history-v1\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-run-history-v1\.mjs/);
assert.match(trollStatus, /Run History & Failure Evidence v1/);
assert.match(plan, /Run History & Failure Evidence v1/);

console.log("Run History v1 OK: shared persistence, bounded retention, failure evidence, task60/UI/WebTango parity");
