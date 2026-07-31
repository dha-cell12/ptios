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
  assert.ok(index >= 0, `LicenseConfig.plist is missing ${key}`);
  const tail = xml.slice(index + marker.length).trimStart();
  const stringMatch = tail.match(/^<string>([\s\S]*?)<\/string>/);
  if (stringMatch) return decodeXML(stringMatch[1]);
  if (tail.startsWith("<true/>")) return true;
  if (tail.startsWith("<false/>")) return false;
  throw new Error(`unsupported plist value for ${key}`);
}

async function hashFile(path) {
  const data = await readFile(path);
  return createHash("sha256").update(data).digest("hex");
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
const app = resolve(args.app || "");
const tipa = resolve(args.tipa || "");
const mode = args.mode;
const output = resolve(args.output || `license-build-${mode}.json`);
assert.ok(mode === "observe" || mode === "enforced", "mode must be observe or enforced");

const expected = {
  LicenseEndpoint: args.endpoint,
  LicenseKeyID: args.keyId,
  LicensePublicKeyX: args.publicKeyX,
  LicensePublicKeyY: args.publicKeyY,
  LicenseEnforcementEnabled: mode === "enforced",
};
for (const [key, value] of Object.entries(expected)) {
  assert.notEqual(value, undefined, `missing expected value for ${key}`);
}

const configPath = join(app, "LicenseConfig.plist");
let configXML;
try {
  configXML = execFileSync("/usr/bin/plutil", ["-convert", "xml1", "-o", "-", configPath], { encoding: "utf8" });
} catch {
  configXML = await readFile(configPath, "utf8");
}
for (const [key, value] of Object.entries(expected)) {
  assert.equal(plistValue(configXML, key), value, `artifact ${key} does not match the CI input`);
}
assert.match(expected.LicenseEndpoint, /^https:\/\//, "license endpoint must use HTTPS");
assert.doesNotMatch(expected.LicenseEndpoint, /REPLACE_|localhost|127\.0\.0\.1/i, "license endpoint is a placeholder or local address");
assert.doesNotMatch(expected.LicenseKeyID, /REPLACE_/i, "license key id is a placeholder");
assert.match(expected.LicensePublicKeyX, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public key X");
assert.match(expected.LicensePublicKeyY, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public key Y");

const executables = ["StreamControl", "streamd", "clipboardd", "privhelper"];
const expectedMarker = mode === "enforced" ? "enforced_compile_time_v1" : "observe_compile_time_v1";
const unexpectedMarker = mode === "enforced" ? "observe_compile_time_v1" : "enforced_compile_time_v1";
const executableHashes = {};
for (const name of executables) {
  const path = join(app, name);
  const bytes = await readFile(path);
  const binary = bytes.toString("latin1");
  assert.ok(binary.includes(expectedMarker), `${name} lacks ${expectedMarker}`);
  assert.ok(!binary.includes(unexpectedMarker), `${name} unexpectedly contains ${unexpectedMarker}`);
  executableHashes[name] = createHash("sha256").update(bytes).digest("hex");
}

const appBinary = (await readFile(join(app, "StreamControl"))).toString("latin1");
const streamdBinary = (await readFile(join(app, "streamd"))).toString("latin1");
assert.ok(appBinary.includes("serviceVersion=23"), "StreamControl does not require service v23");
assert.ok(streamdBinary.includes("serviceVersion=23"), "streamd does not expose service v23");
assert.ok(appBinary.includes("StreamControl_app_6015"), "StreamControl lacks VPN P3 foreground broker evidence");
assert.ok(streamdBinary.includes("vpn_foreground_app_required"), "streamd lacks VPN P3 broker routing evidence");

const appEntitlements = execFileSync("ldid", ["-e", join(app, "StreamControl")], { encoding: "utf8" });
const streamdEntitlements = execFileSync("ldid", ["-e", join(app, "streamd")], { encoding: "utf8" });
assert.ok(
  appEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    appEntitlements.includes("allow-vpn"),
  "StreamControl is missing the signed allow-vpn entitlement",
);
assert.ok(
  appEntitlements.includes("keychain-access-groups") &&
    appEntitlements.includes("StreamCtl.com.tlinkauto.streamcontrol"),
  "StreamControl is missing the TrollStore VPN Keychain group",
);
assert.ok(
  !streamdEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    !streamdEntitlements.includes("com.apple.developer.networking.networkextension"),
  "streamd must not inherit VPN or packet-tunnel entitlements",
);

const forbidden = [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY",
  '"key_ops":["sign"]',
];
for (const path of await listFiles(app)) {
  const content = (await readFile(path)).toString("latin1");
  for (const token of forbidden) {
    assert.ok(!content.includes(token), `${basename(path)} contains forbidden secret marker ${token}`);
  }
}

const manifest = {
  schema_version: 1,
  product: "tlinkauto-trollstore",
  license_contract_version: 1,
  license_mode: mode,
  compile_marker: expectedMarker,
  service_version: 23,
  vpn_phase: 3,
  config: {
    endpoint: expected.LicenseEndpoint,
    key_id: expected.LicenseKeyID,
    public_key_x: expected.LicensePublicKeyX,
    public_key_y: expected.LicensePublicKeyY,
    enforcement_enabled: expected.LicenseEnforcementEnabled,
  },
  sha256: {
    tipa: await hashFile(tipa),
    license_config: await hashFile(configPath),
    executables: executableHashes,
  },
  secret_scan: "passed",
};

await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`license artifact OK: ${mode}, service v23, manifest ${output}`);
