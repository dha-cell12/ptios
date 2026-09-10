import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-background-agent-contract-v1.json"));

const [agent, entitlements, agentMakefile, aggregate, info, helper, supervisor, server, artifact, device, doc, manager, appEntitlements, settings] =
  await Promise.all([
    read("stream-app/vpnagent/main.mm"),
    read("stream-app/vpnagent/entitlements.plist"),
    read("stream-app/vpnagent/Makefile"),
    read("stream-app/Makefile"),
    read("stream-app/app/Info.plist"),
    read("stream-app/privhelper/main.mm"),
    read("stream-app/app/StreamSupervisor.mm"),
    read("stream-app/streamd/POCSocketServer.mm"),
    read("scripts/validate-license-artifact.mjs"),
    read("scripts/Test-TLinkVPNPhase5.ps1"),
    read("docs/vpn-p5-background-agent.md"),
    read("shared/TLinkVPNManager.mm"),
    read("stream-app/app/entitlements.plist"),
    read("TLinkauto/TLinkauto/Settings/TLinkVPNSettingsViewController.m"),
  ]);

assert.equal(fixture.phase, 5);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.agent.port, 6016);
assert.equal(fixture.agent.personaUid, 501);
assert.equal(fixture.state, "background_control");
assert.equal(fixture.promotionEvidence.backgroundDiagnostics, true);
assert.equal(fixture.promotionEvidence.backgroundConnect, true);
assert.equal(fixture.agent.version, 7);
assert.equal(fixture.promotionEvidence.agentVersion, 7);
assert.equal(fixture.promotionEvidence.mobileIdentity, true);
assert.equal(fixture.promotionEvidence.privateProfileMutation, true);
assert.equal(fixture.promotionEvidence.firstRunLocalProfileBootstrapRequired, true);
assert.equal(fixture.security.credentialsOverAgent, false);
assert.equal(fixture.security.packetTunnelProvider, false);

