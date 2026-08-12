import assert from "node:assert/strict";
import { createCipheriv, hkdfSync } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/secure-pairing-contract-v1.json"));

assert.equal(fixture.phase, 0);
assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.state, "contract_only");
assert.equal(fixture.enforcement, "observe_only");
assert.equal(fixture.deviceValidated, false);

assert.deepEqual(fixture.baseline.rootfull.taskProtocols, ["legacy_line_v0", "zxtp_json_v1"]);
assert.deepEqual(fixture.baseline.trollstore.taskProtocols, ["legacy_line_v0"]);
for (const runtime of [fixture.baseline.rootfull, fixture.baseline.trollstore]) {
  assert.equal(runtime.taskEndpoint, "tcp://0.0.0.0:6000");
  assert.equal(runtime.peerAuthentication, false);
  assert.equal(runtime.confidentiality, false);
  assert.equal(runtime.replayProtection, false);
}
assert.equal(fixture.baseline.licenseIsPeerAuthentication, false);
assert.deepEqual(fixture.baseline.streamPorts, [7001, 7002, 7003, 7004, 7005, 7006]);

for (const key of ["assets", "trustBoundaries", "adversaryCapabilities", "requiredSecurityProperties", "outOfScope"]) {
  assert.ok(Array.isArray(fixture.threatModel[key]) && fixture.threatModel[key].length >= 4,
    `threat model ${key} is incomplete`);
}
assert.ok(fixture.threatModel.requiredSecurityProperties.includes("replay_and_downgrade_resistance"));
assert.ok(fixture.threatModel.trustBoundaries.includes("license_worker_entitlement_not_peer_identity"));

assert.deepEqual(fixture.outerFrame, {
  magicAscii: "ZXSP",
  version: 1,
  headerBytes: 12,
  byteOrder: "big_endian",
  fields: [
    { name: "magic", offset: 0, bytes: 4 },
    { name: "version", offset: 4, bytes: 1 },
    { name: "message_type", offset: 5, bytes: 1 },
    { name: "flags", offset: 6, bytes: 2 },
    { name: "body_length", offset: 8, bytes: 4 },
  ],
  bodyEncoding: "utf8_json",
  binaryEncoding: "base64url_no_padding",
  maximumHandshakeBodyBytes: 65536,
  maximumFrameBodyBytes: 1048576,
  unknownVersionAction: "error_then_close",
  malformedFrameAction: "close",
  legacyFallbackAfterMagic: false,
});
assert.deepEqual(fixture.messageTypes, {
  "pair.begin": 1,
  "pair.challenge": 2,
  "pair.finish": 3,
  "pair.complete": 4,
  "session.open": 16,
  "session.accept": 17,
  "secure.data": 32,
  "secure.close": 33,
  error: 127,
});

assert.equal(fixture.pairing.bootstrapTransport, "local_ui_qr_or_copy_only");
assert.equal(fixture.pairing.setupSecretBytes, 32);
assert.equal(fixture.pairing.pairingIdBytes, 16);
assert.equal(fixture.pairing.nonceBytes, 32);
assert.equal(fixture.pairing.windowSeconds, 120);
assert.equal(fixture.pairing.singleUse, true);
assert.equal(fixture.pairing.requiresLocalApproval, true);
assert.equal(fixture.pairing.networkMayOpenPairingWindow, false);
assert.equal(fixture.pairing.maximumPendingAttemptsPerWindow, 5);
assert.equal(fixture.pairing.publicKeyEncoding, "p256_x963_uncompressed_65_bytes");
assert.equal(fixture.pairing.signatureEncoding, "ecdsa_p256_sha256_ieee_p1363_64_bytes");
assert.equal(fixture.pairing.jsonCanonicalization, "rfc8785_jcs");
assert.equal(fixture.pairing.pairKey.primitive, "hkdf_sha256");
assert.equal(fixture.pairing.pairKey.lengthBytes, 32);
assert.match(fixture.pairing.transcript, /pair_challenge_without_proofs$/);
assert.deepEqual(fixture.pairing.proofRoleLabels, {
  device: "TLINK-SP-V1-DEVICE\\0",
  client: "TLINK-SP-V1-CLIENT\\0",
  complete: "TLINK-SP-V1-COMPLETE\\0",
});
assert.match(fixture.pairing.completeProofInput, /pair_complete_without_complete_proof$/);
assert.equal(fixture.pairing.storage.setupSecret, "memory_only_zeroize_on_close");

