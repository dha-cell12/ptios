import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(
  await read("test/fixtures/license-rootfull-authority-contract-v1.json"),
);

assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.runtime, "rootfull");
assert.equal(fixture.transport, "unix_socket");
assert.equal(fixture.authorityProcess, "tlinkauto-licensed");
assert.equal(fixture.authorityUser, "mobile");
assert.equal(fixture.nonceBytes, 32);
assert.equal(fixture.proofLifetimeMs, 10000);
assert.equal(fixture.maximumProofLifetimeMs, 15000);
assert.equal(fixture.failureMode, "fail_closed");
assert.equal(fixture.vpnEntitlementAllowed, false);

const [
  rootMakefile,
  authorityMakefile,
  authority,
  client,
  clientHeader,
  verifier,
  daemonMakefile,
  pccontrolMakefile,
  jsdMakefile,
  vpnMakefile,
  entitlements,
  launchd,
  postinst,
  socketServer,
  artifactValidator,
  policyText,
  integrationText,
  workflow,
  deviceTest,
  doc,
] = await Promise.all([
  read("Makefile"),
  read("license-authority/Makefile"),
  read("license-authority/main.mm"),
  read("shared/TLinkLicenseAuthorityClient.mm"),
  read("shared/TLinkLicenseAuthorityClient.h"),
  read("shared/TLinkLicenseVerifier.mm"),
  read("tlinkauto-binary/Makefile"),
  read("pccontrol/Makefile"),
  read("tlinkauto-jsd/Makefile"),
  read("vpn-broker/Makefile"),
  read("layout/license-authority-entitlements.plist"),
  read("layout/Library/LaunchDaemons/com.tlinkauto.license-authority.plist"),
  read("layout/DEBIAN/postinst"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("scripts/validate-rootfull-license-phase6-artifact.mjs"),
  read("license-rootfull-policy.json"),
  read("license-rootfull-integration.json"),
  read(".github/workflows/build.yml"),
  read("scripts/Test-TLinkRootfullLicensePhase6.ps1"),
  read("docs/license-rootfull-authority-hotfix.md"),
]);

assert.match(rootMakefile, /SUBPROJECTS = [^\r\n]*license-authority/);
assert.match(authorityMakefile, /TOOL_NAME = tlinkauto-licensed/);
assert.match(authorityMakefile, /TLinkLicenseVerifier\.mm/);
assert.match(authorityMakefile, /license-authority-entitlements\.plist/);
assert.doesNotMatch(authorityMakefile, /TLINK_LICENSE_AUTHORITY_CLIENT=1/);

assert.ok(
  clientHeader.includes(fixture.socketPath),
  "authority socket contract changed",
);
assert.match(authority, /AF_UNIX/);
assert.match(authority, /license_authority_signed_status_v1/);
assert.match(authority, /TLinkLicenseCreateDeviceSignature/);
assert.match(authority, /@"nonce": nonce/);
assert.match(authority, /@"expires_at_ms": @\(issuedAt \+ 10000\)/);
assert.match(authority, /chmod\(TLINK_LICENSE_AUTHORITY_SOCKET_PATH, 0660\)/);
assert.doesNotMatch(authority, /license_key|admin_token|private_jwk/i);

assert.match(client, /SecRandomCopyBytes/);
assert.match(client, /uint8_t nonceBytes\[32\]/);
assert.match(client, /SecKeyVerifySignature/);
assert.match(client, /kSecKeyAlgorithmECDSASignatureMessageX962SHA256/);
assert.match(client, /TLinkLicenseDevicePublicKeyAnchored/);
assert.match(client, /expiresAt - issuedAt <= 15000/);
assert.match(client, /license_authority_signature_invalid/);
assert.match(client, /license_authority_proof_invalid_or_expired/);
assert.doesNotMatch(client, /TLinkLicenseCreateDeviceSignature/);

assert.match(verifier, /TLINK_LICENSE_AUTHORITY_CLIENT/);
assert.match(verifier, /TLinkLicenseAuthorityStatus/);
assert.match(verifier, /rootfull_license_authority_client_v1/);
assert.match(verifier, /TLinkLicenseCreateDeviceSignature/);
assert.match(verifier, /TLinkLicenseDevicePublicKeyAnchored/);
assert.match(verifier, /license_authority_public_key_not_lease_anchored/);

for (const [name, makefile] of [
  ["tlinkautod", daemonMakefile],
  ["pccontrol", pccontrolMakefile],
  ["tlinkauto-jsd", jsdMakefile],
  ["tlinkauto-vpnd", vpnMakefile],
]) {
  assert.match(makefile, /TLinkLicenseAuthorityClient\.mm/,
    `${name} is missing authority client source`);
  assert.match(makefile, /TLINK_LICENSE_AUTHORITY_CLIENT=1/,
    `${name} is not compiled in authority-client mode`);
}

assert.match(entitlements, /keychain-access-groups[\s\S]*com\.tlinkauto\.tlinkauto/);
assert.doesNotMatch(entitlements, /networking\.vpn\.api|networking\.networkextension/);
assert.match(launchd, /<string>\/usr\/libexec\/tlinkauto-licensed<\/string>/);
assert.match(launchd, /<key>UserName<\/key>\s*<string>mobile<\/string>/);
assert.match(launchd, /<key>KeepAlive<\/key>\s*<true\/>/);
assert.ok(
  postinst.indexOf("launchctl load -w /Library/LaunchDaemons/com.tlinkauto.license-authority.plist") <
    postinst.indexOf("launchctl load -w /Library/LaunchDaemons/com.tlinkauto.tlinkautod.plist"),
  "license authority must load before tlinkautod",
);
assert.match(postinst, /rm -f \/var\/mobile\/Library\/TLinkauto\/run\/license-authority\.sock/);

assert.match(socketServer, /licenseAuthority=unix_signed_nonce_v1/);
assert.match(artifactValidator, /usr\/libexec\/tlinkauto-licensed/);
assert.match(artifactValidator, /license authority is missing the shared app Keychain access group/);
assert.match(artifactValidator, /license authority must not inherit VPN entitlements/);
assert.match(artifactValidator, /missing the signed license authority client/);

const policy = JSON.parse(policyText);
const integration = JSON.parse(integrationText);
assert.equal(
  policy.components.find(({ component }) => component === "license_authority")
    ?.gate_status,
  "active_signed_nonce_status_v1",
);
assert.equal(
  integration.verifier_components.find(
    ({ component }) => component === "license_authority",
  )?.binary,
  "usr/libexec/tlinkauto-licensed",
);
assert.equal(
  integration.long_running_components.license_authority.failure_mode,
  "fail_closed",
);

assert.match(workflow, /check-rootfull-license-authority\.mjs/);
assert.match(deviceTest, /authority_contract_version/);
assert.match(deviceTest, /authority_proof/);
assert.match(doc, /license_device_private_key_unavailable/);
assert.match(doc, /rotate/i);

console.log(
  "rootfull license authority OK: signed nonce status, narrow Keychain entitlement and fail-closed clients",
);
