import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");

const [
  makefile,
  workflow,
  pathHelper,
  task,
  shellHelper,
  daemon,
  popup,
  tweak,
  appSettings,
  playSettings,
  verifier,
  preinst,
  postinst,
  stageScript,
] = await Promise.all([
  read("Makefile"),
  read(".github/workflows/build.yml"),
  read("shared/TLinkJailbreakPath.h"),
  read("pccontrol/Task.xm"),
  read("pccontrol/Common.xm"),
  read("tlinkauto-binary/main.mm"),
  read("pccontrol/Popup.xm"),
  read("pccontrol/Tweak.xm"),
  read("TLinkauto/TLinkauto/Settings/SettingsPageViewController.m"),
  read("TLinkauto/TLinkauto/ScriptPlaySettings/PlaySettingsViewController.m"),
  read("shared/TLinkLicenseVerifier.mm"),
  read("layout/DEBIAN/preinst"),
  read("layout/DEBIAN/postinst"),
  read("scripts/prepare-roothide-stage.mjs"),
]);

assert.match(makefile, /TLINK_PACKAGE_RUNTIME \?= rootfull/);
assert.match(makefile, /THEOS_PACKAGE_SCHEME = roothide/);
assert.match(makefile, /DEB_ARCH = iphoneos-arm64e/);
assert.match(makefile, /TARGET = iphone:clang:latest:15\.0/);
assert.match(makefile, /IPHONEOS_DEPLOYMENT_TARGET = 15\.0/);
assert.match(makefile, /prepare-roothide-stage\.mjs" --rootfs/);
assert.match(workflow, /package_runtime: \[rootfull, roothide\]/);
assert.match(workflow, /github\.com\/roothide\/theos\.git/);
assert.match(workflow, /TLINK_ROOTHIDE_RUNTIME/);
assert.match(workflow, /EXPECTED_ARCH="iphoneos-arm64e"/);
assert.match(workflow, /XCODE_RUNTIME_SETTINGS=\(ONLY_ACTIVE_ARCH=NO\)/);
assert.doesNotMatch(workflow, /XCODE_RUNTIME_SETTINGS=\(\)/);

assert.match(pathHelper, /dlsym\(RTLD_DEFAULT, "jbroot"\)/);
assert.match(pathHelper, /#include <roothide\.h>/);
assert.match(pathHelper, /return jbroot\(path\)/);
assert.match(pathHelper, /stringByAppendingPathComponent:@"\.jbroot"/);
assert.match(pathHelper, /roothide_jbroot_paths_v1/);
assert.match(task, /TLinkJailbreakPath\(@"\/usr\/bin\/sudo"\)/);
assert.match(task, /TLinkJailbreakPath\(@"\/usr\/bin\/tlinkautob"\)/);
assert.match(shellHelper, /TLinkJailbreakPath\(@"\/bin\/sh"\)/);
assert.match(daemon, /TLinkJailbreakPath\(@"\/bin\/sh"\)/);
assert.match(popup, /TLinkJailbreakPath\(@"\/Library\/Application Support\/TLinkauto/);
assert.match(tweak, /TLinkJailbreakPath\(@"\/usr\/lib\/libactivator\.dylib"\)/);
assert.match(appSettings, /TLinkJailbreakPath\(@"\/usr\/lib\/libactivator\.dylib"\)/);
assert.match(playSettings, /TLinkJailbreakPath\(@"\/usr\/lib\/libactivator\.dylib"\)/);
assert.match(verifier, /TLinkJailbreakPath\(@"\/Applications\/TLinkauto\.app"\)/);

for (const script of [preinst, postinst]) {
  assert.match(script, /if \[ -d \/rootfs\/var\/mobile \]/);
  assert.match(script, /TLINK_DATA_ROOT="\/rootfs\/var\/mobile\/Library\/TLinkauto"/);
}
assert.match(postinst, /cp -R \/var\/mobile\/Library\/TLinkauto\/\. "\$TLINK_DATA_ROOT\/"/);
assert.match(stageScript, /\/rootfs\/var\/mobile\/Library\/TLinkauto\//);

const roothideEntitlements = [
  "layout/roothide-service-entitlements.plist",
  "layout/entitlements-roothide.plist",
  "layout/shortcut-entitlements-roothide.plist",
  "layout/license-authority-entitlements-roothide.plist",
  "layout/tlinkautod-entitlements-roothide.plist",
];
for (const path of roothideEntitlements) {
  const plist = await read(path);
  for (const key of [
    "platform-application",
    "com.apple.private.security.no-sandbox",
    "com.apple.private.security.storage.AppBundles",
    "com.apple.private.security.storage.AppDataContainers",
  ]) {
    assert.ok(plist.includes(`<key>${key}</key>`), `${path} is missing ${key}`);
  }
}

console.log("Roothide build contract OK: scheme, architecture, entitlements and jbroot paths");
