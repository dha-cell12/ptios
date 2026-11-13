import assert from "node:assert/strict";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";
import { pathToFileURL } from "node:url";
import { rootlessDaemons } from "../scripts/prepare-rootless-stage.mjs";

const binaries = ["Applications/TLinkauto.app/TLinkauto", "usr/bin/tlinkautod", "usr/bin/tlinkautob",
  "usr/libexec/tlinkauto-jsd", "usr/libexec/tlinkauto-licensed", "usr/libexec/tlinkauto-vpnd",
  "Library/MobileSubstrate/DynamicLibraries/pccontrol.dylib", "Library/MobileSubstrate/DynamicLibraries/appdelegate.dylib"];
const evidence = ["rootfull_ui_memory_snapshot", "Release Integrity", "Anti-Rollback", "signed_device_checkpoint_v1",
  "license_phase=6", "releaseIntegrity=1", "antiRollback=1", "tlinkautod_rootfull_phase6_release_hardened",
  "h264HeartbeatMs=5000", "scriptHeartbeatMs=1000", "script_helper_start", "license_revoked_during_execution",
  "rootfull_license_authority_client_v1", "license_authority_signed_status_v1", "rootfull_license_authority_signed_v1",
  "vpn_license_denied", "tlinkauto-managed-v1", "vpn_on_demand_enabled",
  "local_ui_connect_all_networks_explicit_disconnect_disables", "active client closed by license",
  "scheduler launch blocked by license", "release_integrity_active", "anti_rollback_active",
  "license_device_key_mismatch", "rootfull_release_integrity_v1", "license_release_integrity_failed",
  "license_lease_rollback_detected", "license_authority_signature_invalid"];
const roothideKeys = ["platform-application", "com.apple.private.security.no-sandbox",
  "com.apple.private.security.storage.AppBundles", "com.apple.private.security.storage.AppDataContainers"];
const plist = values => '<?xml version="1.0"?><plist version="1.0"><dict>' + Object.entries(values)
  .map(([key, value]) => `<key>${key}</key>` + (typeof value === "boolean" ? `<${value}/>` :
    typeof value === "number" ? `<integer>${value}</integer>` : `<string>${value}</string>`)).join("") + "</dict></plist>";

