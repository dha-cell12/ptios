import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const policy = JSON.parse(await readFile(resolve(root, "license-task-policy.json"), "utf8"));
const serverPath = resolve(root, "stream-app/streamd/POCSocketServer.mm");
const server = await readFile(serverPath, "utf8");

assert.equal(policy.license_contract_version, 1, "license contract version must remain 1");
assert.deepEqual(
  [...policy.features].sort(),
  ["admin", "automation", "script", "shell", "stream"],
  "feature allowlist changed without updating the contract",
);

function section(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.ok(start >= 0 && end > start, `missing source section: ${startMarker}`);
  return source.slice(start, end);
}

function sorted(values) {
  return [...values].map(Number).sort((a, b) => a - b);
}

const exemptSource = section(server, "static BOOL TLinkLicenseTaskIsExempt", "static NSString *TLinkLicenseFeatureForTask");
const actualExempt = [...exemptSource.matchAll(/taskType\s*==\s*(\d+)/g)].map((match) => Number(match[1]));
assert.deepEqual(sorted(actualExempt), sorted(policy.exempt_tasks), "exempt task inventory differs from backend");

const featureSource = section(server, "static NSString *TLinkLicenseFeatureForTask", "static NSData *TLinkLicenseDeniedResponse");
const policyTableSource = section(server, "static const TLinkLicenseTaskPolicyEntry kTLinkLicenseTaskPolicy[]", "static NSString *TLinkLicenseFeatureForTask");
const actualFeatureByTask = new Map();
for (const match of policyTableSource.matchAll(/\{\s*(\d+)\s*,\s*\"([^\"]+)\"\s*\}/g)) {
  const task = Number(match[1]);
  const feature = match[2];
  assert.ok(policy.features.includes(feature), `unknown backend feature: ${feature}`);
  assert.ok(!actualFeatureByTask.has(task), `duplicate backend task policy: ${task}`);
  actualFeatureByTask.set(task, feature);
}
assert.ok(featureSource.includes("kTLinkLicenseTaskPolicy"), "task lookup no longer uses the explicit policy table");

const expectedFeatureByTask = new Map();
for (const [feature, tasks] of Object.entries(policy.task_features)) {
  assert.ok(policy.features.includes(feature), `unknown inventory feature: ${feature}`);
  for (const task of tasks) {
    assert.ok(!expectedFeatureByTask.has(task), `duplicate inventory task policy: ${task}`);
    expectedFeatureByTask.set(Number(task), feature);
  }
}
assert.deepEqual(
  [...actualFeatureByTask.entries()].sort((a, b) => a[0] - b[0]),
  [...expectedFeatureByTask.entries()].sort((a, b) => a[0] - b[0]),
  "task-feature inventory differs from TLinkLicenseFeatureForTask",
);

for (const task of [31, 72, 74]) {
  assert.equal(actualFeatureByTask.get(task), "admin", `admin task ${task} escaped the admin feature`);
}
for (const task of [13, 71]) {
  assert.equal(actualFeatureByTask.get(task), "shell", `shell task ${task} escaped the shell feature`);
}
assert.ok(
  !policy.task_features.automation.some((task) => [13, 31, 71, 72, 74].includes(Number(task))),
  "automation feature must not grant shell or admin tasks",
);

const dispatchSource = section(server, "static NSData *TLinkHandleTaskLine", "// Handle one complete line");
const dispatched = new Set([...dispatchSource.matchAll(/taskType\s*==\s*(\d+)/g)].map((match) => Number(match[1])));
for (const match of dispatchSource.matchAll(/taskType\s*>=\s*(\d+)\s*&&\s*taskType\s*<=\s*(\d+)/g)) {
  for (let task = Number(match[1]); task <= Number(match[2]); task++) dispatched.add(task);
}
for (const task of Object.keys(policy.special_tasks)) dispatched.add(Number(task));

const covered = new Set([
  ...policy.exempt_tasks.map(Number),
  ...expectedFeatureByTask.keys(),
  ...Object.keys(policy.special_tasks).map(Number),
]);
assert.deepEqual(sorted(dispatched), sorted(covered), "a dispatched task is missing from the license policy inventory");

for (const [task, feature] of Object.entries(policy.special_tasks)) {
  assert.ok(policy.features.includes(feature), `unknown special task feature: ${feature}`);
  const evidence = `taskType == ${task}`;
  assert.ok(server.includes(evidence), `special task ${task} is not dispatched`);
  assert.ok(server.includes(`TLinkLicenseFeatureAllowed(@\"${feature}\"`), `special task ${task} lacks its gate`);
}

for (const component of policy.components) {
  assert.ok(policy.features.includes(component.feature), `unknown component feature: ${component.feature}`);
  const source = await readFile(resolve(root, component.source), "utf8");
  assert.ok(source.includes(component.evidence), `component policy evidence missing: ${component.component}`);
}

assert.ok(server.includes("sTLinkLicenseDropCount++"), "legacy task 10 lacks deny diagnostics");
assert.ok(server.includes("TLinkStartScriptLicenseHeartbeat"), "script runtime lacks license heartbeat");

console.log(`license task policy OK: ${covered.size} tasks, ${policy.components.length} component gates, contract v${policy.license_contract_version}`);
