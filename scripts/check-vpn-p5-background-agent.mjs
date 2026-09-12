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
assert.equal(fixture.agent.version, 9);
assert.equal(fixture.promotionEvidence.agentVersion, 9);
assert.equal(fixture.promotionEvidence.mobileIdentity, true);
assert.equal(fixture.promotionEvidence.privateProfileMutation, true);
assert.equal(fixture.promotionEvidence.firstRunLocalProfileBootstrapRequired, false);
assert.equal(fixture.promotionEvidence.automationProfileBootstrap, true);
assert.equal(fixture.security.credentialsOverAgent, false);
assert.equal(fixture.security.packetTunnelProvider, false);
assert.equal(fixture.security.legacyProfileExecutor, "privhelper_tsrootbinary");
assert.equal(fixture.security.credentialTransport, "uid501_mode0600_one_shot_file");

assert.match(agent, /kTLinkVPNAgentPort = 6016/);
assert.match(agent, /vpnagent_ready version=9 phase=5/);
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
assert.match(entitlements, /com\.apple\.private\.networkextension\.configuration/);
assert.match(entitlements, /<string>super<\/string>/);
assert.match(entitlements, /com\.apple\.managed\.vpn\.shared/);
assert.match(entitlements, /com\.apple\.SystemConfiguration\.SCPreferences-write-access/);
assert.match(entitlements, /com\.apple\.SystemConfiguration\.SCDynamicStore-write-access/);
assert.match(entitlements, /com\.apple\.managedconfiguration\.profiled-access/);
assert.match(entitlements, /com\.apple\.managedconfiguration\.mdmd-access/);
assert.match(entitlements, /user-preference-write/);
assert.match(entitlements, /preferences\.plist/);
assert.match(appEntitlements, /com\.apple\.SystemConfiguration\.SCPreferences-write-access/);
assert.match(appEntitlements, /com\.apple\.SystemConfiguration\.SCDynamicStore-write-access/);
assert.match(appEntitlements, /com\.apple\.managedconfiguration\.profiled-access/);
assert.match(appEntitlements, /com\.apple\.managedconfiguration\.mdmd-access/);
assert.match(appEntitlements, /user-preference-write/);
assert.match(appEntitlements, /com\.apple\.private\.networkextension\.configuration/);
assert.match(appEntitlements, /<string>super<\/string>/);
assert.match(appEntitlements, /com\.apple\.managed\.vpn\.shared/);
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
assert.match(diagnosticsSource, /mdmd_access/);
assert.match(diagnosticsSource, /user_preference_read/);
assert.match(diagnosticsSource, /user_preference_write/);
assert.match(diagnosticsSource, /private_configuration_super/);
assert.match(diagnosticsSource, /managed_vpn_keychain_access/);
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
assert.match(manager, /TLinkVPNRunLegacyRootHelperSync/);
assert.match(manager, /TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper/);
assert.match(manager, /TLinkVPNRunPrivateConfigurationHelper/);
assert.match(manager, /@"L2TP": @0/);
assert.match(manager, /@"PPTP": @1/);
assert.match(manager, /@"IPSec": @2/);
assert.match(manager, /@"VPNType": modernStore \? protocolType : legacyType/);
assert.match(manager, /@"authType": \[protocolType isEqualToString:@"PPTP"\] \? @0 : @1/);
assert.match(manager, /@"VPNSendAllTraffic": @\(sendAllTraffic\)/);
assert.match(manager, /profile_type/);
assert.match(manager, /vpn_private_on_demand_unsupported/);
assert.match(manager, /privhelper_root_private_store_no_nevpnmanager/);
assert.match(manager, /vpn_l2tp_ipsec_shared_secret_required/);
assert.match(settings, /IPSec shared secret \(required\)/);
assert.match(settings, /@\[@"IKEv2", @"PPTP", @"L2TP", @"IPSec"\]/);
assert.match(settings, /TLinkVPNConfigureLegacyPrivate/);
assert.match(settings, /Shared secret/);
assert.match(settings, /no-confirm private backend/);

