import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    assert.ok(name?.startsWith("--") && value, `invalid argument near ${name || "end"}`);
    result[name.slice(2)] = value;
  }
  return result;
}

function decodeXML(value) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'");
}

function plistValue(xml, key) {
  const marker = `<key>${key}</key>`;
  const index = xml.indexOf(marker);
  assert.ok(index >= 0, `plist is missing ${key}`);
  const tail = xml.slice(index + marker.length).trimStart();
  const stringMatch = tail.match(/^<string>([\s\S]*?)<\/string>/);
  if (stringMatch) return decodeXML(stringMatch[1]);
  const integerMatch = tail.match(/^<integer>(\d+)<\/integer>/);
  if (integerMatch) return Number(integerMatch[1]);
  if (tail.startsWith("<true/>")) return true;
  if (tail.startsWith("<false/>")) return false;
  throw new Error(`unsupported plist value for ${key}`);
}

function plistXML(path) {
  try {
    return execFileSync("/usr/bin/plutil", ["-convert", "xml1", "-o", "-", path], {
      encoding: "utf8",
    });
  } catch {
    return null;
  }
}

async function listFiles(path) {
  const output = [];
  for (const name of await readdir(path)) {
    const child = join(path, name);
    const info = await stat(child);
    if (info.isDirectory()) output.push(...await listFiles(child));
    else if (info.isFile()) output.push(child);
  }
  return output;
}

const args = parseArgs(process.argv.slice(2));
const rootfs = resolve(args.rootfs || "");
const mode = args.mode;
const output = resolve(args.output || `rootfull-license-phase3-${mode}.json`);
assert.ok(mode === "observe" || mode === "enforced", "mode must be observe or enforced");

const rootfullMarker = `rootfull_${mode}_compile_time_v1`;
const wrongRootfullMarker = mode === "enforced"
  ? "rootfull_observe_compile_time_v1"
  : "rootfull_enforced_compile_time_v1";
const verifierMarker = `${mode}_compile_time_v1`;
const wrongVerifierMarker = mode === "enforced"
  ? "observe_compile_time_v1"
  : "enforced_compile_time_v1";

const binaries = [
  "Applications/TLinkauto.app/TLinkauto",
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "usr/libexec/tlinkauto-jsd",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
  "Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib",
];
const verifierBinaries = new Set([
  "Applications/TLinkauto.app/TLinkauto",
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
]);
const taskGateBinaries = new Set([
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
]);
const hashes = {};
for (const relative of binaries) {
  const bytes = await readFile(join(rootfs, relative));
  const content = bytes.toString("latin1");
  assert.ok(content.includes(rootfullMarker), `${relative} lacks ${rootfullMarker}`);
  assert.ok(!content.includes(wrongRootfullMarker), `${relative} contains ${wrongRootfullMarker}`);
  if (verifierBinaries.has(relative)) {
    assert.ok(content.includes(verifierMarker), `${relative} lacks ${verifierMarker}`);
    assert.ok(!content.includes(wrongVerifierMarker), `${relative} contains ${wrongVerifierMarker}`);
    assert.ok(content.includes("license_device_key_mismatch"), `${relative} lacks verifier evidence`);
  }
  if (taskGateBinaries.has(relative)) {
    assert.ok(content.includes("license_policy_missing task="), `${relative} lacks fail-closed policy`);
    assert.ok(content.includes("license_required %@ feature=%@ state=%@ error=%@"),
      `${relative} lacks deny contract`);
  }
  if (relative === "usr/bin/tlinkautod" || relative.endsWith("/pccontrol.dylib")) {
    assert.ok(content.includes("task_server_and_springboard_feature_gate"),
      `${relative} lacks Phase 3 scope`);
    assert.ok(content.includes("rootfull_explicit_v1"), `${relative} lacks task policy marker`);
  }
  if (relative === "Applications/TLinkauto.app/TLinkauto") {
    for (const evidence of [
      "/v1/activate",
      "/v1/refresh",
      "Deactivate This Device",
      "License Required",
    ]) {
      assert.ok(content.includes(evidence), `${relative} lacks lifecycle evidence ${evidence}`);
    }
  }
  hashes[relative] = createHash("sha256").update(bytes).digest("hex");
}

const app = join(rootfs, "Applications/TLinkauto.app");
const buildPlistPath = join(app, "RootfullLicenseBuild.plist");
const configPath = join(app, "LicenseConfig.plist");
const buildXML = plistXML(buildPlistPath) || await readFile(buildPlistPath, "utf8");
const configXML = plistXML(configPath) || await readFile(configPath, "utf8");

assert.equal(plistValue(buildXML, "RootfullLicensePhase"), 3);
assert.equal(plistValue(buildXML, "RootfullLicenseMode"), mode);
assert.equal(plistValue(buildXML, "LicenseContractVersion"), 1);
assert.equal(
  plistValue(buildXML, "EnforcementBehavior"),
  "task_server_and_springboard_feature_gate"
);

const expectedConfig = {
  LicenseEndpoint: args.endpoint,
  LicenseKeyID: args.keyId,
  LicensePublicKeyX: args.publicKeyX,
  LicensePublicKeyY: args.publicKeyY,
  LicenseEnforcementEnabled: mode === "enforced",
};
for (const [key, value] of Object.entries(expectedConfig)) {
  assert.notEqual(value, undefined, `missing expected value for ${key}`);
  assert.equal(plistValue(configXML, key), value, `artifact ${key} differs from CI input`);
}
assert.match(expectedConfig.LicenseEndpoint, /^https:\/\//);
assert.doesNotMatch(expectedConfig.LicenseEndpoint, /REPLACE_|localhost|127\.0\.0\.1/i);
assert.match(expectedConfig.LicensePublicKeyX, /^[A-Za-z0-9_-]{43}$/);
assert.match(expectedConfig.LicensePublicKeyY, /^[A-Za-z0-9_-]{43}$/);

const forbidden = [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY",
  '"key_ops":["sign"]',
];
for (const path of await listFiles(rootfs)) {
  const content = (await readFile(path)).toString("latin1");
  for (const token of forbidden) {
    assert.ok(!content.includes(token), `${basename(path)} contains forbidden secret ${token}`);
  }
}

const manifest = {
  schema_version: 1,
  product: "tlinkauto-rootfull",
  license_contract_version: 1,
  rootfull_license_phase: 3,
  license_mode: mode,
  integration_mode: "task_server_and_springboard_feature_gate",
  activation_ui_active: true,
  automatic_refresh_active: true,
  runtime_gate_active: true,
  runtime_gate_enforcing: mode === "enforced",
  task_policy: "rootfull_explicit_v1",
  gated_components: ["tlinkautod", "tlinkautob", "pccontrol"],
  deferred_phase4: ["h264_active_session", "script_heartbeat", "helper_dispatch"],
  compile_markers: {
    rootfull: rootfullMarker,
    verifier: verifierMarker,
  },
  config: expectedConfig,
  binaries_sha256: hashes,
  secret_scan: "passed",
};
await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`rootfull phase 3 artifact OK: ${mode}, manifest ${output}`);