export async function checkRootlessArtifacts(root, temp, stage) {
  let serial = 0;
  async function seed(runtime, mode) {
    const directory = join(temp, `artifact-${serial++}`), payload = runtime === "rootless" ? join(directory, "var/jb") : directory;
    for (const file of binaries) {
      const path = join(payload, file); await mkdir(dirname(path), { recursive: true });
      await writeFile(path, [`rootfull_${mode}_compile_time_v1`, `${mode}_compile_time_v1`, ...evidence,
        ...(runtime === "rootless" ? ["rootless_var_jb_v1"] : [])].join("\n"));
    }
    const app = join(payload, "Applications/TLinkauto.app");
    await writeFile(join(app, "RootfullLicenseBuild.plist"), plist({ RootfullLicensePhase: 6, RootfullLicenseMode: mode,
      LicenseContractVersion: 1, EnforcementBehavior: "task_and_long_running_component_gate", ReleaseIntegrityVersion: 1,
      AntiRollbackPolicy: "signed_device_checkpoint_v1" }));
    await writeFile(join(app, "LicenseConfig.plist"), plist({ LicenseEndpoint: "https://fixture.invalid", LicenseKeyID: "fixture",
      LicensePublicKeyX: "A".repeat(43), LicensePublicKeyY: "B".repeat(43), LicenseEnforcementEnabled: mode === "enforced" }));
    if (runtime === "rootless") {
      for (const [label] of rootlessDaemons) {
        const file = `Library/LaunchDaemons/com.tlinkauto.${label}.plist`, path = join(payload, file);
        await mkdir(dirname(path), { recursive: true }); await writeFile(path, await readFile(join(stage, file)));
      }
      await mkdir(join(directory, "DEBIAN"));
      for (const name of ["preinst", "postinst"]) await writeFile(join(directory, "DEBIAN", name), await readFile(join(stage, "DEBIAN", name)));
    } else if (runtime === "roothide") {
      for (const label of ["license-authority", "vpn-broker"]) {
        const path = join(payload, `Library/LaunchDaemons/com.tlinkauto.${label}.plist`);
        await mkdir(dirname(path), { recursive: true }); await writeFile(path, "<string>/rootfs/var/mobile/Library/TLinkauto/log</string>");
      }
    }
    return { directory, payload, runtime, mode };
  }
  async function validate(fixture) {
    const originalExec = childProcess.execFileSync, originalArgv = process.argv;
    const output = join(fixture.directory, "manifest.json");
    // Only the platform adapters are controlled. The complete production
    // validator, filesystem reads, markers, prefix/config/secret gates run.
    childProcess.execFileSync = (command, args) => {
      if (command === "/usr/bin/plutil") return ""; // Real XML fixtures use its existing fallback.
      assert.equal(command, "ldid"); assert.equal(args[0], "-e");
      const file = relative(fixture.payload, args[1]).replaceAll("\\", "/");
      assert.ok(!file.startsWith(".."), "entitlement lookup escaped the payload prefix");
      const keys = fixture.runtime === "roothide" ? [...roothideKeys] : [];
      if (file === binaries[0] || file === "usr/libexec/tlinkauto-vpnd") keys.push("com.apple.developer.networking.vpn.api", "allow-vpn");
      if (!file.includes("shortcutext")) keys.push("keychain-access-groups", "com.tlinkauto.tlinkauto");
      return keys.join("\n");
    };
    syncBuiltinESMExports();
    process.argv = [process.execPath, "validator", "--rootfs", fixture.directory, "--runtime", fixture.runtime,
      "--mode", fixture.mode, "--output", output, "--endpoint", "https://fixture.invalid", "--keyId", "fixture",
      "--publicKeyX", "A".repeat(43), "--publicKeyY", "B".repeat(43)];
    try {
      await import(pathToFileURL(join(root, "scripts/validate-rootfull-license-phase6-artifact.mjs")).href + `?rootless-fixture=${serial++}`);
      const manifest = JSON.parse(await readFile(output, "utf8"));
      assert.equal(manifest.package_runtime, fixture.runtime); assert.equal(manifest.license_mode, fixture.mode);
      assert.equal(Object.keys(manifest.binaries_sha256).length, 8);
    } finally {
      process.argv = originalArgv; childProcess.execFileSync = originalExec; syncBuiltinESMExports();
    }
  }
  for (const runtime of ["rootfull", "roothide", "rootless"]) {
    for (const mode of ["observe", "enforced"]) await validate(await seed(runtime, mode));
  }
  const marker = await seed("rootless", "observe"), appPath = join(marker.payload, binaries[0]);
  await writeFile(appPath, (await readFile(appPath, "utf8")).replace("rootless_var_jb_v1", ""));
  await assert.rejects(validate(marker), /wrong rootless compile mode/);
  const daemon = await seed("rootless", "observe"), daemonPath = join(daemon.payload, "Library/LaunchDaemons/com.tlinkauto.tlinkautod.plist");
  await writeFile(daemonPath, (await readFile(daemonPath, "utf8")).replace("/var/jb/usr/bin/tlinkautod", "/usr/bin/tlinkautod"));
  await assert.rejects(validate(daemon), /unprefixed executable/);
  const shell = await seed("rootless", "observe"); await writeFile(join(shell.directory, "DEBIAN/preinst"), "#!/bin/sh\n");
  await assert.rejects(validate(shell), /rootless shell/);
  const secret = await seed("rootless", "observe"); await writeFile(join(secret.directory, "outside-prefix.txt"), "BEGIN PRIVATE KEY");
  await assert.rejects(validate(secret), /forbidden secret/);
  console.log("Artifact validator fixtures passed: all six runtime/license manifests, missing rootless marker, launchd/shell mismatch and secret outside /var/jb refusal. Signatures/plutil are controlled; real Mach-O/signing validation remains in CI.");
}
