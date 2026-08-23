import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/event-channel-v1.json"));

assert.equal(fixture.phase, 1);
assert.equal(fixture.state, "implemented");
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.task, 95);
assert.equal(fixture.schema, "event_channel_v1");
assert.equal(fixture.eventSchema, "tlink_event_v1");
assert.equal(fixture.transport, "task95_long_poll_v1");
assert.equal(fixture.limits.journalMaxEvents, 256);
assert.equal(fixture.limits.pollMaxEvents, 32);
assert.equal(fixture.limits.pollTimeoutMaxMs, 25000);
assert.equal(fixture.limits.payloadMaxBytes, 4096);
assert.equal(fixture.limits.maxConcurrentPollsPerRuntime, 8);

const [header, implementation, rootMakefile, daemonMakefile, trollMakefile, rootPolicy,
  licensePolicy, rootLicensePolicy, rootServer, rootTask, trollServer, runHistory, webClient, webSdk,
  webIde, deviceTest, doc, rootWorkflow, trollWorkflow, plan, trollStatus] = await Promise.all([
  read("shared/TLinkEventChannel.h"), read("shared/TLinkEventChannel.mm"), read("pccontrol/Makefile"),
  read("tlinkauto-binary/Makefile"), read("stream-app/streamd/Makefile"),
  read("shared/TLinkRootfullLicensePolicy.mm"), read("license-task-policy.json"),
  read("license-rootfull-policy.json"),
  read("tlinkauto-binary/SocketServer.mm"), read("pccontrol/Task.xm"),
  read("stream-app/streamd/POCSocketServer.mm"), read("shared/TLinkRunHistory.mm"),
  read("webtango/src/TLinkautoWsClient.ts"), read("webtango/src/services/tlinkautoSdk.ts"),
  read("webtango/src/ide/AutomationIdeApp.tsx"), read("scripts/Test-TLinkEventChannelV1.ps1"),
  read("docs/event-channel-v1.md"), read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"), read("plan.md"), read("docs/trollstore-runtime-status.md"),
]);

assert.match(header, /TLinkEventChannelPublish/);
assert.match(header, /TLinkEventChannelPollBody/);
assert.match(implementation, /@"event_channel_v1"/);
assert.match(implementation, /@"tlink_event_v1"/);
assert.match(implementation, /kTLinkEventJournalMaxEvents = 256/);
assert.match(implementation, /kTLinkEventPollMaxEvents = 32/);
assert.match(implementation, /kTLinkEventPollMaxTimeoutMs = 25000/);
assert.match(implementation, /kTLinkEventPayloadMaxBytes = 4096/);
assert.match(implementation, /kTLinkEventMaxConcurrentPolls = 8/);
assert.match(implementation, /flock\(fd, LOCK_EX\)/);
assert.match(implementation, /@"gap": @\(gap\)/);
assert.match(implementation, /@"timed_out": @\(timedOut\)/);
assert.match(implementation, /sequence > nextCursor && TLinkEventTopicMatches/);
assert.match(implementation, /event_poll_capacity_reached/);
assert.match(implementation, /@"next_cursor": @\(cursor\)/);
assert.match(implementation, /event_request_invalid/);
assert.match(implementation, /event_topic_invalid/);

for (const makefile of [rootMakefile, daemonMakefile, trollMakefile]) {
  assert.match(makefile, /TLinkEventChannel\.mm/);
}
assert.match(rootPolicy, /\{95, "automation"\}/);
assert.ok(JSON.parse(licensePolicy).task_features.automation.includes(95));
assert.ok(!JSON.parse(licensePolicy).exempt_tasks.includes(95));
assert.ok(JSON.parse(rootLicensePolicy).task_features.automation.includes(95));
assert.ok(!JSON.parse(rootLicensePolicy).exempt_tasks.includes(95));
assert.match(rootServer, /zx_deferLegacyEventPoll/);
assert.match(rootServer, /zx_deferJSONEventPoll/);
assert.match(rootServer, /eventPollPending/);
assert.match(rootServer, /TLinkRootfullLicenseTaskAllowed\(95/);
assert.match(rootServer, /ctx\.writeStream = NULL/);
assert.match(rootServer, /taskType == 95/);
assert.match(trollServer, /POCDeferEventPoll/);
assert.match(trollServer, /eventPollPending/);
assert.match(trollServer, /TLinkLicenseFeatureAllowed\(@"automation"/);
assert.match(trollServer, /ctx\.writeStream = NULL/);
assert.match(trollServer, /taskType == 95/);
assert.match(trollServer, /POCTaskTypeFromBuffer\(line\) == 95/);
assert.match(trollServer, /90,91,94,95,96/);
assert.match(rootTask, /@"event_channel": TLinkEventChannelStatus\(\)/);
assert.match(trollServer, /@"event_channel": TLinkEventChannelStatus\(\)/);
assert.match(runHistory, /TLinkEventChannelPublish\(runtime/);
assert.match(runHistory, /@"script\.run"/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 missing ${marker}`);
  assert.ok(doc.includes(marker), `documentation missing ${marker}`);
}

assert.match(webClient, /suppressKeepalive\(timeoutMs \+ 1000\)/);
assert.match(webSdk, /async pollEvents\(/);
assert.match(webSdk, /subscribeEvents\(/);
assert.match(webSdk, /new TLinkautoWsClient\(this\.eventUrl\)/);
assert.match(webSdk, /retryMs = Math\.min\(5000, retryMs \* 2\)/);
assert.match(webSdk, /activeEventClient\.close\(\)/);
assert.match(webSdk, /batch\.schema !== 'event_channel_v1'/);
assert.match(webSdk, /batch\.state === 'error'/);
assert.match(webSdk, /event topic must be/);
assert.match(webIde, /device\.subscribeEvents/);
assert.match(deviceTest, /95\$CursorValue;;25000;;8;;script\.run/);
assert.match(deviceTest, /cursor did not advance/);
assert.match(doc, /at-least-once/i);
assert.match(rootWorkflow, /node scripts\/check-event-channel-v1\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-event-channel-v1\.mjs/);
assert.match(plan, /Event Channel/i);
assert.match(trollStatus, /Event Channel/i);

console.log("Event Channel v1 OK: deferred long-poll, cursor resume, bounded journal, rootfull/TrollStore/WebTango parity");
