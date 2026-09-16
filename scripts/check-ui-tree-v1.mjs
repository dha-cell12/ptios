import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const [
  fixture,
  coreHeader,
  core,
  rootServer,
  rootTask,
  rootPolicy,
  rootMakefile,
  rootEntitlements,
  trollServer,
  trollMakefile,
  trollEntitlements,
  deviceBridge,
  rootRuntime,
  smartWait,
  licensePolicy,
  rootWorkflow,
  trollWorkflow,
  docs,
] = await Promise.all([
  read("test/fixtures/ui-tree-v1.json").then(JSON.parse),
  read("shared/TLinkAccessibilityTree.h"),
  read("shared/TLinkAccessibilityTree.mm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("pccontrol/Task.xm"),
  read("shared/TLinkRootfullLicensePolicy.mm"),
  read("tlinkauto-binary/Makefile"),
  read("layout/tlinkautod-entitlements.plist"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/streamd/Makefile"),
  read("stream-app/streamd/entitlements.plist"),
  read("pccontrol/jsruntime/TLinkautoDeviceBridge.h"),
  read("pccontrol/TLinkautoJSRuntime.mm"),
  read("shared/TLinkSmartWaitPrelude.h"),
  read("license-task-policy.json").then(JSON.parse),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
  read("docs/ui-tree-v1.md"),
]);

assert.equal(fixture.phase, 1);
assert.equal(fixture.snapshotSchema, "ui_snapshot_v1");
assert.equal(fixture.backend, "axruntime_numeric_v1");
assert.equal(fixture.deviceValidated, false);
assert.equal(fixture.selectorRequiresCriterion, true);

for (const symbol of [
  "_AXUIElementCreateAppElementWithPid",
  "AXUIElementCopyAttributeValue",
  "AXUIElementSetMessagingTimeout",
  "AXValueGetValue",
  "AXUIElementCopyElementAtPosition",
]) assert.ok(core.includes(symbol), `AX symbol missing: ${symbol}`);

for (const attribute of ["3015", "2003", "2001", "2006", "5019", "2004", "2007"])
  assert.ok(core.includes(attribute), `numeric AX attribute missing: ${attribute}`);

for (const marker of [
  "TLinkAXCapabilitySnapshot",
  "TLinkAXCopyFrontmostContext",
  "TLinkAXCopySnapshot",
  "TLinkAXFindElement",
  "TLinkAXElementAtPoint",
  "ui_screen_locked",
]) assert.ok(coreHeader.includes(marker) || core.includes(marker), `core marker missing: ${marker}`);
assert.ok(rootServer.includes("ui_context_changed") && trollServer.includes("ui_context_changed"), "context-change fail-closed marker missing");

for (const source of [rootEntitlements, trollEntitlements]) {
  for (const entitlement of [
    "com.apple.private.accessibility.inspection",
    "com.apple.accessibility.api",
    "com.apple.private.accessibility.look-me-up-setup",
  ]) assert.ok(source.includes(entitlement), `entitlement missing: ${entitlement}`);
}
for (const entitlement of [
  "com.apple.backboard.client",
  "com.apple.frontboard.systemappservices",
  "proc_info-allow",
  "task_for_pid-allow",
  "com.apple.system-task-ports.read",
  "com.apple.private.xpc.launchd.per-user-lookup",
]) assert.ok(trollEntitlements.includes(entitlement), `TrollStore foreground entitlement missing: ${entitlement}`);

assert.match(rootMakefile, /TLinkAccessibilityTree\.mm/);
assert.match(rootMakefile, /tlinkautod_CODESIGN_FLAGS\s*=\s*-S\.\.\/layout\/tlinkautod-entitlements\.plist/);
assert.match(rootMakefile, /tlinkautod_FILES\s*=[^\n]*TLinkAccessibilityTree\.mm/);
assert.doesNotMatch(rootMakefile, /tlinkautob_FILES\s*=[^\n]*TLinkAccessibilityTree\.mm/);
assert.match(trollMakefile, /TLinkAccessibilityTree\.mm/);
assert.match(rootTask, /TASK_UI_TREE_CAPABILITY[\s\S]*TASK_UI_TREE_TAP/);
assert.match(rootTask, /zx_handleUITreeTask/);
assert.match(rootServer, /zx_handleUITreeTask/);
assert.match(rootServer, /#ifdef ZX_DAEMON[\s\S]*static NSDictionary \*zx_uiTreeDecodeBody[\s\S]*static NSData \*zx_handleUITreeTask[\s\S]*#endif/);
assert.match(rootServer, /case 77:[\s\S]*case 81:[\s\S]*return true;/);
assert.match(trollServer, /TLinkHandleUITreeTask/);
assert.match(trollServer, /capability\[@"foreground_context"\]/);
assert.match(trollServer, /capability\[@"implementation_version"\]\s*=\s*@4/);
assert.match(trollServer, /shared_ax_context_fallback/);
assert.match(trollServer, /SBFrontmostApplicationDisplayIdentifier/);
assert.match(trollServer, /SBSGetApplicationState/);
assert.match(trollServer, /applicationState\(\(__bridge CFStringRef\)bundleId\) == 8/);
assert.match(trollServer, /SBSCopyInfoForApplicationWithProcessID/);
assert.match(trollServer, /BKSApplicationStateAppIsFrontmost/);
assert.match(trollServer, /SBApplicationStateDisplayIDKey/);
assert.match(core, /SBFrontmostApplicationDisplayIdentifier/);
assert.match(rootServer, /finalResult\[@"tapped"\]\s*=\s*@\(true\)/);
assert.match(rootTask, /finalResult\[@"context_changed"\]\s*=\s*@\(false\)/);

for (const task of Object.values(fixture.tasks)) {
  const automation = licensePolicy.task_features.automation.map(Number);
  assert.ok(automation.includes(task), `TrollStore license policy missing UI task ${task}`);
  assert.ok(rootPolicy.includes(`{${task}, "automation"}`), `rootfull license policy missing UI task ${task}`);
}

for (const source of [rootServer, trollServer]) {
  for (const marker of [
    "uiTreeState=experimental",
    "uiTreeSchema=ui_snapshot_v1",
    "uiTreeBackend=axruntime_numeric_v1",
    "uiTreeTasks=77,78,79,80,81",
    "uiTreeDeviceValidated=0",
  ]) assert.ok(source.includes(marker), `capability marker missing: ${marker}`);
}

for (const method of ["uiTreeCapability", "uiTree", "uiFind", "uiAt", "tapElement"])
  assert.ok(deviceBridge.includes(method) && rootRuntime.includes(method) && trollServer.includes(method), `script bridge missing ${method}`);
for (const method of ["waitForElement", "waitUntilElementGone"])
  assert.ok(smartWait.includes(`api.${method} = ${method}`) && smartWait.includes(`${method}: ${method}`), `Smart Wait missing ${method}`);

assert.match(core, /default_max_elements"\s*:\s*@250/);
assert.match(core, /hard_max_elements"\s*:\s*@1000/);
assert.match(core, /TLinkAXBoundedInteger\(timeoutValue, 1500, 100, 3000\)/);
assert.match(core, /ui_selector_requires_text_identifier_or_role/);
assert.match(rootWorkflow, /node scripts\/check-ui-tree-v1\.mjs/);
assert.match(trollWorkflow, /node scripts\/check-ui-tree-v1\.mjs/);
assert.match(docs, /UI Tree v1/);

console.log("UI Tree v1 OK: shared AXRuntime core, rootfull/TrollStore tasks, entitlements, context-safe tap and JSC waits wired");
