import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/vpn-diagnostics-contract-v1.json"));

assert.equal(fixture.diagnosticsVersion, 1);
assert.equal(fixture.request, "592\r\n");
assert.equal(fixture.responsePrefix, "0;;");
assert.equal(fixture.encoding, "base64-json");
assert.equal(fixture.profileIdentifier, "tlinkauto-managed-v1");

const sampleBase64 = Buffer.from(
  JSON.stringify({
    ...fixture.requiredTopLevelFields,
    ...fixture.samples.trollstore,
    entitlements: Object.fromEntries(
      fixture.requiredEntitlementFields.map((field) => [field, field.endsWith("values") ? [] : 0]),
    ),
    network_extension: Object.fromEntries(
      fixture.requiredNetworkExtensionFields.map((field) => [field, 0]),
    ),
    control_preflight: "blocked_missing_entitlement_or_framework",
    generated_at_ms: 1,
  }),
  "utf8",
).toString("base64");
const decodedSample = JSON.parse(Buffer.from(sampleBase64, "base64").toString("utf8"));
for (const [key, value] of Object.entries(fixture.requiredTopLevelFields)) {
  assert.deepEqual(decodedSample[key], value, `sample diagnostics changed ${key}`);
}
for (const key of fixture.requiredRuntimeFields) {
  assert.ok(Object.hasOwn(decodedSample, key), `sample diagnostics is missing ${key}`);
}

const [
  sharedHeader,
  sharedImplementation,
  rootfullMakefile,
  trollMakefile,
  rootfullConnectivity,
  rootfullTask,
  rootfullServer,
  trollServer,
  appEntitlements,
  streamdEntitlements,
  p0Checker,
  p1Doc,
  statusDoc,
  plan,
] = await Promise.all([
  read("shared/TLinkVPNDiagnostics.h"),
  read("shared/TLinkVPNDiagnostics.mm"),
  read("pccontrol/Makefile"),
  read("stream-app/streamd/Makefile"),
  read("pccontrol/Connectivity.xm"),
  read("pccontrol/Task.xm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/app/entitlements.plist"),
  read("stream-app/streamd/entitlements.plist"),
  read("scripts/check-vpn-p0-baseline.mjs"),
  read("docs/vpn-p1-diagnostics.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
]);

assert.match(sharedHeader, /TLinkVPNDiagnosticsSnapshot/);
assert.match(sharedHeader, /TLinkVPNDiagnosticsBase64/);
assert.match(sharedImplementation, /SecTaskCopyValueForEntitlement/);
assert.match(sharedImplementation, /com\.apple\.developer\.networking\.vpn\.api/);
assert.match(sharedImplementation, /com\.apple\.developer\.networking\.networkextension/);
assert.match(sharedImplementation, /NetworkExtension\.framework\/NetworkExtension/);
assert.match(sharedImplementation, /NSClassFromString\(@"NEVPNManager"\)/);
assert.match(sharedImplementation, /@"api_exercised": @0/);
assert.match(sharedImplementation, /@"entitlement_probe_scope": @"current_process_only"/);
assert.match(sharedImplementation, /@"profile_identifier": TLinkVPNManagedProfileIdentifier\(\)/);
assert.doesNotMatch(sharedImplementation, /startVPNTunnel|stopVPNTunnel|saveToPreferences|loadAllFromPreferences/);

assert.match(rootfullMakefile, /\.\.\/shared\/TLinkVPNDiagnostics\.mm/);
assert.match(trollMakefile, /\.\.\/\.\.\/shared\/TLinkVPNDiagnostics\.mm/);

assert.match(
  rootfullConnectivity,
  /if \(action == 2\)[\s\S]*?TLinkVPNDiagnosticsBase64\([\s\S]*?@"rootfull"/,
);
assert.match(
  trollServer,
  /if \(requestedAction == 2\)[\s\S]*?TLinkVPNDiagnosticsBase64\([\s\S]*?@"trollstore"/,
);
assert.match(rootfullConnectivity, /vpn_diagnostics_takes_no_arguments/);
assert.match(trollServer, /vpn_diagnostics_takes_no_arguments/);
assert.match(rootfullTask, /@"vpn": TLinkVPNDiagnosticsSnapshot\(/);
assert.match(trollServer, /@"vpn_diagnostics": TLinkVPNDiagnosticsSnapshot\(/);

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(rootfullServer.includes(`${key}=${value}`), `rootfull task 97 is missing ${key}=${value}`);
  assert.ok(trollServer.includes(`${key}=${value}`), `TrollStore task 97 is missing ${key}=${value}`);
}

for (const key of Object.keys(fixture.requiredTopLevelFields)) {
  const sourceKey = `@"${key}"`;
  assert.ok(sharedImplementation.includes(sourceKey), `shared diagnostics is missing ${key}`);
}
for (const key of fixture.requiredEntitlementFields) {
  assert.ok(sharedImplementation.includes(`@"${key}"`), `shared entitlement probe is missing ${key}`);
}
for (const key of fixture.requiredNetworkExtensionFields) {
  assert.ok(sharedImplementation.includes(`@"${key}"`), `shared framework probe is missing ${key}`);
}

for (const activeEntitlements of [appEntitlements, streamdEntitlements]) {
  assert.ok(
    !activeEntitlements.includes("com.apple.developer.networking.vpn.api"),
    "P1 must not enable allow-vpn in a production entitlement file",
  );
  assert.ok(
    !activeEntitlements.includes("com.apple.developer.networking.networkextension"),
    "P1 must not enable Network Extension providers in production",
  );
}

assert.match(p0Checker, /vpn-wire-contract-v1\.json/);
assert.match(p1Doc, /current_process_only/);
assert.match(p1Doc, /does not add production VPN entitlements/i);
assert.match(statusDoc, /VPN P1/);
assert.match(plan, /VPN P1/);

const forbidden = /server_address|username|password|shared_secret|private_key|certificate_data|provider_configuration/i;
for (const value of [
  JSON.stringify(fixture),
  sampleBase64,
  sharedImplementation,
]) {
  assert.ok(!forbidden.test(value), "VPN diagnostics must not contain secret/config fields");
}

console.log("VPN P1 diagnostics OK: shared action 2 schema, entitlement probe and no-control boundary enforced");
