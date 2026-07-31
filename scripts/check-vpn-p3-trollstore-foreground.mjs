import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-trollstore-foreground-contract-v1.json"));

assert.equal(fixture.phase, 3);
assert.equal(fixture.runtime, "trollstore");
assert.equal(fixture.legacyTask, 59);
assert.equal(fixture.brokerHost, "127.0.0.1");
assert.equal(fixture.brokerPort, 6015);
assert.equal(fixture.profileIdentifier, "tlinkauto-managed-v1");
assert.equal(fixture.security.credentialsOverTask59, false);
assert.equal(fixture.security.streamdVPNEntitlement, false);
assert.equal(fixture.security.packetTunnelProvider, false);
assert.equal(fixture.security.onDemandEnabled, false);
assert.equal(fixture.security.foreignProfileMutation, false);

const [
  appMakefile,
  appEntitlements,
  streamdEntitlements,
  manager,
  broker,
  appDelegate,
  settings,
  vpnSettings,
  streamd,
  aggregateMakefile,
  artifactValidator,
  workflow,
  deviceTest,
  p3Doc,
  statusDoc,
  plan,
] = await Promise.all([
  read("stream-app/app/Makefile"),
  read("stream-app/app/entitlements.plist"),
  read("stream-app/streamd/entitlements.plist"),
  read("shared/TLinkVPNManager.mm"),
  read("stream-app/app/TLinkVPNForegroundBroker.mm"),
  read("stream-app/app/AppDelegate.mm"),
  read("stream-app/app/SettingsViewController.mm"),
  read("TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.m"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/Makefile"),
  read("scripts/validate-license-artifact.mjs"),
  read(".github/workflows/stream-app.yml"),
  read("scripts/Test-TLinkVPNPhase3.ps1"),
  read("docs/vpn-p3-trollstore-foreground.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
]);

assert.match(appMakefile, /TLinkVPNForegroundBroker\.mm/);
assert.match(appMakefile, /TLinkVPNSettingsViewController\.m/);
assert.match(appMakefile, /TLinkVPNManager\.mm/);
assert.match(appMakefile, /TLinkVPNDiagnostics\.mm/);
assert.match(appMakefile, /NetworkExtension/);
assert.match(appMakefile, /TLINK_VPN_TROLLSTORE_RUNTIME=1/);

assert.match(appEntitlements, /com\.apple\.developer\.networking\.vpn\.api[\s\S]*allow-vpn/);
assert.match(appEntitlements, /keychain-access-groups[\s\S]*StreamCtl\.com\.tlinkauto\.streamcontrol/);
assert.doesNotMatch(appEntitlements, /packet-tunnel-provider/);
assert.doesNotMatch(streamdEntitlements, /networking\.vpn\.api|networking\.networkextension/);
assert.match(aggregateMakefile, /ldid -Sapp\/entitlements\.plist "\$\$APP\/\$\(APP_NAME\)"/);

assert.match(manager, /#if TLINK_VPN_TROLLSTORE_RUNTIME/);
assert.match(manager, /@"StreamCtl\.com\.tlinkauto\.streamcontrol"/);
assert.match(manager, /@"com\.tlinkauto\.tlinkauto"/);
assert.match(manager, /kSecReturnPersistentRef\]\s*=\s*[\r\n\s]*\(__bridge id\)kCFBooleanTrue/);
assert.match(manager, /vpn_server_loopback_not_allowed/);
assert.match(manager, /onDemandEnabled = false/);

assert.match(broker, /kTLinkVPNForegroundBrokerPort = 6015/);
assert.match(broker, /127\.0\.0\.1/);
assert.match(broker, /UIApplicationStateActive/);
assert.match(broker, /vpn_foreground_app_required/);
assert.match(broker, /vpn_trollstore_entitlement_unavailable/);
assert.match(broker, /TLinkLicenseFeatureAllowed\(@"automation"/);
assert.match(broker, /TLinkVPNReadManagerStatus/);
assert.match(broker, /TLinkVPNSetConnected/);
assert.match(broker, /@"phase"\]\s*=\s*@3/);
assert.match(broker, /@"api_exercised"\]\s*=\s*@1/);
for (const command of fixture.brokerCommands) {
  assert.ok(broker.includes(`@"${command}"`), `foreground broker command missing: ${command}`);
}
assert.doesNotMatch(broker, /serverAddress|username|password|providerConfiguration/);

assert.match(appDelegate, /TLinkVPNStartForegroundBroker\(\)/);
assert.match(settings, /@"Managed VPN"/);
assert.match(settings, /VPN: foreground IKEv2 candidate/);
assert.match(settings, /TLinkVPNSettingsViewController/);
assert.match(vpnSettings, /TLinkVPNConfigureIKEv2/);
assert.match(vpnSettings, /pollTransitionStatusForGeneration/);

assert.match(streamd, /htons\(6015\)/);
assert.match(streamd, /TLinkRunVPNForegroundBroker/);
assert.match(streamd, /@"query"/);
assert.match(streamd, /@"connect"/);
assert.match(streamd, /@"disconnect"/);
assert.match(streamd, /@"diagnostics"/);
assert.match(streamd, /vpn_foreground_app_required/);
assert.match(streamd, /TLinkAppForegroundHeartbeatIsFresh\(\)/);
assert.match(streamd, /TLinkSuccess\(TLinkVPNInterfaceActive\(\) \? @"1" : @"0"\)/);
assert.doesNotMatch(streamd, /NEVPNManager|startVPNTunnel|saveToPreferences/);
for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(streamd.includes(`${key}=${value}`), `TrollStore task 97 is missing ${key}=${value}`);
}
assert.match(streamd, /@"vpnEntitlementProbe": @"foreground_app_process_via_592"/);

assert.match(artifactValidator, /StreamControl lacks VPN P3 foreground broker evidence/);
assert.match(artifactValidator, /com\.apple\.developer\.networking\.vpn\.api/);
assert.match(artifactValidator, /streamd must not inherit VPN or packet-tunnel entitlements/);
assert.match(workflow, /check-vpn-p3-trollstore-foreground\.mjs/);
assert.match(deviceTest, /Invoke-TLinkVPNTask/);
assert.match(deviceTest, /RunTransitions/);
assert.match(deviceTest, /vpnPhase=3/);
assert.match(p3Doc, /foreground-only/i);
assert.match(p3Doc, /device evidence/i);
assert.match(statusDoc, /VPN P3/);
assert.match(plan, /VPN P3/);

const forbiddenFixtureKeys = /serverAddress|username|password|sharedSecret|privateKey|certificateData/i;
for (const key of Object.keys(fixture)) {
  assert.ok(!forbiddenFixtureKeys.test(key), `fixture must not contain secret/config key ${key}`);
}

console.log(
  "VPN P3 TrollStore OK: foreground app candidate, entitlement boundary, task59 bridge and query fallback enforced",
);
