import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-on-demand-contract-v1.json"));

assert.equal(fixture.phase, 4);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.legacyTask, 59);
assert.equal(fixture.profileIdentifier, "tlinkauto-managed-v1");
assert.equal(fixture.onDemandRule, "connect_all_networks");
assert.equal(fixture.configurationTransport, "local_ui_only");
assert.equal(fixture.explicitDisconnectPolicy, "disable_on_demand_then_stop");
assert.equal(fixture.security.credentialsOverTask59, false);
assert.equal(fixture.security.onDemandControlOverTask59, false);
assert.equal(fixture.security.foreignProfileMutation, false);
assert.equal(fixture.security.packetTunnelProvider, false);

const [
  managerHeader,
  manager,
  settings,
  rootBroker,
  trollBroker,
  rootTask,
  rootServer,
  trollServer,
  rootWorkflow,
  trollWorkflow,
  deviceTest,
  p4Doc,
  statusDoc,
  plan,
] = await Promise.all([
  read("shared/TLinkVPNManager.h"),
  read("shared/TLinkVPNManager.mm"),
  read("TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.m"),
  read("vpn-broker/main.mm"),
  read("stream-app/app/TLinkVPNForegroundBroker.mm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
  read("scripts/Test-TLinkVPNPhase4.ps1"),
  read("docs/vpn-p4-on-demand.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
]);

assert.match(managerHeader, /TLinkVPNSetOnDemandEnabled/);
assert.match(manager, /NEOnDemandRuleConnect/);
assert.match(manager, /manager\.onDemandRules = @\[connectRule\]/);
assert.match(manager, /manager\.onDemandEnabled = true/);
assert.match(manager, /manager\.onDemandEnabled = false/);
assert.match(manager, /@"on_demand_enabled"/);
assert.match(manager, /@"on_demand_rule_count"/);
assert.match(manager, /@"on_demand_mode"/);
assert.match(manager, /vpn_on_demand_verification_failed/);
assert.match(manager, /!connected && manager\.onDemandEnabled/);
assert.match(manager, /TLinkVPNSetOnDemandEnabled\(false/);
assert.match(manager, /vpn_disconnect_disable_on_demand_failed/);
assert.doesNotMatch(manager, /NETunnelProviderManager|NEPacketTunnelProvider/);

assert.match(settings, /Auto-Reconnect \(On Demand\)/);
assert.match(settings, /onDemandChanged:/);
assert.match(settings, /TLinkVPNSetOnDemandEnabled\(requested/);
assert.match(settings, /Disconnecting[\s\S]*explicitly also disables Auto-Reconnect/);
assert.doesNotMatch(settings, /send:|byPort:6000|6014|6015/);

for (const broker of [rootBroker, trollBroker]) {
  assert.match(broker, /@"phase"\]\s*=\s*@4/);
  assert.match(broker, /@"on_demand_policy"/);
  assert.match(broker, /@"on_demand_enabled"/);
  assert.match(broker, /@"on_demand_rule_count"/);
  assert.match(broker, /@"on_demand_mode"/);
  assert.doesNotMatch(broker, /TLinkVPNSetOnDemandEnabled/);
}
assert.doesNotMatch(rootBroker, /serverAddress|username|password|providerConfiguration/);
assert.doesNotMatch(trollBroker, /serverAddress|username|password|providerConfiguration/);

assert.match(rootTask, /@"full_control"/);
assert.match(rootTask, /@"phase"\]\s*=\s*@4/);
assert.match(p4Doc, /vpnState=app_side_control/);
assert.match(p4Doc, /vpnPhase=4/);
assert.match(trollServer, /local_ui_connect_all_networks_explicit_disconnect_disables/);
assert.match(trollServer, /TLinkRunVPNForegroundBrokerWithTimeout/);
assert.match(trollServer, /@"diagnostics"[\s\S]*?&brokerError,[\s\S]*?5\)/);
assert.match(trollServer, /@"streamd_interface_fallback"/);
assert.match(trollServer, /@"foreground_heartbeat_fresh"/);
assert.match(trollBroker, /@"foreground_app_broker"/);
assert.match(rootBroker, /@"rootfull_broker"/);

for (const [key, value] of Object.entries(
  fixture.runtimes.rootfull.requiredCapabilityFields,
)) {
  assert.ok(rootServer.includes(`${key}=${value}`), `rootfull task 97 is missing ${key}=${value}`);
}
for (const [key, value] of Object.entries(
  fixture.runtimes.trollstore.requiredCapabilityFields,
)) {
  assert.ok(p4Doc.includes(`${key}=${value}`), `P4 baseline document is missing ${key}=${value}`);
}

assert.match(deviceTest, /ValidateSet\("rootfull", "trollstore"\)/);
assert.match(deviceTest, /ExpectOnDemand/);
assert.match(deviceTest, /RunDisconnect/);
assert.match(deviceTest, /explicit disconnect disables on-demand/);
assert.match(deviceTest, /used streamd fallback instead of foreground broker/);
assert.match(rootWorkflow, /check-vpn-p4-on-demand\.mjs/);
assert.match(trollWorkflow, /check-vpn-p4-on-demand\.mjs/);
assert.match(p4Doc, /NEOnDemandRuleConnect/);
assert.match(p4Doc, /both rootfull and TrollStore/i);
assert.match(p4Doc, /explicit[\s\S]*disconnect/i);
assert.match(statusDoc, /VPN P4/);
assert.match(plan, /VPN P4/);

const forbiddenFixtureKeys = /serverAddress|username|password|sharedSecret|privateKey|certificateData/i;
function assertNoSecretFields(value, path = "fixture") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoSecretFields(item, `${path}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      assert.ok(!forbiddenFixtureKeys.test(key), `${path}.${key} must not contain VPN configuration`);
      assertNoSecretFields(child, `${path}.${key}`);
    }
  }
}
assertNoSecretFields(fixture);

console.log(
  "VPN P4 on-demand OK: both runtimes expose local-only auto-reconnect and deterministic explicit disconnect",
);