assert.match(agent, /kTLinkVPNAgentPort = 6016/);
assert.match(agent, /vpnagent_ready version=7 phase=5/);
assert.match(agent, /setgroups\(0, NULL\)/);
assert.match(agent, /setgid\(501\)/);
assert.match(agent, /setuid\(501\)/);
assert.match(agent, /getuid\(\) != 501/);
assert.match(agent, /background_vpnagent/);
assert.match(agent, /dispatch_get_global_queue\(QOS_CLASS_UTILITY/);
assert.match(agent, /CFRunLoopRun\(\)/);
assert.match(agent, /CFRunLoopAddTimer/);
assert.match(agent, /TLinkLicenseFeatureAllowed\(@"automation"/);
assert.match(agent, /TLinkVPNReadManagerStatus/);
assert.match(agent, /TLinkVPNSetConnected/);
assert.doesNotMatch(agent, /serverAddress|remoteIdentifier|username|password|sharedSecret|certificateData/);
assert.match(entitlements, /com\.apple\.developer\.networking\.vpn\.api/);
assert.match(entitlements, /allow-vpn/);
assert.match(entitlements, /StreamCtl\.com\.tlinkauto\.streamcontrol/);
assert.match(entitlements, /com\.apple\.SystemConfiguration\.SCPreferences-write-access/);
assert.match(entitlements, /com\.apple\.SystemConfiguration\.SCDynamicStore-write-access/);
assert.match(entitlements, /com\.apple\.managedconfiguration\.profiled-access/);
assert.match(entitlements, /preferences\.plist/);
assert.match(appEntitlements, /com\.apple\.SystemConfiguration\.SCPreferences-write-access/);
assert.match(appEntitlements, /com\.apple\.SystemConfiguration\.SCDynamicStore-write-access/);
assert.match(appEntitlements, /com\.apple\.managedconfiguration\.profiled-access/);
assert.doesNotMatch(entitlements, /packet-tunnel-provider/);
assert.match(agentMakefile, /TLINK_VPN_TROLLSTORE_RUNTIME=1/);
assert.match(agentMakefile, /NetworkExtension/);
const diagnosticsSource = await read("shared/TLinkVPNDiagnostics.mm");
assert.match(
  diagnosticsSource,
  /VPNPreferences\.bundle[\s\S]*VPNConnectionStore[\s\S]*createVPNWithOptions:[\s\S]*setActiveVPNID:/,
);
assert.match(diagnosticsSource, /vpn-private-owned\.plist/);
assert.match(diagnosticsSource, /mutating_api_exercised/);
assert.match(diagnosticsSource, /scpreferences_write_access/);
assert.match(diagnosticsSource, /scdynamicstore_write_access/);
assert.match(diagnosticsSource, /profiled_access/);
assert.match(manager, /TLinkVPNPrivateRemoveOwnedProfileSync/);
assert.match(manager, /vpn_private_cleanup_delete_failed/);
assert.match(manager, /configureWithKnownGoodBackend/);
assert.match(manager, /restore the proven native path/);
assert.match(manager, /BOOL modernStore/);
assert.match(manager, /NSString \*effectiveRemote = remote\.length > 0 \? remote : server/);
assert.match(settings, /Remote identifier \(defaults to server\)/);
assert.match(manager, /TLinkVPNPrivateRunSafely/);
assert.match(manager, /@catch \(NSException \*exception\)/);
assert.match(manager, /\[NSThread isMainThread\]/);
assert.match(manager, /createAllVPNByUserDefinedNamesDictionary/);
assert.match(manager, /single_identifier_delta/);
assert.match(manager, /verification_attempts/);
assert.match(manager, /\[\[NSRunLoop currentRunLoop\] runUntilDate:/);
assert.match(settings, /saveProfileButton\.enabled = NO/);
assert.match(settings, /saveProfileButton\.enabled = YES/);
assert.match(settings, /native TLink-owned IKEv2 profile/);
assert.doesNotMatch(settings, /private no-consent backend/);
assert.match(manager, /TLinkVPNPrivateSelectConfiguration/);
assert.match(manager, /TLinkVPNPrivateSetConnectedSync/);
assert.match(manager, /vpn-private-owned\.plist/);
assert.match(manager, /NSFilePosixPermissions: @0600/);
assert.match(manager, /hasPrefix:kTLinkVPNPrivateNamePrefix/);
assert.match(manager, /oldMarker\[@"identifier"\]/);
assert.match(manager, /vpn_private_profile_saved/);
assert.match(manager, /configureWithNEVPNManager/);
assert.match(manager, /TLinkVPNConfigureLegacyPrivate/);
assert.match(manager, /TLinkVPNPrivateConfigureLegacySync/);
assert.match(manager, /@"L2TP": @0/);
assert.match(manager, /@"PPTP": @1/);
assert.match(manager, /@"IPSec": @2/);
assert.match(manager, /@"VPNType": modernStore \? protocolType : legacyType/);
assert.match(manager, /@"authType": \[protocolType isEqualToString:@"PPTP"\] \? @0 : @1/);
assert.match(manager, /@"VPNSendAllTraffic": @1/);
assert.match(manager, /profile_type/);
assert.match(manager, /vpn_private_on_demand_unsupported/);
assert.match(settings, /@\[@"IKEv2", @"PPTP", @"L2TP", @"IPSec"\]/);
assert.match(settings, /TLinkVPNConfigureLegacyPrivate/);
assert.match(settings, /Shared secret/);
assert.match(settings, /no-confirm private backend/);

assert.match(aggregate, /vpnagent/);
assert.match(aggregate, /ldid -Svpnagent\/entitlements\.plist/);
assert.doesNotMatch(info, /<string>vpnagent<\/string>/);
assert.match(helper, /TLinkEnsureVPNAgent/);
assert.match(helper, /--ensure-vpnagent/);
assert.match(helper, /posix_spawnattr_set_persona_uid_np\(&attr, 501\)/);
assert.match(helper, /posix_spawnattr_set_persona_gid_np\(&attr, 501\)/);
assert.match(helper, /containsString:@"version=7"/);
assert.match(helper, /containsString:@" uid=501 "/);
assert.match(helper, /containsString:@" gid=501 "/);
assert.match(helper, /privhelper version=9/);
assert.match(supervisor, /kSCRequiredVPNServiceMarker = @"vpnPhase=5"/);
assert.match(supervisor, /containsString:kSCRequiredVPNServiceMarker/);

assert.match(server, /TLinkRunVPNBackgroundAgentWithTimeout/);
assert.match(server, /TLinkRunVPNBackgroundAgentWithRecovery/);
assert.match(server, /@\[@"--ensure-vpnagent", streamdPath\]/);
assert.match(server, /sin_port = htons\(6016\)/);
assert.match(server, /vpnagent_6016_then_StreamControl_6015/);
assert.match(server, /TLinkRunVPNForegroundBrokerWithTimeout/);
for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(server.includes(`${key}=${value}`), `task 97 is missing ${key}=${value}`);
}

assert.match(artifact, /"vpnagent"/);
assert.match(artifact, /vpnagentEntitlements/);
assert.match(artifact, /vpn_phase: 5/);
assert.match(artifact, /vpn_state: "background_control"/);
assert.match(artifact, /vpn_agent_version: 7/);
assert.match(artifact, /vpn_profile_bootstrap: "ikev2_nevpnmanager_legacy_private_no_consent"/);
assert.match(device, /background_vpnagent/);
assert.match(device, /agent_version 7/);
assert.match(device, /process_uid/);
assert.match(device, /private_candidate_ready/);
assert.match(device, /scpreferences_write_access/);
assert.match(device, /scdynamicstore_write_access/);
assert.match(device, /profiled_access/);
assert.match(device, /private_mutating_api_exercised/);
assert.match(device, /RequireManagedProfile/);
assert.match(device, /RequirePrivateProfile/);
assert.match(device, /ExpectedPrivateType/);
assert.match(device, /nevpnmanager_ikev2/);
assert.match(device, /vpnconnectionstore_private/);
assert.match(device, /vpnPhase=5/);
assert.match(device, /initial_connection_status/);
assert.match(doc, /foreground/i);
assert.match(doc, /background_control/);
assert.match(doc, /Save (?:IKEv2|L2TP) Profile/);
assert.match(doc, /vpn_not_configured/);
assert.match(doc, /6016/);

console.log("VPN P5 background control OK: validated mobile vpnagent 6016 is primary with foreground fallback");
