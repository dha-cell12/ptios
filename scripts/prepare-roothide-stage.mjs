import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const rootfsIndex = args.indexOf("--rootfs");
assert.ok(rootfsIndex >= 0 && args[rootfsIndex + 1], "missing --rootfs");
const rootfs = resolve(args[rootfsIndex + 1]);

const launchDaemons = [
  "Library/LaunchDaemons/com.tlinkauto.license-authority.plist",
  "Library/LaunchDaemons/com.tlinkauto.vpn-broker.plist",
];

for (const relative of launchDaemons) {
  const path = resolve(rootfs, relative);
  const source = await readFile(path, "utf8");
  const staged = source.replaceAll(
    "/var/mobile/Library/TLinkauto/",
    "/rootfs/var/mobile/Library/TLinkauto/",
  );
  assert.notEqual(staged, source, `${relative} has no rootfs data path to rewrite`);
  assert.ok(!staged.includes("<string>/var/mobile/Library/TLinkauto/"));
  await writeFile(path, staged, "utf8");
}

console.log("Prepared Roothide staging tree: launchd logs use the shared rootfs data directory");
