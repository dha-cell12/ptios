import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-rootfull-broker-contract-v1.json"));

assert.equal(fixture.phase, 2);
assert.equal(fixture.runtime, "rootfull");
assert.equal(fixture.legacyTask, 59);
assert.equal(fixture.brokerHost, "127.0.0.1");
assert.equal(fixture.brokerPort, 6014);
assert.equal(fixture.profileIdentifier, "tlinkauto-managed-v1");
assert.equal(fixture.security.credentialsOverTask59, false);
assert.equal(fixture.security.foreignProfileMutation, false);
assert.equal(fixture.security.onDemandEnabled, false);

const [
  rootMakefile,
  brokerMakefile,
  broker,
  manager,
  managerHeader,
  connectivity,
  task,
  rootServer,
  appEntitlements,
  shortcutEntitlements,
  launchd,
  postinst,
  settings,
  vpnSettings,
  project,
  workflow,
  artifactValidator,
  policyText,
  integrationText,
  p2Doc,
  plan,
] = await Promise.all([
  read("Makefile"),
  read("vpn-broker/Makefile"),
  read("vpn-broker/main.mm"),
  read("shared/TLinkVPNManager.mm"),
  read("shared/TLinkVPNManager.h"),
  read("pccontrol/Connectivity.xm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("layout/entitlements.plist"),
  read("layout/shortcut-entitlements.plist"),
  read("layout/Library/LaunchDaemons/com.tlinkauto.vpn-broker.plist"),
  read("layout/DEBIAN/postinst"),
  read("TLinkauto/TLinkauto/Settings/SettingsPageViewController.m"),
  read("TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.m"),
  read("TLinkauto/TLinkauto.xcodeproj/project.pbxproj"),
  read(".github/workflows/build.yml"),
  read("scripts/validate-rootfull-license-phase6-artifact.mjs"),
  read("license-rootfull-policy.json"),
  read("license-rootfull-integration.json"),
  read("docs/vpn-p2-rootfull-broker.md"),
  read("plan.md"),
]);

assert.match(rootMakefile, /SUBPROJECTS = [^\r\n]*vpn-broker/);
assert.match(brokerMakefile, /TOOL_NAME = tlinkauto-vpnd/);
assert.match(brokerMakefile, /NetworkExtension/);
assert.match(brokerMakefile, /TLinkLicenseVerifier\.mm/);
assert.match(brokerMakefile, /TLINK_LICENSE_FORCE_ENFORCEMENT/);
assert.match(brokerMakefile, /TLinkRootfullLicenseBuild\.mm/);

assert.match(broker, /127\.0\.0\.1/);
assert.match(broker, /kTLinkVPNBrokerPort = 6014/);
assert.match(
  broker,
  /while \(requestData\.length < kTLinkVPNBrokerMaxRequest\)[\s\S]*?memchr\(buffer, '\\n'/,
);
for (const command of fixture.brokerCommands) {
  assert.ok(broker.includes(`@"${command}"`), `broker command missing: ${command}`);
}
assert.match(broker, /TLinkLicenseFeatureAllowed\(@"automation"/);
assert.match(broker, /TLinkVPNSetConnected/);
assert.match(broker, /TLinkVPNReadManagerStatus/);
assert.doesNotMatch(broker, /serverAddress|username|password|providerConfiguration/);

assert.match(managerHeader, /TLinkVPNConfigureIKEv2/);
assert.match(manager, /\[NEVPNManager sharedManager\]/);
assert.match(manager, /TLinkVPNManagerIsOwned/);
assert.match(manager, /vpn_foreign_profile_present/);
assert.match(manager, /TLinkauto Managed VPN \(tlinkauto-managed-v1\)/);
assert.match(manager, /kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly/);
assert.match(manager, /passwordReference = passwordReference/);
assert.match(manager, /NEVPNProtocolIKEv2/);
assert.match(manager, /useExtendedAuthentication = true/);
assert.match(manager, /onDemandEnabled = false/);
assert.match(manager, /NEVPNStatusDidChangeNotification/);
assert.match(manager, /vpn_transition_timeout/);
assert.match(manager, /MIN\(MAX\(timeout, 5\.0\), 30\.0\)/);
assert.doesNotMatch(manager, /NETunnelProviderManager|NEPacketTunnelProvider/);

assert.match(connectivity, /htons\(6014\)/);
assert.match(connectivity, /inet_pton\(AF_INET, "127\.0\.0\.1"/);
assert.match(connectivity, /@"query"/);
assert.match(connectivity, /@"connect"/);
assert.match(connectivity, /@"disconnect"/);
assert.match(connectivity, /@"diagnostics"/);
assert.doesNotMatch(connectivity, /NEVPNManager|startVPNTunnel|saveToPreferences/);
assert.match(task, /@"broker_managed"/);
assert.match(task, /@"tlinkauto_vpnd_6014"/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(rootServer.includes(`${key}=${value}`), `rootfull task 97 is missing ${key}=${value}`);
}

assert.match(appEntitlements, /com\.apple\.developer\.networking\.vpn\.api[\s\S]*allow-vpn/);
assert.doesNotMatch(appEntitlements, /packet-tunnel-provider/);
assert.doesNotMatch(shortcutEntitlements, /networking\.vpn\.api|networking\.networkextension/);
assert.match(workflow, /shortcut-entitlements\.plist/);

assert.match(launchd, /<string>\/usr\/libexec\/tlinkauto-vpnd<\/string>/);
assert.match(launchd, /<key>UserName<\/key>\s*<string>mobile<\/string>/);
assert.match(launchd, /<key>KeepAlive<\/key>\s*<true\/>/);
assert.match(postinst, /launchctl load -w \/Library\/LaunchDaemons\/com\.tlinkauto\.vpn-broker\.plist/);
assert.match(postinst, /chmod \+x \/usr\/libexec\/tlinkauto-vpnd/);

assert.match(settings, /Managed IKEv2 VPN/);
assert.match(settings, /handleVPNWithEntryCellInstance/);
assert.match(vpnSettings, /secureTextEntry = secure/);
assert.match(vpnSettings, /TLinkVPNConfigureIKEv2/);
assert.match(vpnSettings, /TLinkVPNSetConnected\(YES/);
assert.match(vpnSettings, /TLinkVPNSetConnected\(NO/);
assert.doesNotMatch(vpnSettings, /send:|byPort:6000|6014/);

for (const marker of [
  "TLinkVPNManager.mm in Sources",
  "TLinkVPNSettingsViewController.m in Sources",
  "NetworkExtension.framework in Frameworks",
]) {
  assert.ok(project.includes(marker), `Xcode project missing ${marker}`);
}

assert.match(artifactValidator, /usr\/libexec\/tlinkauto-vpnd/);
assert.match(artifactValidator, /signedEntitlements/);
assert.match(artifactValidator, /com\.apple\.developer\.networking\.vpn\.api/);
assert.match(artifactValidator, /shortcut extension must not inherit VPN entitlements/);
const policy = JSON.parse(policyText);
const integration = JSON.parse(integrationText);
assert.equal(
  policy.components.find(({ component }) => component === "vpn_broker")?.feature,
  "automation",
);
assert.equal(
  integration.verifier_components.find(({ component }) => component === "vpn_broker")?.binary,
  "usr/libexec/tlinkauto-vpnd",
);

assert.match(
  p2Doc,
  /Only a rootfull device\s+with a real IKEv2 server can prove/i,
);
assert.match(p2Doc, /never accepted[\s\S]*through task `59`/i);
assert.match(plan, /VPN P2/);

for (const key of [
  "serverAddress",
  "remoteIdentifier",
  "username",
  "password",
]) {
  assert.ok(!JSON.stringify(fixture).includes(`"${key}"`), `wire fixture must not contain ${key}`);
}

console.log("VPN P2 rootfull OK: owned IKEv2 app/broker path, Keychain boundary, license gate and terminal wait enforced");