const requiredPairFields = {
  pairBeginFields: ["v", "type", "pairing_id", "client_name", "client_identity_key", "client_ephemeral_key", "client_nonce", "requested_scopes"],
  pairChallengeFields: ["v", "type", "pairing_id", "device_id", "device_identity_key", "device_ephemeral_key", "device_nonce", "granted_scopes", "expires_at", "device_signature", "device_proof"],
  pairFinishFields: ["v", "type", "pairing_id", "client_signature", "client_proof"],
  pairCompleteFields: ["v", "type", "pairing_id", "client_id", "granted_scopes", "completed_at", "complete_proof"],
};
for (const [key, fields] of Object.entries(requiredPairFields)) assert.deepEqual(fixture.pairing[key], fields);

assert.equal(fixture.session.authentication, "mutual_ecdsa_p256_identity_signatures");
assert.equal(fixture.session.forwardSecrecy, "fresh_p256_ephemeral_ecdh_per_session");
assert.equal(fixture.session.kdf, "hkdf_sha256");
assert.equal(fixture.session.keyMaterialBytes, 72);
assert.equal(fixture.session.aead, "aes_256_gcm");
assert.equal(fixture.session.tagBytes, 16);
assert.equal(fixture.session.initialSequence, "0");
assert.equal(fixture.session.sequencePolicy, "strict_contiguous_per_direction_close_on_duplicate_or_gap");
assert.equal(fixture.session.maximumAgeSeconds, 28800);
assert.equal(fixture.session.maximumFramesPerDirection, 4294967296);
assert.equal(fixture.session.maximumPlaintextBytes, 1000000);
assert.equal(fixture.session.compression, "forbidden_v1");
assert.deepEqual(fixture.session.sessionOpenFields,
  ["v", "type", "client_id", "client_ephemeral_key", "client_nonce", "timestamp", "client_signature"]);
assert.deepEqual(fixture.session.sessionAcceptFields,
  ["v", "type", "session_id", "device_ephemeral_key", "device_nonce", "expires_at", "granted_scopes", "device_signature"]);
assert.deepEqual(fixture.session.secureDataFields,
  ["v", "type", "session_id", "direction", "sequence", "ciphertext", "tag"]);
assert.match(fixture.session.clientOpenSignatureInput, /session_open_without_client_signature$/);
assert.match(fixture.session.deviceAcceptSignatureInput, /session_accept_without_device_signature$/);

assert.deepEqual(fixture.authorization.scopeVocabulary, ["observe", "automation", "stream", "script", "admin", "shell"]);
assert.equal(fixture.authorization.effectivePermission, "intersection_of_pairing_scope_and_license_feature");
assert.deepEqual(fixture.authorization.defaultRequestedScopes, ["observe"]);
assert.equal(fixture.authorization.scopeEscalation, "local_ui_reapproval_required");
assert.equal(fixture.migration.phase0, "contract_only_observe_no_behavior_change");
assert.deepEqual(fixture.migration.unauthenticatedAllowlistWhenEnforced, [97, 99]);
assert.equal(fixture.migration.silentDowngradeAfterSecureCapabilityObserved, false);
for (const error of ["pairing_window_closed", "session_replay", "bad_sequence", "decrypt_failed", "secure_pairing_required"]) {
  assert.ok(fixture.stableErrors.includes(error), `stable error missing: ${error}`);
}

const vector = fixture.testVectors.outerErrorFrame;
const body = Buffer.from(vector.bodyUtf8, "utf8");
const header = Buffer.alloc(fixture.outerFrame.headerBytes);
header.write(fixture.outerFrame.magicAscii, 0, "ascii");
header.writeUInt8(fixture.outerFrame.version, 4);
header.writeUInt8(vector.messageType, 5);
header.writeUInt16BE(vector.flags, 6);
header.writeUInt32BE(body.length, 8);
assert.equal(Buffer.concat([header, body]).toString("hex"), vector.frameHex,
  "ZXSP outer-frame vector changed");

const hkdf = fixture.testVectors.hkdfSha256Rfc5869Case1;
const okm = Buffer.from(hkdfSync(
  "sha256",
  Buffer.from(hkdf.ikmHex, "hex"),
  Buffer.from(hkdf.saltHex, "hex"),
  Buffer.from(hkdf.infoHex, "hex"),
  hkdf.length,
));
assert.equal(okm.toString("hex"), hkdf.okmHex, "HKDF-SHA256 reference vector changed");

