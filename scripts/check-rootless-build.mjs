import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, mkdir, copyFile, rm, lstat, symlink, chmod } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { prepareRootlessStage, rootlessDaemons } from "./prepare-rootless-stage.mjs";
import { checkRootlessArtifacts } from "../test/rootless-artifact-validation-test.mjs";
import { restoreRootlessMakefile } from "./lib/rootless-makefile-baseline.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = async file => (await readFile(join(root, file), "utf8")).replaceAll("\r\n", "\n");
const makefile = await read("Makefile"), workflow = await read(".github/workflows/build.yml");
const branch = makefile.split("else ifeq ($(TLINK_PACKAGE_RUNTIME),rootless)\n")[1]?.split("else ifeq")[0];
assert.ok(branch, "missing rootless make branch");
for (const value of ["THEOS_PACKAGE_SCHEME = rootless", "DEB_ARCH = iphoneos-arm64", "ARCHS = arm64",
  "TARGET = iphone:clang:latest:15.0", "IPHONEOS_DEPLOYMENT_TARGET = 15.0", "TLINK_ROOTHIDE_RUNTIME := 0", "TLINK_ROOTLESS_RUNTIME := 1"]) assert.ok(branch.includes(value), value);
assert.match(makefile, /prepare-rootless-stage\.mjs" --rootfs "\$\(THEOS_STAGING_DIR\)"/);
assert.match(workflow, /package_runtime: \[rootfull, roothide, rootless\]/);
assert.match(workflow, /license_mode: \[observe, enforced\]/);
assert.match(workflow, /TLINK_ROOTLESS_RUNTIME:.*matrix\.package_runtime == 'rootless'/);
assert.match(workflow, /TLINK_ROOTLESS_RUNTIME=\$\{TLINK_ROOTLESS_RUNTIME\}/);
assert.match(workflow, /EXPECTED_ARCH="iphoneos-arm64"/);
assert.match(workflow, /dpkg-deb -e "\$DEB_PATH" "\$ROOTFS\/DEBIAN"/);
for (const directory of ["appdelegate", "pccontrol", "tlinkauto-binary", "tlinkauto-jsd", "license-authority", "vpn-broker"]) {
  const source = await read(`${directory}/Makefile`);
  assert.match(source, /TLINK_ROOTLESS_RUNTIME \?= 0/);
  assert.match(source, /-DTLINK_ROOTLESS_RUNTIME=\$\(TLINK_ROOTLESS_RUNTIME\)/);
  const file = `${directory}/Makefile`, previous = restoreRootlessMakefile(source, file);
  assert.doesNotMatch(previous, /TLINK_ROOTLESS_RUNTIME/);
  assert.equal(restoreRootlessMakefile(previous, file), previous, "preceding fixtures remain compatible");
  for (const changed of [source + "\n# unrelated edit\n",
    source.replace(" -DTLINK_ROOTLESS_RUNTIME=$(TLINK_ROOTLESS_RUNTIME)", ""),
    source.replace("TLINK_LICENSE_FORCE_ENFORCEMENT ?= 0", "TLINK_LICENSE_FORCE_ENFORCEMENT ?= 1"),
    source.replace("TLINK_ROOTLESS_RUNTIME ?= 0\n", "TLINK_ROOTLESS_RUNTIME ?= 0\nTLINK_ROOTLESS_RUNTIME ?= 0\n")]) {
    assert.notEqual(changed, source);
    assert.throws(() => restoreRootlessMakefile(changed, file), /complete rootless/);
  }
}
console.log("Rootless Makefile baseline passed: six complete current/prior hashes, exact flag reversal and 24 unrelated/missing/duplicate/license-edit refusals; historical persistence/indicator hashes unchanged.");
const validator = await read("scripts/validate-rootfull-license-phase6-artifact.mjs");
assert.match(validator, /const payloadRoot = runtime === "rootless" \? join\(rootfs, "var\/jb"\) : rootfs/);
assert.match(validator, /rootless_var_jb_v1/);
assert.match(validator, /listFiles\(rootfs\)/);
assert.doesNotMatch(validator, /join\(rootfs, (?:relative|"Applications|"usr|"Library)/);
const files = rootlessDaemons.map(([name]) => `Library/LaunchDaemons/com.tlinkauto.${name}.plist`)
  .concat(["DEBIAN/preinst", "DEBIAN/postinst", "var/mobile/Library/TLinkauto/coreutils/ScriptRuntime/add_datetime.sh"]);
const originals = new Map(await Promise.all(files.map(async file => [file, await read(`layout/${file}`)])));
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot, "tlink-rootless-build-"));
async function seed(folder) {
  for (const file of files) {
    const path = join(folder, file); await mkdir(dirname(path), { recursive: true });
    await copyFile(join(root, "layout", file), path);
    if (file.startsWith("DEBIAN/")) await chmod(path, 0o755);
  }
}
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", timeout: 120000 });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed signal=${result.signal}`);
}
try {
  const stage = join(temp, "stage"); await seed(stage); await prepareRootlessStage(stage);
  for (const [label, executable] of rootlessDaemons) {
    const text = await readFile(join(stage, `Library/LaunchDaemons/com.tlinkauto.${label}.plist`), "utf8");
    assert.ok(text.includes(`<string>/var/jb/${executable}</string>`));
    assert.ok(text.includes("/var/mobile/Library/TLinkauto/"));
    assert.ok(!text.includes("/var/log/") && !text.includes("/var/jb/var/mobile/"));
  }
  for (const name of ["preinst", "postinst"]) {
    const text = await readFile(join(stage, "DEBIAN", name), "utf8");
    assert.ok(text.startsWith("#!/var/jb/bin/sh\nTLINK_PACKAGE_RUNTIME=rootless\n"));
    assert.ok(text.includes('TLINK_DATA_ROOT="/var/mobile/Library/TLinkauto"'));
    assert.match(text, /\[ "\$TLINK_PACKAGE_RUNTIME" != rootless \] && \[ -d \/rootfs\/var\/mobile \]/);
    assert.doesNotMatch(text, /(?<![A-Za-z0-9_/.])\/(?:Applications|Library|usr|etc|bin)\//);
    assert.ok(!text.includes("/var/jb/var/jb/"));
    if (process.platform !== "win32") assert.equal((await lstat(join(stage, "DEBIAN", name))).mode & 0o777, 0o755);
    if (name === "postinst") {
      assert.ok(text.includes('cp -R /var/jb/var/mobile/Library/TLinkauto/. "$TLINK_DATA_ROOT/"'));
      assert.ok(text.indexOf("cp -R /var/jb/var/mobile/") < text.indexOf('mv "$TLINK_DATA_ROOT/config.json.preinst-bak"'));
      assert.ok(text.indexOf("launchctl load -w /var/jb/Library/LaunchDaemons/com.tlinkauto.license-authority.plist") <
        text.indexOf("launchctl load -w /var/jb/Library/LaunchDaemons/com.tlinkauto.tlinkautod.plist"));
      assert.ok(text.includes("mobile ALL=(root) NOPASSWD:/var/jb/usr/bin/tlinkautob"));
    }
    if (process.platform === "darwin") run("/bin/sh", ["-n", join(stage, "DEBIAN", name)]);
  }
  const transformed = await Promise.all(files.map(file => readFile(join(stage, file), "utf8")));
  assert.ok(transformed.at(-1).startsWith("#!/var/jb/bin/bash\n"));
  await prepareRootlessStage(stage);
  assert.deepEqual(await Promise.all(files.map(file => readFile(join(stage, file), "utf8"))), transformed, "staging is idempotent");
  // A late missing input must refuse during preflight without altering any of
  // the earlier launchd/script inputs. Original rootful/Roothide files stay put.
  const missing = join(temp, "missing"); await seed(missing); await rm(join(missing, files.at(-1)));
  await assert.rejects(prepareRootlessStage(missing));
  for (const file of files.slice(0, -1)) assert.equal((await readFile(join(missing, file), "utf8")).replaceAll("\r\n", "\n"), originals.get(file));
  for (const file of files) assert.equal(await read(`layout/${file}`), originals.get(file));
  const unsafe = join(temp, "unsafe"); await seed(unsafe);
  const target = join(unsafe, files[0]); await rm(target);
  try {
    await symlink(join(stage, files[0]), target);
    await assert.rejects(prepareRootlessStage(unsafe), /unsafe staging file/);
    assert.equal(await readFile(join(stage, files[0]), "utf8"), transformed[0]);
  } catch (error) {
    if (process.platform !== "win32" || !["EPERM", "EACCES"].includes(error.code)) throw error;
    console.log("Windows symlink privilege unavailable; refusal case remains required on macOS.");
  }
  console.log("Rootless staging passed: four launchd services, shell/helper/app/sudoers paths, shared data/config order, idempotence, missing-input preflight and unchanged rootful/Roothide layout.");
  await checkRootlessArtifacts(root, temp, stage);
  if (process.platform === "darwin") {
    // Evaluate the real top-level Makefile with inert Theos includes. No build,
    // package installation or privileged command runs in this variable probe.
    const theos = join(temp, "theos"); await mkdir(join(theos, "makefiles"), { recursive: true });
    for (const name of ["common.mk", "aggregate.mk"]) await writeFile(join(theos, "makefiles", name), "");
    const probe = join(temp, "probe.mk");
    await writeFile(probe, `include ${join(root, "Makefile").replaceAll(" ", "\\ ")}\n` +
      'probe:\n\t@printf "%s|%s|%s|%s|%s|%s\\n" "$(THEOS_PACKAGE_SCHEME)" "$(DEB_ARCH)" "$(ARCHS)" "$(TLINK_ROOTLESS_RUNTIME)" "$(TLINK_ROOTHIDE_RUNTIME)" "$(TLINK_LICENSE_FORCE_ENFORCEMENT)"\n');
    for (const runtime of ["rootfull", "roothide", "rootless"]) {
      for (const license of ["observe", "enforced"]) {
        const args = ["--no-print-directory", "-s", "-f", probe, "probe", `THEOS=${theos}`, `TLINK_PACKAGE_RUNTIME=${runtime}`, `TLINK_LICENSE_MODE=${license}`];
        const value = spawnSync("make", args, { cwd: root, encoding: "utf8", timeout: 30000 });
        assert.equal(value.status, 0, value.stderr);
        const expected = runtime === "rootfull" ? ["", "", "arm64e arm64", "0", "0"] :
          runtime === "rootless" ? ["rootless", "iphoneos-arm64", "arm64", "1", "0"] : ["roothide", "iphoneos-arm64e", "arm64", "0", "1"];
        assert.deepEqual(value.stdout.trim().split("|"), expected.concat(license === "enforced" ? "1" : "0"));
      }
    }
    const invalid = spawnSync("make", ["-s", "-f", probe, "probe", `THEOS=${theos}`, "TLINK_PACKAGE_RUNTIME=unknown"], { cwd: root, encoding: "utf8", timeout: 30000 });
    assert.notEqual(invalid.status, 0); assert.match(invalid.stderr, /TLINK_PACKAGE_RUNTIME must be/);
    // Rebase both bootstrap and shared-data paths into a private fixture tree.
    // Stub every service/UI/identity command; ordinary file operations are real.
    const sandbox = join(temp, "install"), jb = join(sandbox, "jb"), mobile = join(sandbox, "mobile");
    const data = join(mobile, "Library/TLinkauto"), defaults = join(jb, "var/mobile/Library/TLinkauto");
    for (const directory of [data, defaults, join(jb, "etc"), join(jb, "Library/LaunchDaemons")]) await mkdir(directory, { recursive: true });
    const config = '{"user_config":"preserved"}\n';
    await writeFile(join(data, "config.json"), config); await writeFile(join(defaults, "config.json"), '{"default":true}\n');
    const runtimeScript = "coreutils/ScriptRuntime/add_datetime.sh";
    await mkdir(dirname(join(defaults, runtimeScript)), { recursive: true });
    await copyFile(join(stage, "var/mobile/Library/TLinkauto", runtimeScript), join(defaults, runtimeScript));
    for (const [label, executable] of rootlessDaemons) {
      const file = join(jb, executable); await mkdir(dirname(file), { recursive: true }); await writeFile(file, "#!/bin/sh\nexit 0\n");
      await copyFile(join(stage, `Library/LaunchDaemons/com.tlinkauto.${label}.plist`), join(jb, `Library/LaunchDaemons/com.tlinkauto.${label}.plist`));
    }
    const trace = join(sandbox, "trace"), wrapper = join(sandbox, "run.sh");
    await writeFile(wrapper,
      'killall(){ :; }; chown(){ :; }; su(){ :; }; uicache(){ :; }; ldid(){ :; }\n' +
      'launchctl(){ printf "%s\\n" "$*" >> "$ROOTLESS_FIXTURE_TRACE"; }\n. "$1"\n');
    for (const name of ["preinst", "postinst"]) {
      const paths = { "/var/jb/var/mobile": join(jb, "var/mobile"), "/rootfs/var/mobile": join(sandbox, "rootfs-mobile"), "/var/jb": jb, "/var/mobile": mobile };
      const source = (await readFile(join(stage, "DEBIAN", name), "utf8"))
        .replace(/\/var\/jb\/var\/mobile|\/rootfs\/var\/mobile|\/var\/jb|\/var\/mobile/g, path => paths[path]);
      const path = join(sandbox, name); await writeFile(path, source);
      const times = name === "postinst" ? 2 : 1;
      for (let n = 0; n < times; ++n) {
        const result = spawnSync("/bin/sh", [wrapper, path], { cwd: root, encoding: "utf8", timeout: 30000,
          env: { ...process.env, ROOTLESS_FIXTURE_TRACE: trace } });
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.equal(await readFile(join(data, "config.json"), "utf8"), config);
      }
    }
    const loads = (await readFile(trace, "utf8")).split("\n").filter(line => line.startsWith("load -w "));
    assert.equal(loads.length, 8);
    assert.ok(loads[0].includes("license-authority.plist") && loads[1].includes("tlinkautod.plist"));
    assert.ok(loads.every(line => line.startsWith(`load -w ${jb}/Library/LaunchDaemons/`)));
    assert.ok((await readFile(join(jb, "etc/sudoers"), "utf8")).includes(`${jb}/usr/bin/tlinkautob`));
    assert.ok((await readFile(join(data, runtimeScript), "utf8")).startsWith("#!/var/jb/bin/bash\n"));
    console.log("Rootless install sandbox passed: real preinst/postinst files, preserved user config, repeated configure, four ordered service loads and prefixed sudoers; no real service/UI operation.");
    for (const mode of ["rootfull", "rootless-app", "rootless-sdk", "roothide-sdk"]) {
      const folder = join(temp, mode); await mkdir(folder);
      let prefix = ""; const defines = [];
      if (mode.startsWith("rootless")) { defines.push("-DTLINK_ROOTLESS_RUNTIME=1"); prefix = "/var/jb"; }
      if (mode === "rootless-sdk") {
        prefix = "/fixture-rootless";
        await writeFile(join(folder, "rootless.h"), '#define ROOT_PATH_NS_VAR(path) [@"/fixture-rootless" stringByAppendingString:(path)]\n');
      }
      if (mode === "roothide-sdk") {
        prefix = "/fixture-roothide"; defines.push("-DTLINK_ROOTHIDE_RUNTIME=1");
        await writeFile(join(folder, "roothide.h"), 'static inline NSString *jbroot(NSString *path){return [@"/fixture-roothide" stringByAppendingString:path];}\n');
      }
      const binary = join(folder, "paths");
      run(process.env.CXX || "clang", ["-x", "objective-c", "-Wall", "-Wextra", "-Werror", "-fobjc-arc",
        "-fsanitize=address,undefined", "-framework", "Foundation", "-I", folder,
        ...defines, `-DEXPECTED_JB_PREFIX=@"${prefix}"`, join(root, "test/jailbreak-path-runtime-test.m"), "-o", binary]);
      run(binary, []);
    }
    console.log("Jailbreak path Foundation passed: rootful, standard rootless app, libroot selector and RootHide SDK branches.");
  } else console.log("Foundation path branches require macOS CI; not executed on this host.");
} finally {
  assert.equal(dirname(temp), tempRoot); assert.ok(basename(temp).startsWith("tlink-rootless-build-"));
  await rm(temp, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
