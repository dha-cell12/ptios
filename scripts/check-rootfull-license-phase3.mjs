import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const policy = JSON.parse(await read("license-rootfull-policy.json"));
const policySource = await read("shared/TLinkRootfullLicensePolicy.mm");
const policyHeader = await read("shared/TLinkRootfullLicensePolicy.h");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const task = await read("pccontrol/Task.xm");
const daemonMakefile = await read("tlinkauto-binary/Makefile");
const tweakMakefile = await read("pccontrol/Makefile");
const buildPlist = await read("RootfullLicenseBuild.plist");
const workflow = await read(".github/workflows/build.yml");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase3.ps1");
const playCell = await read("TLinkauto/TLinkauto/ScriptListTableCell.m");

assert.ok(integration.phase >= 3);
assert.ok([
  "task_server_and_springboard_feature_gate",
  "task_and_long_running_component_gate"
].includes(integration.integration_mode));
assert.equal(integration.runtime_gate_active, true);
assert.equal(integration.task_policy.daemon_gate, true);
assert.equal(integration.task_policy.springboard_gate, true);
assert.equal(integration.task_policy.missing_policy, "fail_closed");
assert.equal(integration.task_policy.task10_deny, "silent_drop_with_counter");
assert.ok(policy.phase >= 3);
assert.ok([
  "task_server_and_springboard_feature_gate",
  "task_and_long_running_component_gate"
].includes(policy.enforcement_behavior));

const expected = new Map();
for (const [feature, tasks] of Object.entries(policy.task_features)) {
  for (const taskId of tasks) expected.set(Number(taskId), feature);
}
for (const [taskId, feature] of Object.entries(policy.special_tasks)) {
  expected.set(Number(taskId), feature);
}

const actual = new Map();
for (const match of policySource.matchAll(/\{\s*(\d+)\s*,\s*"([^"]+)"\s*\}/g)) {
  const taskId = Number(match[1]);
  assert.ok(!actual.has(taskId), `duplicate C task policy ${taskId}`);
  actual.set(taskId, match[2]);
}
assert.deepEqual(
  [...actual.entries()].sort((a, b) => a[0] - b[0]),
  [...expected.entries()].sort((a, b) => a[0] - b[0]),
  "rootfull C task policy differs from license-rootfull-policy.json"
);

const exemptSection = policySource.slice(
  policySource.indexOf("BOOL TLinkRootfullLicenseTaskIsExempt"),
  policySource.indexOf("NSString *TLinkRootfullLicenseFeatureForTask")
);
const actualExempt = [...exemptSection.matchAll(/taskType\s*==\s*(\d+)/g)]
  .map((match) => Number(match[1]))
  .sort((a, b) => a - b);
assert.deepEqual(actualExempt, [...policy.exempt_tasks].sort((a, b) => a - b));

for (const evidence of [
  "TLinkRootfullLicenseTaskAllowed",
  "TLinkRootfullLicenseComponentAllowed",
  "license_policy_missing task=",
  "license_required %@ feature=%@ state=%@ error=%@"
]) {
  assert.ok(policySource.includes(evidence), `shared policy lacks ${evidence}`);
}
assert.match(policyHeader, /TLinkRootfullLicenseTaskAllowed/);

assert.match(socket, /TLinkRootfullLicenseTaskAllowed\(taskType/);
assert.match(socket, /TLinkRootfullLicenseComponentAllowed\(@"automation",\s*@"home_command"/);
assert.match(socket, /sTLinkRootfullLicenseTask10DropCount\.fetch_add/);
assert.match(socket, /zx_rootfullPhase[34]DiagnosticResponse/);
assert.match(socket, /rootfull_license_phase"\]\s*=\s*@[34]/);
assert.match(socket, /runtime_gate_active"\]\s*=\s*@1/);
assert.match(socket, /task_server_and_springboard_feature_gate|task_and_long_running_component_gate/);
const daemonGateIndex = socket.indexOf("BOOL licenseAllowed = homeCommand");
const daemonDiagnosticIndex = socket.indexOf("NSData *phase4Diagnostic");
assert.ok(
  daemonGateIndex >= 0 &&
    daemonDiagnosticIndex >= 0 &&
    daemonGateIndex < daemonDiagnosticIndex,
  "daemon gate must run before dispatch"
);

assert.match(task, /TLinkRootfullLicenseTaskAllowed\(taskType/);
assert.match(task, /sTLinkSpringBoardLicenseTask10DropCount\.fetch_add/);
assert.match(task, /licenseStatus\[@"phase"\]\s*=\s*@[34]/);
assert.match(task, /licenseStatus\[@"runtime_gate_active"\]\s*=\s*@1/);
assert.ok(
  task.indexOf("TLinkRootfullLicenseTaskAllowed(taskType") <
    task.indexOf("if (taskType == TASK_PERFORM_TOUCH)"),
  "SpringBoard gate must run before task dispatch"
);

for (const makefile of [daemonMakefile, tweakMakefile]) {
  assert.match(makefile, /TLinkRootfullLicensePolicy\.mm/);
}
assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>[34]<\/integer>/);
assert.match(buildPlist, /task_server_and_springboard_feature_gate|task_and_long_running_component_gate/);
assert.match(workflow, /check-rootfull-license-phase3\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase[34]-artifact\.mjs/);
assert.match(deviceProbe, /ExpectedAccess/);
assert.match(deviceProbe, /license_required task=/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "76reload"/);
assert.match(deviceProbe, /license_policy_missing task=74/);
assert.match(playCell, /TLinkLicenseFeatureAllowed\(@"script"/);
assert.match(playCell, /License Required/);

console.log(
  `rootfull license phase 3 OK: ${actual.size} task gates, ` +
  `${actualExempt.length} exempt diagnostics, daemon + SpringBoard fail-closed policy`
);
