import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");
const fixture = JSON.parse(await read("test/fixtures/adaptive-streaming-v1.json"));

assert.equal(fixture.state, "implemented");
assert.equal(fixture.feedbackTask, 94);
assert.deepEqual(fixture.levels, ["high", "balanced", "survival"]);
assert.equal(fixture.limits.encoderRestartsPerSession, 3);
assert.equal(fixture.limits.clientReconnectAttempts, 6);
assert.equal(fixture.limits.feedbackMinimumIntervalMs, 750);

const [header, core, rootH264, trollH264, rootServer, trollServer, rootTask,
  rootPolicy, trollPolicy, worker, grid, controller, ide, doc, deviceTest,
  streamService, rootMakefile, daemonMakefile, trollMakefile, rootWorkflow, trollWorkflow] = await Promise.all([
  read("shared/TLinkAdaptiveStreaming.h"), read("shared/TLinkAdaptiveStreaming.mm"),
  read("pccontrol/H264Stream.xm"), read("stream-app/streamd/H264Stream.mm"),
  read("tlinkauto-binary/SocketServer.mm"), read("stream-app/streamd/POCSocketServer.mm"),
  read("pccontrol/Task.xm"), read("license-rootfull-policy.json"), read("license-task-policy.json"),
  read("webtango/src/IosH264Worker.ts"), read("webtango/src/services/ios/IosGridStreams.ts"),
  read("webtango/src/services/ios/IosStreamController.ts"), read("webtango/src/ide/IdeScreenPanel.tsx"),
  read("docs/adaptive-streaming-self-healing-v1.md"), read("scripts/Test-TLinkAdaptiveStreamingV1.ps1"),
  read("webtango/src/services/ios/IosStreamService.ts"),
  read("pccontrol/Makefile"), read("tlinkauto-binary/Makefile"), read("stream-app/streamd/Makefile"),
  read(".github/workflows/build.yml"), read(".github/workflows/stream-app.yml"),
]);

assert.match(header, /TLinkAdaptiveStreamingSubmitFeedback/);
assert.match(core, /@"adaptive_streaming_v1"/);
assert.match(core, /kTLinkAdaptiveFeedbackFreshMs = 5000/);
assert.match(core, /kTLinkAdaptiveFeedbackMinimumIntervalMs = 750/);
assert.match(core, /kTLinkAdaptiveChangeCooldownMs = 5000/);
assert.match(core, /kTLinkAdaptiveRecoveryGoodSamples = 4/);
assert.match(core, /feedback_stale_fail_safe/);
assert.match(core, /adaptive_feedback_schema_invalid/);
assert.match(core, /shouldPersist = newSample \|\| changed/);
assert.match(core, /@"stream\.health"/);
assert.ok(JSON.parse(rootPolicy).task_features.stream.includes(94));
assert.ok(JSON.parse(trollPolicy).task_features.stream.includes(94));
for (const makefile of [rootMakefile, daemonMakefile, trollMakefile]) {
  assert.match(makefile, /TLinkAdaptiveStreaming\.mm/);
}
for (const h264 of [rootH264, trollH264]) {
  assert.match(h264, /TLinkAdaptiveStreamingDecision/);
  assert.match(h264, /encoderRecoveryCount < 3/);
  assert.match(h264, /Invalidation drains encoder callbacks/);
  assert.match(h264, /TLinkAdaptiveStreamingSessionEnded/);
}
assert.match(rootServer, /taskType == 94/);
assert.doesNotMatch(rootServer.slice(rootServer.indexOf("static bool shouldRouteToSpringBoard"), rootServer.indexOf("static bool shouldWaitForResponse")), /case 94/);
assert.match(trollServer, /taskType == 94/);
assert.match(trollServer, /\{94, "stream"\}/);
assert.match(rootTask, /@"adaptive_streaming": TLinkH264AdaptiveStreamingStatus/);
assert.match(trollServer, /@"adaptive_streaming": TLinkH264AdaptiveStreamingStatus/);
assert.match(worker, /MAX_RECONNECT_ATTEMPTS = 6/);
assert.match(worker, /performance\.now\(\) - lastFrameAt < 3000/);
assert.match(worker, /94\$\{payload\}/);
assert.match(worker, /scheduleReconnect\('decoder_error'\)/);
for (const client of [grid, controller, ide]) {
  assert.match(client, /feedbackUrl/);
  assert.match(client, /port: 7004/);
}
assert.match(streamService, /this\.activeStart\.profile === 'worker' \? 7004 : 7003/);
assert.match(streamService, /scheduleReconnect\('raw_socket_closed'\)/);
for (const marker of [
  "adaptiveStreamingState=implemented", "adaptiveStreamingVersion=1",
  "adaptiveStreamingSchema=adaptive_streaming_v1", "adaptiveStreamingFeedback=task94_base64_json_v1",
  "adaptiveStreamingLevels=high,balanced,survival",
  "adaptiveStreamingSelfHealing=encoder_restart_3_client_reconnect_6",
  "adaptiveStreamingDeviceValidated=0",
]) {
  assert.ok(rootServer.includes(marker), `rootfull missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore missing ${marker}`);
  assert.ok(doc.includes(marker), `documentation missing ${marker}`);
}
assert.match(deviceTest, /RunFeedbackSmoke/);
assert.match(rootWorkflow, /check-adaptive-streaming-v1\.mjs/);
assert.match(trollWorkflow, /check-adaptive-streaming-v1\.mjs/);

console.log("Adaptive Streaming v1 OK: bounded feedback, hysteresis, thermal ceiling, encoder recovery and WebTango reconnect");
