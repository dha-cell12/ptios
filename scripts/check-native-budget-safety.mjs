import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = async path => (await readFile(join(root, path), "utf8")).replaceAll("\r\n", "\n");
const [bridge, task, socket, image, template, tess, vision, ax, context] = await Promise.all([
  "pccontrol/jsruntime/TLinkInProcessNativeBridge.mm", "pccontrol/Task.xm", "pccontrol/SocketResponder.xm",
  "pccontrol/Image.xm", "pccontrol/TemplateMatch.xm", "pccontrol/TesseractOCRTask.mm",
  "pccontrol/TextRecognization/VKOcrManager.xm", "shared/TLinkAccessibilityTree.mm", "pccontrol/TLinkTaskContext.mm"
].map(read));
assert.doesNotMatch(bridge, /CFWriteStreamCreateWithAllocatedBuffers|kCFStreamPropertyDataWritten/);
assert.match(bridge, /payload.length > 8192\) return TLinkNativeFailure\(@"input_too_large"\)/);
assert.match(bridge, /payloadData.length > 32 \* 1024 \|\| memchr/);
assert.match(bridge, /processTaskWithContext\([\s\S]*?\[payloadData length\] - 1, stream, call\)/);
assert.match(bridge, /@finally \{ CFWriteStreamClose\(stream\); CFRelease\(stream\); \}/);
assert.match(bridge, /if \(\(frameCreate \|\| imageCreate\)[\s\S]*?executeRawPayload:release context:context/);
assert.match(bridge, /@try \{\s*down = \[self executeRequest:[\s\S]*?@finally \{\s*up = \[self executeRequest:/);
assert.match(context, /inherited && std::isfinite\(parent.defaultTimeoutSeconds\) && parent.defaultTimeoutSeconds > 0 \? parent.defaultTimeoutSeconds : 30.0/);
assert.match(context, /std::min\(deadline, inherited->deadline\(\)\)/);
assert.match(socket, /capturesResponse\(\)\) return budget->appendCString\(msg\)/);
assert.match(task, /TLinkNativeBudgetScope taskScope\(TLinkTaskBudget\(context\)\)/);
assert.match(task, /License refresh may wait for IPC; recheck before committing an action/);
assert.match(task, /@finally \{ zx_performSingleTouch\(TOUCH_UP/g);
assert.match(task, /TLinkGestureTimeline timeline/);
assert.match(task, /timeline\.wait\(unsigned\(i\), unsigned\(pointTexts.count - 1\)\)/);
const numericTouches = task.slice(task.indexOf("static void zx_performSingleTouch"), task.indexOf("static NSArray<NSString *> *zx_splitTaskParts"));
assert.match(numericTouches, /performTouchFrame\(&point, 1\)/);
assert.match(numericTouches, /performTouchFrame\(frame, count\)/);
assert.doesNotMatch(numericTouches, /stringWithFormat|appendFormat|UTF8String|performTouchFromRawData/);
assert.match(task, /if \(!completed\) ownedTouches.release/);
assert.match(tess, /shouldCancelImageRecognitionForTesseract/);
assert.match(tess, /@finally \{ tesseract.delegate = nil; tesseract.image = nil; \}/);
assert.match(vision, /current&&current->stopped\(\)\)\[activeRequest cancel\]/);
assert.match(vision, /@finally[\s\S]*dispatch_source_cancel\(monitor\);dispatch_sync\(monitorQueue/);
assert.match(vision, /@synchronized\(self\)\{inProgress=false;\}/);
assert.match(ax, /estimatedJSONBytes \+= rowBytes/);
for (const source of [image, tess, ax]) {
  assert.match(source, /TLinkNativeDispatchSync\(/);
  assert.doesNotMatch(source, /dispatch_sync\((zx_imageQueue|zx_tessQueue|TLinkAXQueue)\(\)/);
}
assert.match(await read("pccontrol/ScriptPlayer.xm"), /setNativeBudget:TLinkTaskBudget\(session.taskContext\)/);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-native-budget-"));
function between(source, start, end) {
  const a = source.indexOf(start); const b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `missing source boundary ${start}`);
  return source.slice(a, b);
}
function run(command, args, timeout = 120000) {
  const result = spawnSync(command, args, { cwd: root, encoding: "utf8", timeout });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed (signal=${result.signal})`);
}
try {
  for (const [source, name] of [[image, "Image"], [template, "Template"]]) {
    const body = between(source, "static long long zx_sad_match_region", "\n}") + "\n}\n";
    await writeFile(join(temp, `${name}SadUnderTest.inc`), body.replaceAll("zx_sad_match_region", `${name.toLowerCase()}SadUnderTest`));
  }
  await writeFile(join(temp, "ImageScaleUnderTest.inc"),
    (between(image, "static BOOL zx_findTemplateSAD", "\n}") + "\n}\n")
      .replaceAll("zx_sad_match_region", "imageSadUnderTest"));
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "native-budget-test.exe" : "native-budget-test");
  const files = ["test/native-budget-safety-test.cpp", "test/native-budget-scope-peer.cpp"].map(p => join(root, p));
  run(compiler, msvc
    ? ["/nologo", "/std:c++14", "/W4", "/WX", "/EHsc", `/I${temp}`, ...files, `/Fe${binary}`, `/Fo${temp}\\`]
    : ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-pthread", "-I", temp, ...files, "-o", binary]);
  run(binary, []);
  // Extract and check fixture dependencies on every host, even when Foundation is unavailable.
  const rawBridge = between(bridge, "// BEGIN bounded native dispatch", "// END bounded native dispatch.");
  const press = between(bridge, "    else if ([method isEqualToString:TLinkJSNativeMethodPressHardwareKey])",
    "    else if ([method isEqualToString:TLinkJSNativeMethodKeepAwake])");
  const helpers = between(bridge, "static NSString *TLinkNativeStopCode", "@protocol TLinkInProcessFacadeInterface") +
    between(bridge, "static NSString *TLinkautoJSOwnerField", "static BOOL TLinkautoJSStringContainsAny") +
    between(bridge, "static NSDictionary *TLinkautoJSResultByAdding", "static double TLinkautoJSDoubleOption");
  for (const name of new Set([...`${rawBridge}\n${press}`.matchAll(/\b(TLinkautoJS\w+)\s*\(/g)].map(match => match[1]))) {
    assert.ok(helpers.includes(`${name}(`), `missing production helper in native fixture: ${name}`);
  }
  await writeFile(join(temp, "NativeBridgeUnderTest.inc"), rawBridge);
  await writeFile(join(temp, "NativeHelpersUnderTest.inc"), helpers);
  await writeFile(join(temp, "NativeRequestPreludeUnderTest.inc"),
    between(bridge, "    NSString *method = request.method;", "    id<TLinkInProcessFacadeInterface> runtime"));
  await writeFile(join(temp, "NativePressUnderTest.inc"), press);
  await writeFile(join(temp, "NativeGesturesUnderTest.inc"),
    between(task, "static std::atomic<uint64_t> sTLinkZoomAttemptCount", "static NSDictionary *zx_zoomDiagnostics") +
    between(task, "static int zx_clampTouchCoord", "// BEGIN typed touch task entry."));
  await writeFile(join(temp, "NativeTouchEntryUnderTest.inc"),between(task,"// BEGIN typed touch task entry.","// END typed touch task entry."));
  const typedTouch=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodTap])","    else if ([method isEqualToString:TLinkJSNativeMethodGesture])");
  assert.doesNotMatch(typedTouch,/executeRawPayload|stringWithFormat|CFWriteStream/);
  assert.equal([...typedTouch.matchAll(/TLinkExecuteNativeTouch\(touch,context\)/g)].length,3);
  await writeFile(join(temp,"NativeTouchBridgeUnderTest.inc"),typedTouch);
  const entry=between(task,"// BEGIN typed touch task entry.","// END typed touch task entry.");
  assert.match(entry,/TLinkRootfullLicenseTaskAllowed\(taskType,&denial\)/);
  assert.match(entry,/budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed[\s\S]*budget->stopped\(\)[\s\S]*zx_executeNativeTap/);
  assert.doesNotMatch(entry,/processTaskWithContext|CFWriteStreamCreate|appendCString/);
  assert.doesNotMatch(entry,/\b(?:YES|NO)\b/,'typed Task entry must compile after Image.h undefines Objective-C boolean macros');
  const runtimeFixture=await read('test/native-bridge-budget-runtime-test.mm');
  assert.match(runtimeFixture,/#undef YES\n#undef NO\n#include "NativeTouchEntryUnderTest.inc"/);
  console.log("macOS fixture extraction: production bridge helpers present on this host.");
  if (process.platform === "darwin") {
    const runtime = join(temp, "native-bridge-runtime-test");
    run(compiler, ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-Wno-unused-variable", "-Wno-deprecated-declarations",
      "-fobjc-arc", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-framework", "Foundation", "-framework", "CoreFoundation", "-framework", "CoreGraphics",
      "-I", temp, "-I", join(root, "pccontrol"), join(root, "test/native-bridge-budget-runtime-test.mm"),
      join(root, "pccontrol/TLinkTaskContext.mm"), join(root, "pccontrol/jsruntime/TLinkJSNativeRequest.mm"),
      join(root, "pccontrol/jsruntime/TLinkJSNativeResponse.mm"), "-x", "objective-c++", join(root, "pccontrol/SocketResponder.xm"), "-o", runtime]);
    run(runtime, []);
  } else console.log("macOS actual bridge/context/response/gesture integration is included in CI; not run on this host.");
} finally {
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-native-budget-"));
  await rm(temp, { recursive: true, force: true });
}
