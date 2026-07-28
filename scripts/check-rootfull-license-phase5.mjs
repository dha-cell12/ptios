import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const policy = JSON.parse(await read("license-rootfull-policy.json"));
const verifierHeader = await read("shared/TLinkLicenseVerifier.h");
const verifier = await read("shared/TLinkLicenseVerifier.mm");
const lifecycleHeader = await read("stream-app/app/LicenseLifecycleCoordinator.h");
const lifecycle = await read("stream-app/app/LicenseLifecycleCoordinator.mm");
const scripts = await read("TLinkauto/TLinkauto/ScriptListViewController.m");
const scriptCell = await read("TLinkauto/TLinkauto/ScriptListTableCell.m");
const settings = await read("TLinkauto/TLinkauto/Settings/SettingsPageViewController.m");
const licenseView = await read("stream-app/app/LicenseViewController.mm");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const task = await read("pccontrol/Task.xm");
const buildPlist = await read("RootfullLicenseBuild.plist");
const workflow = await read(".github/workflows/build.yml");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase5.ps1");

assert.ok(integration.phase >= 5);
assert.equal(integration.integration_mode, "task_and_long_running_component_gate");
assert.equal(integration.runtime_gate_active, true);
assert.ok(integration.next_runtime_gate_phase >= 6);
assert.ok(policy.phase >= 5);
assert.equal(
  policy.components.find(({ component }) => component === "app_ui")?.gate_status,
  "active_phase_5_feature_aware_memory_snapshot"
);

for (const evidence of [
  "TLinkLicensePerformanceDictionary",
  "feature_check_average_us",
  "status_refresh_average_ms",
  "cache_hit_count",
  "cache_miss_count",
  "generation_poll_interval_ms",
  "generation_poll_count",
  "mach_absolute_time",
]) {
  assert.ok(verifier.includes(evidence), `verifier lacks performance evidence ${evidence}`);
}
assert.match(verifierHeader, /TLinkLicensePerformanceDictionary/);

for (const evidence of [
  "cachedLicenseStatus",
  "cachedFeatureAllowed",
  "refreshLicenseUISnapshotAsyncForReason",
]) {
  assert.ok(lifecycleHeader.includes(evidence), `lifecycle header lacks ${evidence}`);
}
for (const evidence of [
  "com.tlinkauto.license-ui-snapshot",
  "rootfull_ui_memory_snapshot",
  "uiSnapshotRefreshInFlight",
  "uiSnapshotRefreshPending",
  "dispatch_get_global_queue(QOS_CLASS_UTILITY",
  "verifier_performance",
]) {
  assert.ok(lifecycle.includes(evidence), `lifecycle lacks ${evidence}`);
}

assert.match(scriptCell, /cachedFeatureAllowed:@"script"/);
assert.doesNotMatch(scriptCell, /TLinkLicenseFeatureAllowed\(@"script"/);
assert.match(scriptCell, /applyScriptLicenseState/);
assert.match(scripts, /refreshLicenseUISnapshotAsyncForReason:@"scripts_view_loaded"/);
assert.match(scripts, /licenseSnapshotDidChange/);
assert.match(settings, /@"feature":\s*@"stream"/);
assert.match(settings, /@"feature":\s*@"automation"/);
assert.match(settings, /@"feature":\s*@"script"/);
assert.match(settings, /cachedFeatureAllowed:feature/);
assert.match(licenseView, /SCLicenseSectionPerformance/);
assert.match(licenseView, /Memory snapshot/);
assert.match(licenseView, /QOS_CLASS_UTILITY/);

for (const source of [socket, task]) {
  assert.match(source, /(?:rootfull_license_phase"\]|licenseStatus\[@"phase"\])\s*=\s*@[56]/);
  assert.match(source, /ui_feature_snapshot_active/);
  assert.match(source, /verifier_performance/);
  assert.match(source, /TLinkLicensePerformanceDictionary/);
}
assert.match(socket, /license_phase=[56]/);
assert.match(socket, /uiFeatureSnapshot=1/);
assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>[56]<\/integer>/);
assert.match(workflow, /check-rootfull-license-phase5\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase[56]-artifact\.mjs/);
assert.match(deviceProbe, /ExpectedPhase\s*=\s*5/);
assert.match(deviceProbe, /feature_check_average_us/);

console.log(
  "rootfull license phase 5 OK: feature-aware memory snapshot UI, background refresh, " +
  "verifier latency metrics and backend authority preserved"
);
