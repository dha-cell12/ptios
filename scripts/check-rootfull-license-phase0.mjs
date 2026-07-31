import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const policy = JSON.parse(await read("license-rootfull-policy.json"));
const taskHeader = await read("pccontrol/Task.h");
const taskSource = await read("pccontrol/Task.xm");
const socketSource = await read("tlinkauto-binary/SocketServer.mm");
const tweakSource = await read("pccontrol/Tweak.xm");
const rootMakefile = await read("Makefile");
const workflow = await read(".github/workflows/build.yml");

assert.equal(policy.product, "tlinkauto-rootfull");
assert.equal(policy.runtime, "rootfull");
assert.ok(policy.phase >= 0);
assert.equal(policy.license_contract_version, 1);
assert.ok([
  "marker_only_no_runtime_gate",
  "task_server_and_springboard_feature_gate",
  "task_and_long_running_component_gate"
].includes(policy.enforcement_behavior));
assert.deepEqual(policy.features, ["automation", "stream", "script", "admin", "shell"]);
assert.deepEqual(policy.exempt_tasks, [60, 75, 76, 96, 97, 99]);

const defines = new Map();
for (const match of taskHeader.matchAll(/^#define\s+(TASK_[A-Z0-9_]+)\s+(\d+)\s*$/gm)) {
  defines.set(match[1], Number(match[2]));
}
assert.ok(defines.size > 0, "Task.h contains no task definitions");

const policyIds = [];
for (const ids of Object.values(policy.task_features)) policyIds.push(...ids);
policyIds.push(...policy.exempt_tasks);
policyIds.push(...Object.keys(policy.special_tasks).map(Number));
assert.equal(new Set(policyIds).size, policyIds.length, "rootfull policy assigns a task more than once");

const declaredIds = [...new Set(defines.values())].sort((a, b) => a - b);
const coveredIds = [...new Set(policyIds)].sort((a, b) => a - b);
assert.deepEqual(coveredIds, declaredIds, "every declared rootfull task must have exactly one policy");

const dispatchedSymbols = [...taskSource.matchAll(/taskType\s*==\s*(TASK_[A-Z0-9_]+)/g)]
  .map((match) => match[1]);
for (const symbol of dispatchedSymbols) {
  assert.ok(defines.has(symbol), `Task.xm dispatches undefined symbol ${symbol}`);
  assert.ok(coveredIds.includes(defines.get(symbol)), `Task.xm dispatch ${symbol} has no license policy`);
}

for (const id of policy.exempt_tasks.filter((value) => value !== 60)) {
  assert.match(
    socketSource,
    new RegExp(`(?:case\\s+${id}:|taskType\\s*==\\s*${id})`),
    `daemon diagnostic task ${id} is missing`
  );
}
assert.match(socketSource, /license_contract_version=1/);
assert.match(taskSource, /@"license_contract_version":\s*@1/);
assert.match(taskSource, /TLinkRootfullLicenseBuildMode/);

assert.doesNotMatch(tweakSource, /47\.114\.83\.227|internal\/version_control|NSURLConnection/);
assert.doesNotMatch(tweakSource, /\bisExpired\b|\bCHECKER\b/);

assert.match(rootMakefile, /TLINK_LICENSE_MODE \?= observe/);
assert.match(rootMakefile, /TLINK_LICENSE_FORCE_ENFORCEMENT := 1/);
assert.match(workflow, /license_mode:\s*\[observe,\s*enforced\]/);

const makefiles = [
  await read("tlinkauto-binary/Makefile"),
  await read("pccontrol/Makefile"),
  await read("tlinkauto-jsd/Makefile"),
  await read("license-authority/Makefile"),
  await read("vpn-broker/Makefile"),
  await read("appdelegate/Makefile")
];
for (const content of makefiles) {
  assert.match(content, /TLinkRootfullLicenseBuild\.mm/);
  assert.match(content, /TLINK_LICENSE_FORCE_ENFORCEMENT/);
}

const forbidden = [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY"
];
for (const [name, content] of [
  ["Task.h", taskHeader],
  ["Task.xm", taskSource],
  ["SocketServer.mm", socketSource],
  ["Tweak.xm", tweakSource],
  ["build.yml", workflow]
]) {
  for (const token of forbidden) {
    assert.ok(!content.includes(token), `${name} contains forbidden secret marker ${token}`);
  }
}

console.log(
  `rootfull license phase 0 OK: ${coveredIds.length} tasks, ` +
  `${policy.components.length} component inventory entries, contract v1`
);