assert.match(aggregate, /vpnagent/);
assert.match(aggregate, /ldid -Svpnagent\/entitlements\.plist/);
assert.doesNotMatch(info, /<string>vpnagent<\/string>/);
assert.match(helper, /TLinkEnsureVPNAgent/);
assert.match(helper, /--ensure-vpnagent/);
assert.match(helper, /--configure-legacy-vpn/);
assert.match(helper, /--configure-vpn/);
assert.match(helper, /TLinkHelperConfigureVPN/);
assert.match(helper, /TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper/);
assert.match(helper, /TLinkVPNConfigureIKEv2SynchronouslyForHelper/);
assert.match(helper, /requestStat\.st_uid != 501/);
assert.match(helper, /requestStat\.st_nlink != 1/);
assert.match(helper, /fchown\(fd, 501, 501\)/);
assert.match(helper, /posix_spawnattr_set_persona_uid_np\(&attr, 501\)/);
assert.match(helper, /posix_spawnattr_set_persona_gid_np\(&attr, 501\)/);
assert.match(helper, /containsString:@"version=9"/);
assert.match(helper, /containsString:@" uid=501 "/);
assert.match(helper, /containsString:@" gid=501 "/);
assert.match(helper, /privhelper version=11/);
assert.match(supervisor, /kSCRequiredVPNServiceMarker = @"vpnPhase=5"/);
assert.match(supervisor, /containsString:kSCRequiredVPNServiceMarker/);

assert.match(server, /TLinkRunVPNBackgroundAgentWithTimeout/);
assert.match(server, /TLinkRunVPNBackgroundAgentWithRecovery/);
assert.match(server, /@\[@"--ensure-vpnagent", streamdPath\]/);
assert.match(server, /sin_port = htons\(6016\)/);
assert.match(server, /vpnagent_6016_then_StreamControl_6015/);
assert.match(server, /TLinkRunVPNForegroundBrokerWithTimeout/);
assert.match(server, /vpnconf\[@"create"\]/);
assert.match(server, /vpnconf\[@"createResult"\]/);
assert.match(server, /vpnconf\[@"lastResult"\]/);
assert.match(server, /TLinkVPNRunPrivateConfigurationHelper/);
assert.match(server, /vpnScriptConfigurationTransport=vpnconf_privhelper_mode0600_v1/);
const requestTransport = await read("shared/TLinkVPNPrivateRequest.mm");
assert.match(requestTransport, /vpn-private-requests/);
assert.match(requestTransport, /O_WRONLY \| O_CREAT \| O_EXCL \| O_NOFOLLOW/);
assert.match(requestTransport, /fchmod\(requestFd, 0600\)/);
assert.match(requestTransport, /fchown\(requestFd, 501, 501\)/);
assert.match(requestTransport, /callerUID == 501 && callerGID == 501/);
assert.match(requestTransport, /posix_spawnattr_set_persona_uid_np\(&attr, 0\)/);
assert.match(requestTransport, /--configure-vpn/);
assert.doesNotMatch(requestTransport, /NSLog|printf/);
for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(server.includes(`${key}=${value}`), `task 97 is missing ${key}=${value}`);
}

assert.match(artifact, /"vpnagent"/);
assert.match(artifact, /vpnagentEntitlements/);
assert.match(artifact, /vpn_phase: 5/);
assert.match(artifact, /vpn_state: "background_control"/);
assert.match(artifact, /vpn_agent_version: 9/);
assert.match(artifact, /vpn_profile_bootstrap: "ikev2_nevpnmanager_legacy_privhelper_root_no_consent"/);
assert.match(device, /background_vpnagent/);
assert.match(device, /agent_version 9/);
assert.match(device, /process_uid/);
assert.match(device, /private_candidate_ready/);
assert.match(device, /scpreferences_write_access/);
assert.match(device, /scdynamicstore_write_access/);
assert.match(device, /profiled_access/);
assert.match(device, /mdmd_access/);
assert.match(device, /user_preference_read/);
assert.match(device, /user_preference_write/);
assert.match(device, /private_configuration_super/);
assert.match(device, /managed_vpn_keychain_access/);
assert.match(device, /private_mutating_api_exercised/);
assert.match(device, /RequireManagedProfile/);
assert.match(device, /RequirePrivateProfile/);
assert.match(device, /ExpectedPrivateType/);
assert.match(device, /privhelper_root_private_store_no_nevpnmanager/);
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
