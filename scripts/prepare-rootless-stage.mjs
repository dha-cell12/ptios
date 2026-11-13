import assert from "node:assert/strict";
import { lstat, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

export const rootlessDaemons = [
  ["tlinkautod", "usr/bin/tlinkautod"],
  ["js-helper", "usr/libexec/tlinkauto-jsd"],
  ["license-authority", "usr/libexec/tlinkauto-licensed"],
  ["vpn-broker", "usr/libexec/tlinkauto-vpnd"],
];
const rootlessPATH = "export PATH=/var/jb/usr/sbin:/var/jb/usr/bin:/var/jb/sbin:/var/jb/bin:$PATH\n";

export function rootlessMaintainer(source, name) {
  if (source.startsWith("#!/var/jb/bin/sh\nTLINK_PACKAGE_RUNTIME=rootless\n")) return source;
  assert.ok(source.startsWith("#!/bin/sh\n"), `${name}: unexpected interpreter`);
  let body = source.slice("#!/bin/sh\n".length)
    .replaceAll("[ -d /rootfs/var/mobile ]", '[ "$TLINK_PACKAGE_RUNTIME" != rootless ] && [ -d /rootfs/var/mobile ]')
    .replace(/(?<![A-Za-z0-9_/.])\/(Applications|Library|usr|etc|bin)\//g, "/var/jb/$1/")
    .replace(/(?<![A-Za-z0-9_/.])\/((?:entitlements|shortcut-entitlements|license-authority-entitlements)(?:-roothide)?\.plist)/g, "/var/jb/$1");
  if (name === "postinst") {
    const anchor = 'mkdir -p "$TLINK_DATA_ROOT/run"\n';
    assert.equal(body.split(anchor).length, 2, "postinst: missing unique data bootstrap anchor");
    // Theos prefixes layout data too. Seed the shared writable directory before
    // the original config-backup restoration, preserving an existing config.
    body = body.replace(anchor, anchor +
      'if [ -d /var/jb/var/mobile/Library/TLinkauto ]; then\n' +
      '    if [ -f "$TLINK_DATA_ROOT/config.json" ] && [ ! -f "$TLINK_DATA_ROOT/config.json.preinst-bak" ]; then\n' +
      '        cp -p "$TLINK_DATA_ROOT/config.json" "$TLINK_DATA_ROOT/config.json.preinst-bak" || exit 1\n    fi\n' +
      '    cp -R /var/jb/var/mobile/Library/TLinkauto/. "$TLINK_DATA_ROOT/"\nfi\n');
  }
  return "#!/var/jb/bin/sh\nTLINK_PACKAGE_RUNTIME=rootless\n" + rootlessPATH + body;
}

export async function prepareRootlessStage(directory) {
  const root = resolve(directory);
  const staged = [];
  async function source(relative) {
    // Never write through a symlink in a supplied staging tree.
    let path = root;
    for (const part of relative.split("/")) {
      assert.ok(part && part !== "." && part !== "..");
      const parent = await lstat(path);
      assert.ok(parent.isDirectory() && !parent.isSymbolicLink(), `unsafe staging directory: ${path}`);
      path = join(path, part);
    }
    const info = await lstat(path);
    assert.ok(info.isFile() && !info.isSymbolicLink(), `unsafe staging file: ${path}`);
    return { path, text: (await readFile(path, "utf8")).replaceAll("\r\n", "\n") };
  }
  for (const [label, executable] of rootlessDaemons) {
    const file = await source(`Library/LaunchDaemons/com.tlinkauto.${label}.plist`);
    const original = `<string>/${executable}</string>`;
    const prefixed = `<string>/var/jb/${executable}</string>`;
    assert.ok(file.text.includes(original) || file.text.includes(prefixed), `${label}: unexpected executable`);
    staged.push({ path: file.path, text: file.text.replaceAll(original, prefixed)
      .replaceAll("<string>/var/log/", "<string>/var/mobile/Library/TLinkauto/") });
  }
  for (const name of ["preinst", "postinst"]) {
    const file = await source(`DEBIAN/${name}`);
    staged.push({ path: file.path, text: rootlessMaintainer(file.text, name) });
  }
  const script = await source("var/mobile/Library/TLinkauto/coreutils/ScriptRuntime/add_datetime.sh");
  assert.ok(script.text.startsWith("#!/bin/bash\n") || script.text.startsWith("#!/var/jb/bin/bash\n"));
  staged.push({ path: script.path, text: script.text.startsWith("#!/bin/bash\n")
    ? script.text.replace("#!/bin/bash\n", "#!/var/jb/bin/bash\n" + rootlessPATH) : script.text });
  // Complete preflight before modifying any source. Theos applies /var/jb to
  // the staging tree afterwards; these are runtime strings, not a second move.
  for (const file of staged) await writeFile(file.path, file.text, "utf8");
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  assert.equal(args.length, 2, "usage: prepare-rootless-stage.mjs --rootfs STAGING_DIRECTORY");
  assert.equal(args[0], "--rootfs");
  await prepareRootlessStage(args[1]);
  console.log("Prepared rootless staging: /var/jb services, install scripts and shared writable data");
}
