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

function signedEntitlements(path) {
  return execFileSync("ldid", ["-e", path], {
    encoding: "utf8",
  });
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
const output = resolve(args.output || `rootfull-license-phase6-${mode}.json`);
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
  "usr/libexec/tlinkauto-vpnd",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
  "Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib",
];
const verifierBinaries = new Set([
  "Applications/TLinkauto.app/TLinkauto",
  "usr/bin/tlinkautod",
  "usr/bin/tlinkautob",
  "usr/libexec/tlinkauto-jsd",
  "usr/libexec/tlinkauto-vpnd",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib",
]);
const evidence = {
  "Applications/TLinkauto.app/TLinkauto": [
    "rootfull_ui_memory_snapshot",
    "Release Integrity",
    "Anti-Rollback",
    "signed_device_checkpoint_v1",
  ],
  "usr/bin/tlinkautod": [
    "license_phase=6",
    "releaseIntegrity=1",
    "antiRollback=1",
    "tlinkautod_rootfull_phase6_release_hardened",
    "h264HeartbeatMs=5000",
    "scriptHeartbeatMs=1000",
  ],
  "usr/libexec/tlinkauto-jsd": [
    "script_helper_start",
    "license_revoked_during_execution",
    "signed_device_checkpoint_v1",
  ],
  "usr/libexec/tlinkauto-vpnd": [
    "vpn_license_denied",
    "tlinkauto-managed-v1",
    "signed_device_checkpoint_v1",
  ],
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib": [
    "active client closed by license",
    "scheduler launch blocked by license",
    "release_integrity_active",
    "anti_rollback_active",
  ],
};

const hashes = {};
for (const relative of binaries) {
  const bytes = await readFile(join(rootfs, relative));
  const content = bytes.toString("latin1");
  assert.ok(content.includes(rootfullMarker), `${relative} lacks ${rootfullMarker}`);
  assert.ok(!content.includes(wrongRootfullMarker), `${relative} contains ${wrongRootfullMarker}`);
  if (verifierBinaries.has(relative)) {
    assert.ok(content.includes(verifierMarker), `${relative} lacks ${verifierMarker}`);
    assert.ok(!content.includes(wrongVerifierMarker), `${relative} contains ${wrongVerifierMarker}`);
    for (const marker of [
      "license_device_key_mismatch",
      "rootfull_release_integrity_v1",
      "license_release_integrity_failed",
      "signed_device_checkpoint_v1",
      "license_lease_rollback_detected",
    ]) {
      assert.ok(content.includes(marker), `${relative} lacks verifier evidence ${marker}`);
    }
  }
  for (const marker of evidence[relative] || []) {
    assert.ok(content.includes(marker), `${relative} lacks Phase 6 evidence ${marker}`);
  }
  hashes[relative] = createHash("sha256").update(bytes).digest("hex");
}

const app = join(rootfs, "Applications/TLinkauto.app");
const allowVPNMarker = "com.apple.developer.networking.vpn.api";
for (const relative of [
  "Applications/TLinkauto.app/TLinkauto",
  "usr/libexec/tlinkauto-vpnd",
]) {
  const entitlements = signedEntitlements(join(rootfs, relative));
  assert.ok(
    entitlements.includes(allowVPNMarker) &&
      entitlements.includes("allow-vpn"),
    `${relative} is missing the signed allow-vpn entitlement`,
  );
}
const shortcutEntitlements = signedEntitlements(
  join(rootfs,
    "Applications/TLinkauto.app/PlugIns/shortcutext.appex/shortcutext"),
);
assert.ok(
  !shortcutEntitlements.includes(allowVPNMarker) &&
    !shortcutEntitlements.includes("com.apple.developer.networking.networkextension"),
  "shortcut extension must not inherit VPN entitlements",
);

const buildPlistPath = join(app, "RootfullLicenseBuild.plist");
const configPath = join(app, "LicenseConfig.plist");
const buildXML = plistXML(buildPlistPath) || await readFile(buildPlistPath, "utf8");
const configXML = plistXML(configPath) || await readFile(configPath, "utf8");

assert.equal(plistValue(buildXML, "RootfullLicensePhase"), 6);
assert.equal(plistValue(buildXML, "RootfullLicenseMode"), mode);
assert.equal(plistValue(buildXML, "LicenseContractVersion"), 1);
assert.equal(
  plistValue(buildXML, "EnforcementBehavior"),
  "task_and_long_running_component_gate"
);
assert.equal(plistValue(buildXML, "ReleaseIntegrityVersion"), 1);
assert.equal(
  plistValue(buildXML, "AntiRollbackPolicy"),
  "signed_device_checkpoint_v1"
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
  rootfull_license_phase: 6,
  license_mode: mode,
  integration_mode: "task_and_long_running_component_gate",
  runtime_gate_active: true,
  runtime_gate_enforcing: mode === "enforced",
  application_ui_feature_snapshot_active: true,
  release_integrity: {
    active: true,
    enforced_failure_mode: "fail_closed",
    version: 1,
  },
  anti_rollback: {
    active: true,
    policy: "signed_device_checkpoint_v1",
    device_signature: "ECDSA_P256",
    clock_rollback_tolerance_seconds: 300,
  },
  long_running_gate_heartbeat_ms: {
    h264: 5000,
    script: 1000,
    script_helper: 1000,
  },
  release_evidence_required: [
    "device_regression",
    "24_hour_online_soak",
    "72_hour_offline_grace_soak",
  ],
  deferred_phase7: [
    "client_authenticated_transport",
    "selective_ollvm",
    "checkpoint_deletion_telemetry",
  ],
  compile_markers: { rootfull: rootfullMarker, verifier: verifierMarker },
  config: expectedConfig,
  binaries_sha256: hashes,
  secret_scan: "passed",
};
await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`rootfull phase 6 artifact OK: ${mode}, manifest ${output}`);
