import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (path) => readFile(resolve(root, path), "utf8");

const [workflow, workerWorkflow, verifier, server, validator, regression, soak, docs] = await Promise.all([
  source(".github/workflows/stream-app.yml"),
  source(".github/workflows/license-worker.yml"),
  source("shared/TLinkLicenseVerifier.mm"),
  source("stream-app/streamd/POCSocketServer.mm"),
  source("scripts/validate-license-artifact.mjs"),
  source("scripts/Test-TLinkLicensePhase6.ps1"),
  source("scripts/Start-TLinkLicenseSoak.ps1"),
  source("docs/license-phase6-release-gate.md"),
]);

assert.ok(workflow.includes("license_mode: [observe, enforced]"), "CI does not build both license modes");
assert.ok(workflow.includes("matrix.license_mode == 'enforced'"), "compile enforcement is not derived from the matrix mode");
assert.ok(workflow.includes("validate-license-artifact.mjs"), "artifact validator is not in the build workflow");
assert.ok(workflow.includes("StreamControl-tipa-${{ matrix.license_mode }}"), "mode-specific artifacts are missing");
assert.ok(!workflow.includes("LICENSE_SIGNING_PRIVATE_JWK:"), "build workflow must not receive the signing private key");
assert.ok(!workflow.includes("TLINK_LICENSE_ADMIN_TOKEN:"), "build workflow must not receive the admin token");

assert.ok(workerWorkflow.includes("check-license-recovery.mjs"), "Worker validation omits recovery checks");
assert.ok(workerWorkflow.includes("check-license-release-readiness.mjs"), "Worker validation omits release-readiness checks");
assert.ok(verifier.includes("enforced_compile_time_v1") && verifier.includes("observe_compile_time_v1"), "compile markers are missing");
assert.ok(server.includes("serviceVersion=23") && server.includes('@"service_version": @23'), "service v23 is not synchronized");
assert.ok(validator.includes("secret_scan") && validator.includes("forbidden"), "artifact secret scan is missing");
assert.ok(regression.includes('Invoke-TLinkTask -Task "76reload"'), "device regression does not test cache reload");
assert.ok(regression.includes("RunSafeFeatureProbes"), "device regression lacks feature probes");
assert.ok(regression.includes("UTF8Encoding]::new($false)"), "device regression may prefix tasks with a UTF-8 BOM");
assert.ok(soak.includes("MaxConsecutiveFailures") && soak.includes("jsonl"), "soak evidence/failure threshold is missing");
assert.ok(soak.includes("UTF8Encoding]::new($false)"), "soak probe may prefix tasks with a UTF-8 BOM");
assert.ok(docs.includes("24-hour") && docs.includes("72-hour"), "release gate lacks required soak windows");
assert.ok(docs.includes("ROOTFULL BLOCKED"), "rootfull blocking rule is not explicit");

console.log("license release readiness OK: dual-mode artifacts, secret scan, device regression, soak gate");
