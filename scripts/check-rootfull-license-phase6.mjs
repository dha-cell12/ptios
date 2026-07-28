import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = async (path) => readFile(new URL(path, root), "utf8");

const integration = JSON.parse(await read("license-rootfull-integration.json"));
const policy = JSON.parse(await read("license-rootfull-policy.json"));
const verifier = await read("shared/TLinkLicenseVerifier.mm");
const licenseManager = await read("stream-app/app/LicenseManager.mm");
const licenseView = await read("stream-app/app/LicenseViewController.mm");
const socket = await read("tlinkauto-binary/SocketServer.mm");
const task = await read("pccontrol/Task.xm");
const buildPlist = await read("RootfullLicenseBuild.plist");
const workflow = await read(".github/workflows/build.yml");
const validator = await read("scripts/validate-rootfull-license-phase6-artifact.mjs");
const deviceProbe = await read("scripts/Test-TLinkRootfullLicensePhase6.ps1");
const soak = await read("scripts/Start-TLinkRootfullLicensePhase6Soak.ps1");
const docs = await read("docs/license-rootfull-phase6.md");

assert.equal(integration.phase, 6);
assert.equal(integration.next_runtime_gate_phase, 7);
assert.equal(policy.phase, 6);
assert.equal(integration.release_hardening.package_runtime_coherence.active, true);
assert.equal(integration.release_hardening.anti_rollback.active, true);
assert.equal(
  policy.components.find(({ component }) => component === "release_integrity")?.gate_status,
  "active_phase_6_enforced_fail_closed"
);
assert.equal(
  policy.components.find(({ component }) => component === "anti_rollback")?.gate_status,
  "active_phase_6_signed_device_checkpoint"
);

for (const evidence of [
  "RootfullLicenseBuild.plist",
  "ReleaseIntegrityVersion",
  "rootfull_release_integrity_v1",
  "license_release_integrity_failed",
  "signed_device_checkpoint_v1",
  "license_lease_rollback_detected",
  "license_clock_rollback_detected",
  "SecKeyCreateSignature",
  "SecKeyVerifySignature",
  "trust_checkpoint.lock",
]) {
  assert.ok(verifier.includes(evidence), `verifier lacks Phase 6 evidence ${evidence}`);
}
assert.match(verifier, /TLinkRootfullLicenseBuildIsEnforced/);
assert.match(verifier, /TLinkValidateAndAdvanceTrustCheckpoint/);
assert.match(verifier, /TLinkLicenseResetTrustCheckpoint/);
assert.match(verifier, /TLINK_LICENSE_ROOTFULL_RUNTIME/);
assert.match(licenseManager, /previousCheckpointData/);
assert.match(licenseManager, /license_candidate_rollback_detected/);
assert.match(licenseManager, /TLinkLicenseResetTrustCheckpoint/);

for (const source of [socket, task]) {
  assert.match(source, /(?:rootfull_license_phase"\]|licenseStatus\[@"phase"\])\s*=\s*@6/);
  assert.match(source, /release_integrity_active/);
  assert.match(source, /anti_rollback_active/);
}
assert.match(socket, /zx_rootfullPhase6DiagnosticResponse/);
assert.match(socket, /license_phase=6/);
assert.match(socket, /releaseIntegrity=1/);
assert.match(socket, /antiRollback=1/);
assert.match(licenseView, /Release Integrity/);
assert.match(licenseView, /Anti-Rollback/);

assert.match(buildPlist, /<key>RootfullLicensePhase<\/key>\s*<integer>6<\/integer>/);
assert.match(buildPlist, /<key>ReleaseIntegrityVersion<\/key>\s*<integer>1<\/integer>/);
assert.match(buildPlist, /<key>AntiRollbackPolicy<\/key>\s*<string>signed_device_checkpoint_v1<\/string>/);

assert.match(workflow, /check-rootfull-license-phase6\.mjs/);
assert.match(workflow, /validate-rootfull-license-phase6-artifact\.mjs/);
assert.match(workflow, /rootfull-license-phase6-/);
assert.match(validator, /rootfull_license_phase:\s*6/);
assert.match(validator, /secret_scan:\s*"passed"/);
assert.match(deviceProbe, /ExpectedPhase\s*=\s*6/);
assert.match(deviceProbe, /release_integrity/);
assert.match(deviceProbe, /anti_rollback/);
assert.match(soak, /MaxConsecutiveFailures/);
assert.match(soak, /jsonl/);
assert.match(soak, /release_integrity/);
assert.match(docs, /24-hour/);
assert.match(docs, /72-hour/);
assert.match(docs, /OLLVM/);
assert.match(docs, /client authentication/);

console.log(
  "rootfull license phase 6 OK: release coherence, signed anti-rollback checkpoint, " +
  "device regression, soak evidence and enforced artifact validation"
);
