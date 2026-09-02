import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-background-agent-contract-v1.json"));

const [agent, entitlements, agentMakefile, aggregate, info, helper, supervisor, server, artifact, device, doc] =
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
  ]);

assert.equal(fixture.phase, 5);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.agent.port, 6016);
assert.equal(fixture.agent.personaUid, 501);
assert.equal(fixture.state, "background_control");
assert.equal(fixture.promotionEvidence.backgroundDiagnostics, true);
assert.equal(fixture.promotionEvidence.backgroundConnect, true);
assert.equal(fixture.promotionEvidence.agentVersion, 2);
assert.equal(fixture.promotionEvidence.mobileIdentity, true);
assert.equal(fixture.promotionEvidence.firstRunLocalProfileBootstrapRequired, true);
assert.equal(fixture.security.credentialsOverAgent, false);
assert.equal(fixture.security.packetTunnelProvider, false);

assert.match(agent, /kTLinkVPNAgentPort = 6016/);
assert.match(agent, /vpnagent_ready version=2 phase=5/);
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
assert.doesNotMatch(entitlements, /packet-tunnel-provider/);
assert.match(agentMakefile, /TLINK_VPN_TROLLSTORE_RUNTIME=1/);
assert.match(agentMakefile, /NetworkExtension/);
const diagnosticsSource = await read("shared/TLinkVPNDiagnostics.mm");
assert.match(
  diagnosticsSource,
  /VPNPreferences\.bundle[\s\S]*VPNConnectionStore[\s\S]*createVPNWithOptions:[\s\S]*setActiveVPNID:/,
);
assert.match(diagnosticsSource, /mutating_api_exercised[^\n]*@0/);

assert.match(aggregate, /vpnagent/);
assert.match(aggregate, /ldid -Svpnagent\/entitlements\.plist/);
assert.doesNotMatch(info, /<string>vpnagent<\/string>/);
assert.match(helper, /TLinkEnsureVPNAgent/);
assert.match(helper, /--ensure-vpnagent/);
assert.match(helper, /posix_spawnattr_set_persona_uid_np\(&attr, 501\)/);
assert.match(helper, /posix_spawnattr_set_persona_gid_np\(&attr, 501\)/);
assert.match(helper, /containsString:@"version=2"/);
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
assert.match(artifact, /vpn_agent_version: 2/);
assert.match(artifact, /vpn_profile_bootstrap: "local_ui_keychain_once"/);
assert.match(device, /background_vpnagent/);
assert.match(device, /agent_version 2/);
assert.match(device, /process_uid/);
assert.match(device, /private_candidate_ready/);
assert.match(device, /private_mutating_api_exercised/);
assert.match(device, /vpnPhase=5/);
assert.match(device, /initial_connection_status/);
assert.match(doc, /foreground/i);
assert.match(doc, /background_control/);
assert.match(doc, /Save Profile/);
assert.match(doc, /vpn_not_configured/);
assert.match(doc, /6016/);

console.log("VPN P5 background control OK: validated mobile vpnagent 6016 is primary with foreground fallback");