const gcm = fixture.testVectors.aes256GcmEmpty;
const cipher = createCipheriv("aes-256-gcm", Buffer.from(gcm.keyHex, "hex"), Buffer.from(gcm.nonceHex, "hex"));
cipher.setAAD(Buffer.from(gcm.aadHex, "hex"));
const ciphertext = Buffer.concat([cipher.update(Buffer.from(gcm.plaintextHex, "hex")), cipher.final()]);
assert.equal(ciphertext.toString("hex"), gcm.ciphertextHex, "AES-256-GCM ciphertext vector changed");
assert.equal(cipher.getAuthTag().toString("hex"), gcm.tagHex, "AES-256-GCM tag vector changed");

const [rootHeader, rootServer, rootTask, trollHeader, trollServer, h264Root, h264Troll, remoteBridge,
  deviceTest, doc, trollStatus, plan, rootWorkflow, trollWorkflow] = await Promise.all([
  read("tlinkauto-binary/SocketServer.h"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("pccontrol/Task.xm"),
  read("stream-app/streamd/POCSocketServer.h"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("pccontrol/H264Stream.xm"),
  read("stream-app/streamd/H264Stream.mm"),
  read("stream-app/streamd/RemoteBridgeAgent.mm"),
  read("scripts/Test-TLinkSecurePairingPhase0.ps1"),
  read("docs/secure-pairing-p0-baseline.md"),
  read("docs/trollstore-runtime-status.md"),
  read("plan.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
]);

assert.match(rootHeader, /#define TLinkautoD_PORT 6000/);
assert.match(rootHeader, /#define TLinkautoD_ADDR "0\.0\.0\.0"/);
assert.match(trollHeader, /#define POC_SOCKET_PORT 6000/);
assert.match(trollHeader, /#define POC_SOCKET_ADDR "0\.0\.0\.0"/);
assert.match(rootServer, /kZXTPMagic\[4\].*'Z'.*'X'.*'T'.*'P'/);
assert.match(rootServer, /ZXWireProtocolLegacyV0/);
assert.match(trollServer, /if \(bytes\[i\] == '\\n'\) \{ nl = i; break; \}/);
assert.match(trollServer, /if \(nl == NSNotFound\) return; \/\/ wait for more data/);
assert.match(remoteBridge, /@"\/remote\/device\/control"/);
assert.match(remoteBridge, /Bearer /);
assert.match(remoteBridge, /isEqualToString:@"wss"/);
for (const [label, source] of [["rootfull", h264Root], ["TrollStore", h264Troll]]) {
  for (let port = 7001; port <= 7006; port++) assert.match(source, new RegExp(`\\.port = ${port}`), `${label} missing port ${port}`);
}

const capabilityFields = fixture.requiredCapabilityFields;
for (const [key, value] of Object.entries(capabilityFields)) {
  const marker = `${key}=${value}`;
  assert.ok(rootServer.includes(marker), `rootfull task 97 missing ${marker}`);
  assert.ok(trollServer.includes(marker), `TrollStore task 97 missing ${marker}`);
  assert.ok(doc.includes(marker), `P0 document missing ${marker}`);
}
for (const source of [rootTask, trollServer]) {
  assert.match(source, /@"secure_pairing"/);
  assert.match(source, /@"state": @"contract_only"/);
  assert.match(source, /@"mode": @"observe_only"/);
  assert.match(source, /@"device_validated": @0/);
}
assert.doesNotMatch(rootServer, /kZXSPMagic|\{'Z',\s*'X',\s*'S',\s*'P'\}/,
  "rootfull must not implement ZXSP framing in P0");
assert.doesNotMatch(trollServer, /kZXSPMagic|\{'Z',\s*'X',\s*'S',\s*'P'\}/,
  "TrollStore must not implement ZXSP framing in P0");

assert.match(deviceTest, /pairing_attempted = \$false/);
assert.match(deviceTest, /Invoke-TLinkPairingBaselineTask -Task "99"/);
assert.doesNotMatch(deviceTest, /GetBytes\("ZXSP/);
assert.match(doc, /contract only \/ observe only/i);
assert.match(doc, /license must never be treated as evidence/i);
assert.match(doc, /network request[\s\S]*cannot open it/i);
assert.match(doc, /must not silently retry plaintext/i);
assert.match(trollStatus, /Secure Pairing P0/);
assert.match(plan, /Secure Pairing P0/);
assert.match(rootWorkflow, /node scripts\/check-secure-pairing-p0\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-secure-pairing-p0\.mjs/);
assert.match(trollWorkflow, /test -f scripts\/Test-TLinkSecurePairingPhase0\.ps1/);

console.log("Secure Pairing P0 OK: baseline, threat model, ZXSP wire contract v1 and crypto vectors frozen; enforcement observe-only");
