import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

async function source(path) {
  return readFile(resolve(root, path), "utf8");
}

function section(text, start, end) {
  const startIndex = text.indexOf(start);
  const endIndex = text.indexOf(end, startIndex + start.length);
  assert.ok(startIndex >= 0 && endIndex > startIndex, `missing section ${start}`);
  return text.slice(startIndex, endIndex);
}

const verifier = await source("shared/TLinkLicenseVerifier.mm");
const manager = await source("stream-app/app/LicenseManager.mm");
const coordinator = await source("stream-app/app/LicenseLifecycleCoordinator.mm");
const view = await source("stream-app/app/LicenseViewController.mm");
const supervisor = await source("stream-app/app/StreamSupervisor.mm");
const server = await source("stream-app/streamd/POCSocketServer.mm");

const quarantine = section(verifier, "static NSString *TLinkQuarantineCorruptLease", "NSDictionary *TLinkLicenseStatusDictionary");
const advanceGeneration = section(verifier, "uint64_t TLinkLicenseAdvanceGeneration", "static NSString *TLinkExecutableDirectory");
assert.ok(!advanceGeneration.includes("quarantine_lock_failed"), "quarantine recovery logic leaked into the generic generation helper");
assert.ok(quarantine.includes("flock(lockFD, LOCK_EX)"), "quarantine generation update lacks a cross-process lock");
assert.ok(quarantine.includes("quarantine_lock_failed"), "quarantine does not fail closed when its lock is unavailable");
assert.ok(quarantine.includes("moveItemAtPath:kTLinkLicenseLease"), "corrupt lease is not moved out of the active path");
assert.ok(quarantine.includes("notify_post(kTLinkLicenseDarwinNotification)"), "quarantine does not notify other processes");
assert.ok(!quarantine.includes("TLinkLicenseAdvanceGeneration()"), "quarantine must not dispatch-sync into the verifier cache queue");
assert.ok(verifier.includes("kTLinkLicenseClockSkewToleranceSeconds"), "clock skew tolerance is not explicit");
assert.ok(verifier.includes("license_signature_invalid"), "signature corruption is not fail-closed");

assert.ok(manager.includes("repairDevicePublicKey"), "device public-key repair API is missing");
assert.ok(manager.includes("device_private_key_present"), "private-key recovery diagnostics are missing");
assert.ok(manager.includes("deactivate_the_old_device_or_request_an_admin_device_reset"), "device-limit recovery guidance is missing");
assert.ok(coordinator.includes("publishLicenseChange:@\"repair_device_public_key\""), "repair does not publish a global license change");
assert.ok(view.includes("Repair Device Binding"), "License UI has no device binding repair action");

assert.ok(supervisor.includes("serviceVersion=22"), "app does not require the current streamd version");
assert.ok(server.includes('withString:@"serviceVersion=22"'), "task 97 does not expose the current service version");
assert.ok(server.includes('@"service_version": @22'), "task 60 does not expose the current service version");

console.log("license recovery policy OK: quarantine, key repair, lifecycle guidance, service v22");
