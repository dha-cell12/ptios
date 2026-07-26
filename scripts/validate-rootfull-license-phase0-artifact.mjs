import assert from "node:assert/strict";
import { createHash } from "node:crypto";
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
const output = resolve(args.output || `rootfull-license-phase0-${mode}.json`);
assert.ok(mode === "observe" || mode === "enforced", "mode must be observe or enforced");

const expectedMarker = `rootfull_${mode}_compile_time_v1`;
const unexpectedMarker = mode === "enforced"
  ? "rootfull_observe_compile_time_v1"
  : "rootfull_enforced_compile_time_v1";
const binaries = [
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "usr/libexec/tlinkauto-jsd",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
  "Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib"
];
const hashes = {};
for (const relative of binaries) {
  const bytes = await readFile(join(rootfs, relative));
  const content = bytes.toString("latin1");
  assert.ok(content.includes(expectedMarker), `${relative} lacks ${expectedMarker}`);
  assert.ok(!content.includes(unexpectedMarker), `${relative} contains ${unexpectedMarker}`);
  hashes[relative] = createHash("sha256").update(bytes).digest("hex");
}

const appManifest = await readFile(
  join(rootfs, "Applications/TLinkauto.app/RootfullLicenseBuild.plist"),
  "utf8"
);
assert.match(appManifest, new RegExp(`<string>${mode}</string>`));
assert.match(appManifest, /<key>RootfullLicensePhase<\/key>\s*<integer>0<\/integer>/);
assert.match(appManifest, /<key>LicenseContractVersion<\/key>\s*<integer>1<\/integer>/);

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
  rootfull_license_phase: 0,
  license_mode: mode,
  enforcement_behavior: "marker_only_no_runtime_gate",
  compile_marker: expectedMarker,
  binaries_sha256: hashes,
  secret_scan: "passed"
};
await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`rootfull phase 0 artifact OK: ${mode}, manifest ${output}`);
