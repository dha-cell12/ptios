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
assert.match(task, /timeline\.wait\(unsigned\(i\),unsigned\(points.size\(\)-1\)\)/);
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
  const typedTouch=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodTap])","    else if ([method isEqualToString:TLinkJSNativeMethodPickColor])");
  const colorBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodPickColor])","    else if ([method isEqualToString:TLinkJSNativeMethodScreenshotRegion])");
  const colorEntry=between(task,"// BEGIN typed color task entry.","// END typed color task entry.");
  assert.doesNotMatch(colorBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString/);
  assert.match(colorBridge,/TLinkExecuteNativeColorPick\(pick,context\)/);
  assert.match(colorEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_PICKER,&denial\)[\s\S]*getRGBAtPosition/);
  assert.doesNotMatch(colorEntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeColorBridgeUnderTest.inc"),colorBridge);
  await writeFile(join(temp,"NativeColorEntryUnderTest.inc"),colorEntry);
  const colorRangeBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFindColor])","    else if ([method isEqualToString:TLinkJSNativeMethodIsColors]");
  const colorRangeEntry=between(task,"// BEGIN typed color range task entry.","// END typed color range task entry.");
  assert.doesNotMatch(colorRangeBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString/);
  assert.match(colorRangeBridge,/TLinkExecuteNativeColorRange\(search,context\)/);
  assert.match(colorRangeEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_SEARCHER,&denial\)[\s\S]*searchRGBRange/);
  assert.doesNotMatch(colorRangeEntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeColorRangeBridge.inc"),colorRangeBridge);
  await writeFile(join(temp,"NativeColorRangeEntry.inc"),colorRangeEntry);
  const framePickBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColor])","    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColors])");
  const framePickEntry=between(task,"// BEGIN typed frame pick task entry.","// END typed frame pick task entry.");
  assert.doesNotMatch(framePickBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString/);
  assert.match(framePickBridge,/TLinkFramePickInputFits[\s\S]*invalid_payload[\s\S]*TLinkExecuteNativeFramePick/);
  assert.match(framePickEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_IN_FRAME,&denial\)[\s\S]*readFramePixel/);
  assert.doesNotMatch(framePickEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFramePickBridge.inc"),framePickBridge);
  await writeFile(join(temp,"NativeFramePickEntry.inc"),framePickEntry);
  const frameManyBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColors])","    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindColor])");
  const frameManyEntry=between(task,"// BEGIN typed frame pick-many task entry.","// END typed frame pick-many task entry.");
  assert.doesNotMatch(frameManyBridge,/executeRawPayload|stringWithFormat|componentsJoinedByString|componentsSeparatedByString/);
  assert.match(frameManyEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_IN_FRAME,&denial\)[\s\S]*readFramePixels/);
  assert.doesNotMatch(frameManyEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameManyBridge.inc"),frameManyBridge);
  await writeFile(join(temp,"NativeFrameManyEntry.inc"),frameManyEntry);
  const frameSearchBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindColor])","    else if ([method isEqualToString:TLinkJSNativeMethodFrameIsColors]");
  const frameSearchEntry=between(task,"// BEGIN typed frame search task entry.","// END typed frame search task entry.");
  assert.doesNotMatch(frameSearchBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString/);
  assert.match(frameSearchEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_IN_FRAME,&denial\)[\s\S]*searchFrameColor/);
  assert.doesNotMatch(frameSearchEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameSearchBridge.inc"),frameSearchBridge);
  await writeFile(join(temp,"NativeFrameSearchEntry.inc"),frameSearchEntry);
  const frameColorsBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFrameIsColors])","    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindMultiColor])");
  const frameColorsEntry=between(task,"// BEGIN typed frame colors task entry.","// END typed frame colors task entry.");
  assert.doesNotMatch(frameColorsBridge,/executeRawPayload|componentsSeparatedByString|componentsJoinedByString|TLinkautoJSEncodePointColorTable/);
  assert.match(frameColorsEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_IN_FRAME,&denial\)[\s\S]*testFrameColors/);
  assert.doesNotMatch(frameColorsEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameColorsBridge.inc"),frameColorsBridge);
  await writeFile(join(temp,"NativeFrameColorsEntry.inc"),frameColorsEntry);
  const frameMultiBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFrameFindMultiColor])","    else if ([method isEqualToString:TLinkJSNativeMethodFindImageInFrame])");
  const frameMultiEntry=between(task,"// BEGIN typed frame multi task entry.","// END typed frame multi task entry.");
  assert.doesNotMatch(frameMultiBridge,/executeRawPayload|componentsSeparatedByString|componentsJoinedByString|TLinkautoJSEncodePointColorTable/);
  assert.match(frameMultiBridge,/TLinkFrameMultiInputFits[\s\S]*invalid_payload[\s\S]*TLinkExecuteNativeFrameMulti/);
  assert.match(frameMultiEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_IN_FRAME,&denial\)[\s\S]*findFrameColors/);
  assert.doesNotMatch(frameMultiEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameMultiBridge.inc"),frameMultiBridge);
  await writeFile(join(temp,"NativeFrameMultiEntry.inc"),frameMultiEntry);
  const batchBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodBatch])","    else if ([method isEqualToString:TLinkJSNativeMethodRunShell])");
  const structuredBatch=between(batchBridge,"        if(structured) {","        NSMutableArray<NSString *> *wireCommands");
  assert.doesNotMatch(structuredBatch,/executeRawPayload|componentsJoinedByString|CFWriteStream|UTF8String/);
  assert.match(structuredBatch,/input.fits\(\)[\s\S]*TLinkExecuteNativeTouchBatch\(touches,context\)/);
  await writeFile(join(temp,"NativeBatchBridgeUnderTest.inc"),batchBridge);
  const helpers = between(bridge,"static NSString *TLinkautoJSSafeStringPart","static NSString *TLinkautoJSBase64Encode") +
    between(bridge,"static BOOL TLinkautoJSIsFiniteNumber","static const unsigned long long") +
    between(bridge,"static NSString *TLinkautoJSEncodePointColorTable","static NSDictionary *TLinkautoJSOCRResultByAddingDecodedError") +
    between(bridge,"static double TLinkautoJSDoubleOption","static NSString *TLinkautoJSStringOption") +
    between(bridge,"static NSString *TLinkautoJSStringOption","static NSString *TLinkautoJSOwnerField") +
    between(bridge,"static NSString *TLinkautoJSEncodeGesturePoints","static NSString *TLinkautoJSEncodePointColorTable") +
    between(bridge, "static NSString *TLinkNativeStopCode", "@protocol TLinkInProcessFacadeInterface") +
    between(bridge, "static NSString *TLinkautoJSOwnerField", "static BOOL TLinkautoJSValidToken") +
    between(bridge,"static BOOL TLinkautoJSValidToken","static BOOL TLinkautoJSValidProtocolString") +
    between(bridge, "static NSDictionary *TLinkautoJSResultByAdding", "static double TLinkautoJSDoubleOption");
  for (const name of new Set([...`${rawBridge}\n${press}\n${typedTouch}\n${batchBridge}\n${colorBridge}\n${framePickBridge}\n${frameManyBridge}\n${frameSearchBridge}\n${frameColorsBridge}\n${frameMultiBridge}\n${colorRangeBridge}`.matchAll(/\b(TLinkautoJS\w+)\s*\(/g)].map(match => match[1]))) {
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
  assert.doesNotMatch(typedTouch,/executeRawPayload|stringWithFormat|CFWriteStream/);
  assert.equal([...typedTouch.matchAll(/TLinkExecuteNativeTouch\(touch,context\)/g)].length,5);
  await writeFile(join(temp,"NativeTouchBridgeUnderTest.inc"),typedTouch);
  const entry=between(task,"// BEGIN typed touch task entry.","// END typed touch task entry.");
  assert.match(entry,/TLinkRootfullLicenseTaskAllowed\(taskType,&denial\)/);
  assert.match(entry,/budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed[\s\S]*budget->stopped\(\)[\s\S]*zx_executeNativeTap/);
  assert.doesNotMatch(entry,/processTaskWithContext|CFWriteStreamCreate|appendCString/);
  const batchEntry=entry.slice(entry.indexOf('NSDictionary *TLinkExecuteNativeTouchBatch'));
  assert.match(batchEntry,/TLinkRootfullLicenseTaskAllowed\(TASK_NATIVE_BATCH,&denial\)/);
  assert.equal([...batchEntry.matchAll(/TLinkRootfullLicenseTaskAllowed/g)].length,1);
  assert.doesNotMatch(batchEntry,/TLinkExecuteNativeTouch\(|zx_handleNative|processTaskWithContext/);

  assert.match(entry,/zx_executeNativeGesture\(request.points/);assert.match(entry,/zx_zoomBegin\(\);zx_executeNativeZoom/);
  assert.match(typedTouch,/TLinkNativeGestureInputFits/);
  assert.doesNotMatch(entry,/\b(?:YES|NO)\b/,'typed Task entry must compile after Image.h undefines Objective-C boolean macros');
  const runtimeFixture=await read('test/native-bridge-budget-runtime-test.mm');
  assert.match(runtimeFixture,/#undef YES\n#undef NO\n#include "NativeTouchEntryUnderTest.inc"\n#include "NativeColorEntryUnderTest.inc"\n#include "NativeColorRangeEntry.inc"\n#include "NativeFramePickEntry.inc"/);
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
