import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-wire-contract-v1.json"));

assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.lineEnding, "\r\n");
assert.equal(fixture.delimiter, ";;");
assert.equal(fixture.task, 59);
assert.equal(fixture.profileScope, "tlink_owned_only");
assert.equal(fixture.configurationTransport, "local_ui_keychain_only");
assert.equal(fixture.credentialsOverTask59, false);

assert.deepEqual(fixture.requests, {
  query: "590\r\n",
  disconnect: "591;;0\r\n",
  connect: "591;;1\r\n",
  diagnosticsReserved: "592\r\n",
});
for (const key of ["queryDisconnected", "queryConnected", "disconnectObserved", "connectObserved"]) {
  assert.match(fixture.targetResponses[key], /^0;;[01]\r\n$/);
}
assert.equal(fixture.targetResponses.diagnosticsPrefix, "0;;");
assert.equal(fixture.targetResponses.errorPrefix, "-1;;");

const [
  rootfullHeader,
  rootfullConnectivity,
  rootfullTask,
  rootfullServer,
  sharedVPN,
  trollServer,
  pythonClient,
  pythonDataHandler,
  trollPolicy,
  rootfullPolicy,
  baselineDoc,
  trollStatusDoc,
  plan,
] = await Promise.all([
  read("pccontrol/Task.h"),
  read("pccontrol/Connectivity.xm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("shared/TLinkVPNDiagnostics.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("webtango/tlinkauto/client.py"),
  read("webtango/tlinkauto/datahandler.py"),
  read("license-task-policy.json"),
  read("shared/TLinkRootfullLicensePolicy.mm"),
  read("docs/vpn-p0-baseline.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
]);

assert.match(rootfullHeader, /#define TASK_VPN 59/);
assert.match(rootfullTask, /taskType == TASK_VPN[\s\S]*?vpnTaskFromRawData\(eventData, &err\)/);
assert.match(rootfullConnectivity, /NSString\* vpnTaskFromRawData[\s\S]*?VPN control not implemented on this build\./);
assert.doesNotMatch(rootfullConnectivity, /NEVPNManager|NETunnelProviderManager|NetworkExtension/);

assert.match(trollServer, /if \(taskType >= 55 && taskType <= 59\)[\s\S]*?TLinkHandleConnectivityTask/);
assert.match(trollServer, /static NSData \*TLinkHandleVPNConnectivity[\s\S]*?TLinkVPNInterfaceActive\(\)[\s\S]*?vpn_control_requires_profile_or_private_entitlement query_only_supported/);
assert.doesNotMatch(
  trollServer.slice(
    trollServer.indexOf("static NSData *TLinkHandleVPNConnectivity"),
    trollServer.indexOf("static NSData *TLinkHandleConnectivityTask"),
  ),
  /NEVPNManager|NETunnelProviderManager|startVPNTunnel/,
);

assert.match(pythonDataHandler, /str\(task_type\) \+ \(";;"\.join/);
assert.match(pythonClient, /def turn_on_vpn\(self\):[\s\S]*?TASK_VPN, 1, 1/);
assert.match(pythonClient, /def turn_off_vpn\(self\):[\s\S]*?TASK_VPN, 1, 0/);
assert.match(pythonClient, /def is_vpn_on\(self\):[\s\S]*?TASK_VPN, 0/);

const trollPolicyObject = JSON.parse(trollPolicy);
assert.ok(
  trollPolicyObject.task_features?.automation?.includes(59),
  "TrollStore task 59 must remain covered by the automation license gate",
);
assert.match(rootfullPolicy, /\{59, "automation"\}/);

const common = fixture.requiredCommonCapabilityFields;
const rootfull = { ...common, ...fixture.requiredRuntimeCapabilityFields.rootfull };
const trollstore = { ...common, ...fixture.requiredRuntimeCapabilityFields.trollstore };

for (const [key, value] of Object.entries(rootfull)) {
  assert.ok(rootfullServer.includes(`${key}=${value}`), `rootfull task 97 is missing ${key}=${value}`);
}
for (const [key, value] of Object.entries(trollstore)) {
  assert.ok(trollServer.includes(`${key}=${value}`), `TrollStore task 97 is missing ${key}=${value}`);
}

const rootfullTask60Fields = {
  vpn_contract_version: "@1",
  legacy_task: "@59",
  profile_scope: '@"tlink_owned_only"',
  configuration_transport: '@"local_ui_keychain_only"',
  credentials_over_task59: "@0",
};
for (const [key, value] of Object.entries(rootfullTask60Fields)) {
  assert.ok(
    sharedVPN.includes(`@"${key}": ${value}`),
    `rootfull task 60 is missing vpn.${key}=${value}`,
  );
}
assert.match(
  rootfullTask,
  /@"vpn": TLinkVPNDiagnosticsSnapshot\([\s\S]*?@"rootfull"[\s\S]*?@"unavailable"[\s\S]*?@"unsupported"[\s\S]*?@"unsupported"[\s\S]*?@"stub"[\s\S]*?@"not_implemented"/,
);
const trollTask60Fields = {
  vpnContractVersion: "@1",
  vpnLegacyTask: "@59",
  vpnState: '@"query_only"',
  vpnQuery: '@"interface_probe"',
  vpnControl: '@"unsupported"',
  vpnBackend: '@"interface_probe"',
  vpnBroker: '@"not_implemented"',
  vpnProfileScope: '@"tlink_owned_only"',
  vpnConfigurationTransport: '@"local_ui_keychain_only"',
  vpnCredentialsOverTask59: "@(NO)",
};
for (const [key, value] of Object.entries(trollTask60Fields)) {
  assert.ok(
    trollServer.includes(`@"${key}": ${value}`),
    `TrollStore task 60 is missing capabilities.${key}=${value}`,
  );
}

assert.match(baselineDoc, /does not add a Network Extension entitlement/i);
assert.match(baselineDoc, /must never be accepted[\s\S]*through task `59`/i);
assert.match(baselineDoc, /success means the requested terminal state was observed/i);
assert.match(trollStatusDoc, /VPN P0/);
assert.match(plan, /VPN P0/);

const forbiddenFixtureKeys = /password|sharedSecret|privateKey|certificateData|serverAddress|username/i;
function assertNoSecretFields(value, path = "fixture") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoSecretFields(item, `${path}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      assert.ok(!forbiddenFixtureKeys.test(key), `${path}.${key} must not define VPN secret/config input`);
      assertNoSecretFields(child, `${path}.${key}`);
    }
  }
}
assertNoSecretFields(fixture);

console.log("VPN P0 baseline OK: task 59 contract v1 and rootfull/TrollStore capability baseline frozen");
