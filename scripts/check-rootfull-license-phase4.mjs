import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const policy = JSON.parse(await read("license-rootfull-policy.json"));
const h264 = await read("pccontrol/H264Stream.xm");
const h264Header = await read("pccontrol/H264Stream.h");
const player = await read("pccontrol/ScriptPlayer.xm");
const playerHeader = await read("pccontrol/ScriptPlayer.h");
const scheduler = await read("pccontrol/Scheduler.xm");
const helper = await read("tlinkauto-jsd/TLinkJSHelperServer.mm");
const helperMakefile = await read("tlinkauto-jsd/Makefile");
const task = await read("pccontrol/Task.xm");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const buildPlist = await read("RootfullLicenseBuild.plist");
const workflow = await read(".github/workflows/build.yml");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase4.ps1");

assert.equal(integration.phase, 4);
assert.equal(integration.integration_mode, "task_and_long_running_component_gate");
assert.equal(integration.runtime_gate_active, true);
assert.equal(integration.next_runtime_gate_phase, 5);
assert.equal(policy.phase, 4);
assert.equal(policy.enforcement_behavior, "task_and_long_running_component_gate");

for (const [component, status] of [
  ["h264", "active_phase_4_accept_and_heartbeat"],
  ["script_runtime", "active_phase_4_heartbeat"],
  ["script_helper", "active_phase_4_start_and_heartbeat"],
  ["scheduler", "active_phase_4_launch_time_recheck"],
]) {
  const entry = policy.components.find((item) => item.component === component);
  assert.ok(entry, `missing Phase 4 component ${component}`);
  assert.equal(entry.gate_status, status);
}

assert.match(h264, /TLinkRootfullLicenseComponentAllowed\(@"stream",\s*@"h264_accept"/);
assert.match(h264, /TLinkRootfullLicenseComponentAllowed\(@"stream",\s*@"h264_session"/);
assert.match(h264, /nextLicenseCheck\s*=\s*now\s*\+\s*5\.0/);
assert.match(h264, /active client closed by license/);
assert.match(h264Header, /TLinkH264LicenseRevokedClientCount/);
const h264Server = h264.slice(h264.indexOf("void startH264StreamServer"));
assert.ok(
  h264Server.indexOf('@"h264_accept"') >= 0 &&
    h264Server.indexOf('@"h264_accept"') <
      h264Server.indexOf("atomic_compare_exchange_strong(&gActiveClientFd"),
  "H264 license gate must run before accepting the active viewer"
);

assert.match(player, /TLinkRootfullLicenseComponentAllowed\(@"script",\s*@"script_runtime"/);
assert.match(player, /license_revoked_during_execution/);
assert.match(player, /dispatch_source_set_timer[\s\S]*NSEC_PER_SEC/);
assert.match(player, /\[runtime requestStop\]/);
assert.match(player, /fclose\(file\)/);
assert.match(playerHeader, /licenseRuntimeDiagnostics/);

assert.match(scheduler, /TLinkSchedulerScriptLaunchAllowed\(@"scheduler_timer"\)/);
assert.match(scheduler, /scheduler launch blocked by license/);
assert.ok(
  scheduler.indexOf('TLinkSchedulerScriptLaunchAllowed(@"scheduler_timer")') <
    scheduler.indexOf("playScript((UInt8*)[script UTF8String]"),
  "scheduler must recheck the license before launching"
);

assert.match(helper, /TLinkRootfullLicenseComponentAllowed\(@"script"/);
assert.match(helper, /@"script_helper_start"/);
assert.match(helper, /license_revoked_during_execution/);
assert.match(helper, /closeActiveFileHandles/);
assert.match(helper, /licenseHeartbeatIntervalMs/);
assert.match(helperMakefile, /TLinkLicenseVerifier\.mm/);
assert.match(helperMakefile, /TLinkRootfullLicensePolicy\.mm/);
assert.match(helperMakefile, /TLINK_LICENSE_ROOTFULL_RUNTIME=1/);
assert.match(helperMakefile, /Security/);

for (const [name, source] of [["daemon", socket], ["SpringBoard", task]]) {
  assert.match(source, /task_and_long_running_component_gate/);
  assert.match(source, /(?:rootfull_license_phase"\]|licenseStatus\[@"phase"\])\s*=\s*@4/);
  assert.match(source, /h264_gate_active/);
  assert.match(source, /script_heartbeat_active/);
  assert.match(source, /scheduler_launch_gate_active/);
  assert.match(source, /helper_runtime_gate_active/);
  assert.ok(source.length > 0, `${name} diagnostics missing`);
}

assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>4<\/integer>/);
assert.match(buildPlist, /task_and_long_running_component_gate/);
assert.match(workflow, /check-rootfull-license-phase4\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase4-artifact\.mjs/);
assert.match(deviceProbe, /license_phase=4/);
assert.match(deviceProbe, /h264_heartbeat_interval_ms/);
assert.match(deviceProbe, /script_heartbeat_active/);

console.log(
  "rootfull license phase 4 OK: H264 accept/session, script/helper heartbeat, " +
  "scheduler launch-time gate and cleanup diagnostics"
);
