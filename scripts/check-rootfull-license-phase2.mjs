import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const manager = await read("stream-app/app/LicenseManager.mm");
const lifecycle = await read("stream-app/app/LicenseLifecycleCoordinator.mm");
const licenseView = await read("stream-app/app/LicenseViewController.mm");
const appDelegate = await read("TLinkauto/TLinkauto/AppDelegate.m");
const settings = await read("TLinkauto/TLinkauto/Settings/SettingsPageViewController.m");
const project = await read("TLinkauto/TLinkauto.xcodeproj/project.pbxproj");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const task = await read("pccontrol/Task.xm");
const workflow = await read(".github/workflows/build.yml");
const buildPlist = await read("RootfullLicenseBuild.plist");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase2.ps1");
const testLicenseCreator = await read("scripts/New-TLinkRootfullTestLicense.ps1");
const phase2Docs = await read("docs/license-rootfull-phase2.md");
const appSocket = await read("TLinkauto/TLinkauto/Socket.m");
const playCell = await read("TLinkauto/TLinkauto/ScriptListTableCell.m");
const settingsController = await read("TLinkauto/TLinkauto/Settings/SettingsPageViewController.m");
const configManager = await read("TLinkauto/TLinkauto/ConfigManager.m");
const appConfig = await read("TLinkauto/TLinkauto/Config.h");
const jsRuntime = await read("pccontrol/TLinkautoJSRuntime.mm");

assert.equal(integration.product, "tlinkauto-rootfull");
assert.equal(integration.phase, 2);
assert.equal(integration.license_contract_version, 1);
assert.equal(integration.integration_mode, "activation_lifecycle_observe_no_runtime_gate");
assert.equal(integration.runtime_gate_active, false);
assert.equal(integration.activation_ui_phase, 2);
assert.equal(integration.activation_ui_active, true);
assert.equal(integration.daemon_cache_sync_task, 76);
assert.equal(integration.next_runtime_gate_phase, 3);
assert.equal(integration.automatic_refresh.single_flight, true);
assert.equal(integration.automatic_refresh.backoff_with_jitter, true);
assert.ok(integration.verifier_components.some(({ component }) => component === "application_lifecycle"));
assert.ok(integration.verifier_components.some(({ component }) => component === "application_license_ui"));

for (const evidence of [
  "/v1/challenge",
  "/v1/activate",
  "/v1/refresh",
  "/v1/deactivate",
  "SecKeyCreateSignature",
  "TLinkLicenseAdvanceGeneration"
]) {
  assert.ok(manager.includes(evidence), `LicenseManager lacks ${evidence}`);
}

for (const evidence of [
  "TLINK_LICENSE_ROOTFULL_RUNTIME",
  "76reload",
  "requestInFlight",
  "pendingRefreshCompletions",
  "kTLinkLicenseRefreshWindow",
  "kTLinkLicenseBackoffMaximum",
  "handleApplicationLaunch",
  "handleApplicationDidBecomeActive",
  "publishLicenseChange"
]) {
  assert.ok(lifecycle.includes(evidence), `LicenseLifecycleCoordinator lacks ${evidence}`);
}
assert.doesNotMatch(lifecycle, /TLinkLicenseFeatureAllowed\s*\(/);

for (const evidence of [
  "Activate",
  "Refresh Lease",
  "Deactivate This Device",
  "Repair Device Binding",
  "Remove Local Lease (Recovery)"
]) {
  assert.ok(licenseView.includes(evidence), `License UI lacks ${evidence}`);
}

assert.match(appDelegate, /handleApplicationLaunch/);
assert.match(appDelegate, /applicationDidBecomeActive/);
assert.match(settings, /SCLicenseViewController/);
assert.match(settings, /Activation and device binding/);

for (const source of [
  "LicenseManager.mm in Sources",
  "LicenseLifecycleCoordinator.mm in Sources",
  "LicenseViewController.mm in Sources",
  "TLinkLicenseVerifier.mm in Sources",
  "TLinkRootfullLicenseBuild.mm in Sources",
  "Security.framework in Frameworks",
  "LicenseConfig.plist in Resources"
]) {
  assert.ok(project.includes(source), `Xcode project lacks ${source}`);
}

assert.match(socket, /zx_rootfullPhase2DiagnosticResponse/);
assert.match(socket, /rootfull_license_phase"\]\s*=\s*@2/);
assert.match(socket, /activation_lifecycle_active"\]\s*=\s*@1/);
assert.match(socket, /license_phase=2/);
assert.match(socket, /runtimeGate=0/);
assert.doesNotMatch(socket, /TLinkLicenseFeatureAllowed\s*\(/);

assert.match(task, /licenseStatus\[@"phase"\]\s*=\s*@2/);
assert.match(task, /licenseStatus\[@"activation_lifecycle_active"\]\s*=\s*@1/);
assert.match(task, /licenseStatus\[@"runtime_gate_active"\]\s*=\s*@0/);
assert.doesNotMatch(task, /TLinkLicenseFeatureAllowed\s*\(/);

assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>2<\/integer>/);
assert.match(buildPlist, /activation_lifecycle_observe_no_runtime_gate/);
assert.match(workflow, /check-rootfull-license-phase2\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase2-artifact\.mjs/);
assert.match(workflow, /TLINK_LICENSE_ROOTFULL_RUNTIME=1/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "97"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "75"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "60"/);
assert.match(deviceProbe, /Invoke-TLinkTask -Task "76reload"/);
assert.match(deviceProbe, /Phase 2 unexpectedly enabled the runtime gate/);

assert.match(testLicenseCreator, /NewGuid\(\)/);
assert.match(testLicenseCreator, /\/v1\/admin\/licenses/);
assert.match(testLicenseCreator, /SecureStringToBSTR/);
assert.match(testLicenseCreator, /TLINK-ROOTFULL-TEST-/);
assert.match(phase2Docs, /New-TLinkRootfullTestLicense\.ps1/);
assert.match(phase2Docs, /Switch App Before Playing/);

assert.match(appSocket, /SO_RCVTIMEO/);
assert.match(appSocket, /SO_SNDTIMEO/);
assert.match(playCell, /19%@\\r\\n/);
assert.doesNotMatch(playCell, /springBoardSocket recv/);
assert.match(settingsController, /notifySpringBoardConfigurationChanged/);
assert.match(settingsController, /enableJSHelperExecution/);
assert.match(settingsController, /handleJSHelperExecution/);
assert.match(settingsController, /javascript_helper_runtime_enabled/);
assert.match(settingsController, /scriptRuntimeSettingsHint/);
assert.match(configManager, /withIntermediateDirectories:YES/);
assert.match(appConfig, /RUNTIME_CONFIG_PATH/);
assert.match(jsRuntime, /enable_js_helper_execution/);

for (const token of [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY"
]) {
  for (const [name, content] of [
    ["LicenseManager.mm", manager],
    ["LicenseLifecycleCoordinator.mm", lifecycle],
    ["build.yml", workflow]
  ]) {
    assert.ok(!content.includes(token), `${name} contains forbidden secret marker ${token}`);
  }
}

console.log(
  "rootfull license phase 2 OK: activation UI, signed lifecycle, automatic refresh, " +
  "daemon generation sync, runtime gate disabled"
);
