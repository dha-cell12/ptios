import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    const name = argv[i];
    const value = argv[i + 1];
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
    return execFileSync(
      "/usr/bin/plutil",
      ["-convert", "xml1", "-o", "-", path],
      { encoding: "utf8" }
    );
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
const output = resolve(args.output || `rootfull-license-phase2-${mode}.json`);
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
  "Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib"
];
const verifierBinaries = new Set([
  "Applications/TLinkauto.app/TLinkauto",
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib"
]);
const hashes = {};
for (const relative of binaries) {
  const bytes = await readFile(join(rootfs, relative));
  const content = bytes.toString("latin1");
  assert.ok(content.includes(rootfullMarker), `${relative} lacks ${rootfullMarker}`);
  assert.ok(!content.includes(wrongRootfullMarker), `${relative} contains ${wrongRootfullMarker}`);
  if (verifierBinaries.has(relative)) {
    assert.ok(content.includes(verifierMarker), `${relative} lacks verifier marker ${verifierMarker}`);
    assert.ok(!content.includes(wrongVerifierMarker), `${relative} contains ${wrongVerifierMarker}`);
    assert.ok(content.includes("license_device_key_mismatch"), `${relative} lacks shared verifier evidence`);
  }
  if (relative === "Applications/TLinkauto.app/TLinkauto") {
    for (const evidence of [
      "/v1/challenge",
      "/v1/activate",
      "/v1/refresh",
      "/v1/deactivate",
      "license_request_in_progress",
      "Deactivate This Device"
    ]) {
      assert.ok(content.includes(evidence), `${relative} lacks Phase 2 lifecycle evidence ${evidence}`);
    }
  }
  hashes[relative] = createHash("sha256").update(bytes).digest("hex");
}

const app = join(rootfs, "Applications/TLinkauto.app");
const buildPlistPath = join(app, "RootfullLicenseBuild.plist");
const licenseConfigPath = join(app, "LicenseConfig.plist");
const buildXML = plistXML(buildPlistPath) || await readFile(buildPlistPath, "utf8");
const configXML = plistXML(licenseConfigPath) || await readFile(licenseConfigPath, "utf8");

assert.equal(plistValue(buildXML, "RootfullLicensePhase"), 2);
assert.equal(plistValue(buildXML, "RootfullLicenseMode"), mode);
assert.equal(plistValue(buildXML, "LicenseContractVersion"), 1);
assert.equal(
  plistValue(buildXML, "EnforcementBehavior"),
  "activation_lifecycle_observe_no_runtime_gate"
);

const expectedConfig = {
  LicenseEndpoint: args.endpoint,
  LicenseKeyID: args.keyId,
  LicensePublicKeyX: args.publicKeyX,
  LicensePublicKeyY: args.publicKeyY,
  LicenseEnforcementEnabled: mode === "enforced"
};
for (const [key, value] of Object.entries(expectedConfig)) {
  assert.notEqual(value, undefined, `missing expected value for ${key}`);
  assert.equal(plistValue(configXML, key), value, `artifact ${key} does not match CI input`);
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
  "\"key_ops\":[\"sign\"]"
];
for (const path of await listFiles(rootfs)) {
  const content = (await readFile(path)).toString("latin1");
  for (const token of forbidden) {
    assert.ok(!content.includes(token), `${basename(path)} contains forbidden secret marker ${token}`);
  }
}

const manifest = {
  schema_version: 1,
  product: "tlinkauto-rootfull",
  license_contract_version: 1,
  rootfull_license_phase: 2,
  license_mode: mode,
  integration_mode: "activation_lifecycle_observe_no_runtime_gate",
  activation_ui_active: true,
  automatic_refresh_active: true,
  runtime_gate_active: false,
  compile_markers: {
    rootfull: rootfullMarker,
    verifier: verifierMarker
  },
  config: expectedConfig,
  binaries_sha256: hashes,
  secret_scan: "passed"
};
await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`rootfull phase 2 artifact OK: ${mode}, manifest ${output}`);
