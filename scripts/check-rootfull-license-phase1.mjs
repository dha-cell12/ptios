import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const verifier = await read("shared/TLinkLicenseVerifier.mm");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const task = await read("pccontrol/Task.xm");
const daemonMakefile = await read("tlinkauto-binary/Makefile");
const tweakMakefile = await read("pccontrol/Makefile");
const workflow = await read(".github/workflows/build.yml");
const buildPlist = await read("RootfullLicenseBuild.plist");
const licenseConfig = await read("TLinkauto/TLinkauto/LicenseConfig.plist");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase1.ps1");

assert.equal(integration.product, "tlinkauto-rootfull");
assert.equal(integration.runtime, "rootfull");
assert.ok(integration.phase >= 1);
assert.equal(integration.license_contract_version, 1);
assert.ok([
  "shared_verifier_observe_no_runtime_gate",
  "activation_lifecycle_observe_no_runtime_gate",
  "task_server_and_springboard_feature_gate"
].includes(integration.integration_mode));
assert.equal(integration.runtime_gate_active, integration.phase >= 3);
assert.equal(integration.activation_ui_phase, 2);
assert.ok(integration.verifier_components.length >= 3);

assert.match(verifier, /com\.tlinkauto\.tlinkauto/);
assert.match(verifier, /com\.tlinkauto\.streamcontrol/);
assert.match(verifier, /TLINK_LICENSE_ROOTFULL_RUNTIME/);
assert.match(verifier, /TLinkApplicationBundleIdentifiers/);
assert.match(verifier, /\/Applications\/TLinkauto\.app/);

for (const makefile of [daemonMakefile, tweakMakefile]) {
  assert.match(makefile, /TLinkLicenseVerifier\.mm/);
  assert.match(makefile, /TLINK_LICENSE_ROOTFULL_RUNTIME=1/);
  assert.match(makefile, /Security/);
}

assert.match(socket, /TLinkLicenseStatusDictionary/);
assert.match(socket, /TLinkLicenseAdvanceGeneration/);
assert.match(socket, /TLinkLicenseInvalidateCache/);
assert.match(socket, /rootfull_license_phase/);
assert.match(socket, /(?:observe_verifier|activation_lifecycle_observe)_no_runtime_gate|task_server_and_springboard_feature_gate/);
assert.match(socket, /license_phase=[123]/);
assert.match(socket, /runtimeGate=[01]/);
if (integration.phase < 3) assert.doesNotMatch(socket, /TLinkRootfullLicenseTaskAllowed\s*\(/);
else assert.match(socket, /TLinkRootfullLicenseTaskAllowed\s*\(/);

assert.match(task, /TLinkLicenseStatusDictionary/);
assert.match(task, /licenseStatus\[@"phase"\]\s*=\s*@[123]/);
assert.match(task, /licenseStatus\[@"runtime_gate_active"\]\s*=\s*@[01]/);
assert.match(task, /(?:observe_verifier|activation_lifecycle_observe)_no_runtime_gate|task_server_and_springboard_feature_gate/);
if (integration.phase < 3) assert.doesNotMatch(task, /TLinkRootfullLicenseTaskAllowed\s*\(/);
else assert.match(task, /TLinkRootfullLicenseTaskAllowed\s*\(/);

assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>[123]<\/integer>/);
assert.match(buildPlist, /(?:shared_verifier|activation_lifecycle)_observe_no_runtime_gate|task_server_and_springboard_feature_gate/);
for (const key of [
  "LicenseEndpoint",
  "LicenseKeyID",
  "LicensePublicKeyX",
  "LicensePublicKeyY",
  "LicenseEnforcementEnabled"
]) {
  assert.match(licenseConfig, new RegExp(`<key>${key}<\\/key>`));
}

assert.match(workflow, /check-rootfull-license-phase1\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase[123]-artifact\.mjs/);
assert.match(workflow, /TLinkauto\/TLinkauto\/LicenseConfig\.plist/);
assert.match(workflow, /TLINK_LICENSE_ENDPOINT/);
assert.match(workflow, /TLINK_LICENSE_PUBLIC_KEY_X/);
assert.match(workflow, /TLINK_LICENSE_PUBLIC_KEY_Y/);

assert.match(deviceProbe, /Invoke-TLinkTask -Task "97"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "75"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "76"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "76reload"/);
assert.match(deviceProbe, /runtime_gate_active/);
assert.match(deviceProbe, /observe_verifier_no_runtime_gate/);

for (const token of [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY"
]) {
  for (const [name, content] of [
    ["SocketServer.mm", socket],
    ["Task.xm", task],
    ["build.yml", workflow],
    ["LicenseConfig.plist", licenseConfig]
  ]) {
    assert.ok(!content.includes(token), `${name} contains forbidden secret marker ${token}`);
  }
}

console.log(
  `rootfull license phase 1 OK: ${integration.verifier_components.length} verifier components, ` +
  `diagnostics 60/75/76/97, current runtime gate ${integration.runtime_gate_active ? "active" : "disabled"}`
);
