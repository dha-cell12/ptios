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
  const colorPointsBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodIsColors])","    else if ([method isEqualToString:TLinkJSNativeMethodFindMultiColor])");
  const colorPointsEntry=between(task,"// BEGIN typed color points task entry.","// END typed color points task entry.");
  assert.doesNotMatch(colorPointsBridge,/executeRawPayload|TLinkautoJSEncodePointColorTable|componentsSeparatedByString|componentsJoinedByString/);
  assert.match(colorPointsBridge,/TLinkNativeColorPointsInputFits[\s\S]*TLinkExecuteNativeColorPoints/);
  assert.match(colorPointsEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_SEARCHER,&denial\)[\s\S]*testRGBPoints/);
  assert.doesNotMatch(colorPointsEntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeColorPointsBridge.inc"),colorPointsBridge);
  await writeFile(join(temp,"NativeColorPointsEntry.inc"),colorPointsEntry);
  const colorMultiBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFindMultiColor])",'    return [TLinkJSNativeResponse responseWithError:[NSString stringWithFormat:@"Unimplemented method:');
  const colorMultiEntry=between(task,"// BEGIN typed color multi task entry.","// END typed color multi task entry.");
  assert.doesNotMatch(colorMultiBridge,/executeRawPayload|TLinkautoJSEncodePointColorTable|componentsSeparatedByString|componentsJoinedByString/);
  assert.match(colorMultiBridge,/TLinkNativeColorMultiInputFits[\s\S]*TLinkExecuteNativeColorMulti/);
  assert.match(colorMultiEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_COLOR_SEARCHER,&denial\)[\s\S]*searchRGBMulti/);
  assert.doesNotMatch(colorMultiEntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeColorMultiBridge.inc"),colorMultiBridge);
  await writeFile(join(temp,"NativeColorMultiEntry.inc"),colorMultiEntry);
  const frameImageBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFindImageInFrame])","    else if ([method isEqualToString:TLinkJSNativeMethodOcrLanguages])");
  const frameImageEntry=between(task,"// BEGIN typed frame image task entry.","// END typed frame image task entry.");
  assert.doesNotMatch(frameImageBridge,/executeRawPayload|componentsSeparatedByString|componentsJoinedByString/);
  assert.match(frameImageBridge,/TLinkNativeFrameImageInputFits[\s\S]*invalid_payload[\s\S]*TLinkExecuteNativeFrameImage/);
  assert.match(frameImageEntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_FIND_IMAGE_IN_FRAME,&denial\)[\s\S]*matchImageInFrame/);
  assert.doesNotMatch(frameImageEntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameImageBridge.inc"),frameImageBridge);
  await writeFile(join(temp,"NativeFrameImageEntry.inc"),frameImageEntry);
  const frameCaptureBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodCaptureFrame])","    else if ([method isEqualToString:TLinkJSNativeMethodReleaseFrame])");
  const frameCaptureEntry=between(task,"// BEGIN typed frame capture task entry.","// END typed frame capture task entry.");
  assert.doesNotMatch(frameCaptureBridge,/executeRawPayload/);
  assert.match(frameCaptureEntry,/outputLimit\(\)<1024[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_FRAME_CAPTURE,&denial\)[\s\S]*captureStoredFrame/);
  assert.match(frameCaptureEntry,/@finally[\s\S]*!committed&&publishedId[\s\S]*TLinkNativeCallContext\(call,true,false\)[\s\S]*releaseStoredFrames/);
  assert.doesNotMatch(frameCaptureEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  assert.doesNotMatch(frameCaptureBridge,/result\[@"parts"\]|SafeStringPart|NSMutableDictionary/);
  assert.match(frameCaptureEntry,/TLinkNativeFrameCaptureValue value[\s\S]*TLinkNativeFrameCaptureResult\(value\)[\s\S]*outputAllowed[\s\S]*committed=true/);
  const captureResult=await readFile(join(root,"shared/TLinkNativeFrameCaptureResult.h"),"utf8");
  assert.doesNotMatch(captureResult,/componentsSeparatedByString|\b(?:YES|NO)\b/);
  assert.match(captureResult,/componentsJoinedByString[\s\S]*created\.longLongValue/);
  await writeFile(join(temp,"NativeFrameCaptureBridge.inc"),frameCaptureBridge);
  await writeFile(join(temp,"NativeFrameCaptureEntry.inc"),frameCaptureEntry);
  const imageCaptureBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodCaptureImage])","    else if ([method isEqualToString:TLinkJSNativeMethodReleaseImage])");
  const imageCaptureEntry=between(task,"// BEGIN typed image capture task entry.","// END typed image capture task entry.");
  assert.doesNotMatch(imageCaptureBridge,/executeRawPayload|result\[@"parts"\]|SafeStringPart|NSMutableDictionary/);
  assert.match(imageCaptureBridge,/TLinkNativeImageCaptureJSInt[\s\S]*TLinkNativeImageCaptureInputFits[\s\S]*TLinkExecuteNativeImageCapture/);
  assert.match(imageCaptureEntry,/outputLimit\(\)<1024[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_IMAGE_OBJECT,&denial\)[\s\S]*captureStoredImage[\s\S]*TLinkNativeImageResult[\s\S]*outputAllowed[\s\S]*committed=true/);
  assert.match(imageCaptureEntry,/@finally[\s\S]*!committed&&publishedId[\s\S]*TLinkNativeCallContext\(call,true,false\)[\s\S]*releaseStoredImages/);
  assert.doesNotMatch(imageCaptureEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeImageCaptureBridge.inc"),imageCaptureBridge);
  await writeFile(join(temp,"NativeImageCaptureEntry.inc"),imageCaptureEntry);
  const imageOpenBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodOpenImage])","    else if ([method isEqualToString:TLinkJSNativeMethodCaptureImage])");
  const imageOpenEntry=between(task,"// BEGIN typed image open task entry.","// END typed image open task entry.");
  assert.doesNotMatch(imageOpenBridge,/executeRawPayload/);
  assert.match(imageOpenBridge,/TLinkNativeImageOpenInputFits[\s\S]*TLinkNativeImageOpenBytesFit[\s\S]*TLinkExecuteNativeImageOpen/);
  assert.match(imageOpenEntry,/outputLimit\(\)<1024[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_IMAGE_OBJECT,&denial\)[\s\S]*openStoredImage/);
  assert.match(imageOpenEntry,/@finally[\s\S]*!committed&&publishedId[\s\S]*TLinkNativeCallContext\(call,true,false\)[\s\S]*releaseStoredImages/);
  assert.doesNotMatch(imageOpenEntry,/processTaskWithContext|CFWriteStream|componentsSeparatedByString|\b(?:YES|NO)\b/);
  assert.doesNotMatch(imageOpenBridge,/result\[@"parts"\]|SafeStringPart|NSMutableDictionary/);
  assert.match(imageOpenEntry,/TLinkNativeImageValue value[\s\S]*TLinkNativeImageResult\(value\)[\s\S]*outputAllowed[\s\S]*committed=true/);
  const imageResult=await readFile(join(root,"shared/TLinkNativeImageResult.h"),"utf8");
  assert.doesNotMatch(imageResult,/componentsSeparatedByString|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeImageOpenBridge.inc"),imageOpenBridge);
  await writeFile(join(temp,"NativeImageOpenEntry.inc"),imageOpenEntry);
  const imageReleaseBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodReleaseImage])","    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColor])");
  const imageReleaseEntry=between(task,"// BEGIN typed image release task entry.","// END typed image release task entry.");
  assert.doesNotMatch(imageReleaseBridge,/executeRawPayload|stringByTrimmingCharactersInSet/);
  assert.match(imageReleaseEntry,/TLinkNativeCallContext\(context,true,false\)/);
  assert.doesNotMatch(imageReleaseEntry,/processTaskWithContext|CFWriteStream|TLinkRootfullLicenseTaskAllowed|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeImageReleaseBridge.inc"),imageReleaseBridge);
  await writeFile(join(temp,"NativeImageReleaseEntry.inc"),imageReleaseEntry);
  const frameReleaseBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodReleaseFrame])","    else if ([method isEqualToString:TLinkJSNativeMethodOpenImage])");
  const frameReleaseEntry=between(task,"// BEGIN typed frame release task entry.","// END typed frame release task entry.");
  assert.doesNotMatch(frameReleaseBridge,/executeRawPayload/);
  assert.match(frameReleaseEntry,/TLinkNativeCallContext\(context,true,false\)/);
  assert.doesNotMatch(frameReleaseEntry,/processTaskWithContext|CFWriteStream|TLinkRootfullLicenseTaskAllowed|\b(?:YES|NO)\b/);
  await writeFile(join(temp,"NativeFrameReleaseBridge.inc"),frameReleaseBridge);
  await writeFile(join(temp,"NativeFrameReleaseEntry.inc"),frameReleaseEntry);
  const frameOCRBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodOcrFrame])","    else if ([method isEqualToString:TLinkJSNativeMethodOcr])");
  const frameOCREntry=between(task,"// BEGIN typed frame OCR task entry.","// END typed frame OCR task entry.");
  assert.doesNotMatch(frameOCRBridge,/executeRawPayload|componentsJoinedByString/);
  assert.match(frameOCRBridge,/TLinkNativeOCRInputFits[\s\S]*invalid_payload[\s\S]*TLinkExecuteNativeFrameOCR/);
  assert.match(frameOCREntry,/TLinkC01TaskBudget[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_OCR_TESSERACT_REGION,&denial\)[\s\S]*recognizeFrameWithTesseract/);
  assert.doesNotMatch(frameOCREntry,/processTaskWithContext|CFWriteStream|\b(?:YES|NO)\b/);
  assert.match(frameOCREntry,/return zx_typedFrameOCRReply\(error\.localizedDescription/,'OCR bodies require column-aware status handling, not touch-only success');
  assert.match(frameOCREntry,/"ok":@\(\[status isEqualToString:@"0"\]\)/);
  await writeFile(join(temp,"NativeFrameOCRBridge.inc"),frameOCRBridge);
  await writeFile(join(temp,"NativeFrameOCREntry.inc"),frameOCREntry);
  const frameOCRResult=between(tess,"// BEGIN structured frame OCR result.","// END structured frame OCR result.");
  assert.doesNotMatch(frameOCRResult,/initWithBase64EncodedString|componentsSeparatedByString/);
  assert.doesNotMatch(frameOCREntry.slice(frameOCREntry.indexOf("NSDictionary *TLinkExecuteNativeFrameOCR")),/componentsSeparatedByString|initWithBase64EncodedString/);
  assert.doesNotMatch(frameOCRBridge.slice(frameOCRBridge.indexOf("NSDictionary *result=TLinkExecuteNativeFrameOCR")),/TLinkautoJSBase64Decode|TLinkautoJSSafeStringPart/);
  await writeFile(join(temp,"NativeFrameOCRResult.inc"),frameOCRResult);
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
  const frontmostBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodFrontMostAppId])","    else if ([method isEqualToString:TLinkJSNativeMethodOpenApp]");
  const frontmostEntry=between(task,"// BEGIN typed frontmost task entry.","// END typed frontmost task entry.");
  assert.equal([...frontmostBridge.matchAll(/TLinkExecuteNativeFrontmost\(/g)].length,2);
  assert.doesNotMatch(frontmostBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString|CFWriteStream/);
  assert.match(frontmostEntry,/TLinkNativeCallContext\(context,false,false\)[\s\S]*budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed\(taskType,&denial\)[\s\S]*budget->stopped\(\)[\s\S]*frontMostAppId\(\)/);
  assert.equal([...frontmostEntry.matchAll(/TLinkRootfullLicenseTaskAllowed\(/g)].length,1);
  assert.match(frontmostEntry,/outputAllowed\(length\)[\s\S]*if\(compatibility\)[\s\S]*else parts=@\[@"0",body\]/);
  assert.doesNotMatch(frontmostEntry,/processTaskWithContext|CFWriteStream|TLinkC01|\b(?:YES|NO)\b/);
  const frontmostLegacy=await read("test/fixtures/frontmost-handler-legacy-v1.inc");
  assert.equal(between(task,"    else if (taskType == TASK_FRONTMOST_APP_ID)","    else if (taskType == TASK_SET_AUTO_LAUNCH)").trim(),frontmostLegacy.slice(frontmostLegacy.indexOf('\n')+1).trim());
  await writeFile(join(temp,"NativeFrontmostBridge.inc"),frontmostBridge);
  await writeFile(join(temp,"NativeFrontmostEntry.inc"),frontmostEntry);
  const pathBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodRootDir]","    else if ([method isEqualToString:TLinkJSNativeMethodInfo])");
  const pathEntry=between(task,"// BEGIN typed path task entry.","// END typed path task entry.");
  assert.match(pathBridge,/TLinkExecuteNativePath\(task,context\)/);
  assert.doesNotMatch(pathBridge,/executeRawPayload|stringWithFormat|componentsSeparatedByString|CFWriteStream/);
  assert.match(pathEntry,/TLinkNativeCallContext\(context,false,false\)[\s\S]*budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed\(taskType,&denial\)[\s\S]*budget->stopped\(\)[\s\S]*rootDirValue\(\)[\s\S]*currentDirValue\(\)[\s\S]*botPathValue\(\)/);
  assert.equal([...pathEntry.matchAll(/TLinkRootfullLicenseTaskAllowed\(/g)].length,1);
  assert.match(frontmostEntry,/static NSDictionary \*zx_nativeStringQueryResult\(/);
  assert.match(pathEntry,/zx_nativeStringQueryResult\(value,key,false,@"path",budget\)[\s\S]*budget->stopped\(\)/);
  assert.doesNotMatch(pathEntry,/processTaskWithContext|CFWriteStream|TLinkC01|\b(?:YES|NO)\b/);
  const pathLegacy=await read("test/fixtures/path-handler-legacy-v1.inc");
  assert.equal(between(task,"    else if (taskType == TASK_ROOT_DIR)","    else if (taskType == TASK_SCREENSHOT)").trim(),pathLegacy.slice(pathLegacy.indexOf('\n')+1).trim());
  await writeFile(join(temp,"NativePathBridge.inc"),pathBridge);
  await writeFile(join(temp,"NativePathEntry.inc"),pathEntry);
  const hardware=await read("pccontrol/HardwareKey.xm");
  const hardwareBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodHardwareKey])","    else if ([method isEqualToString:TLinkJSNativeMethodPressHardwareKey])");
  const hardwareEntry=between(task,"// BEGIN typed hardware key task entry.","// END typed hardware key task entry.");
  assert.match(hardwareBridge,/keyType <= 0 \|\| keyAction < 0[\s\S]*TLinkExecuteNativeHardwareKey\(keyAction,keyType,context\)/);
  assert.doesNotMatch(hardwareBridge,/executeRawPayload|stringWithFormat|CFWriteStream/);
  assert.match(hardwareEntry,/cleanup=action==HARDWARE_KEY_ACTION_UP[\s\S]*TLinkNativeCallContext\(context,cleanup,false\)[\s\S]*budget->stopped\(\)[\s\S]*!cleanup&&!TLinkRootfullLicenseTaskAllowed\(TASK_HARDWARE_KEY,&denial\)[\s\S]*budget->stopped\(\)[\s\S]*sendHardwareKeyEvent\(action,keyType,&error\)/);
  assert.equal([...hardwareEntry.matchAll(/TLinkRootfullLicenseTaskAllowed\(/g)].length,1);
  assert.doesNotMatch(hardwareEntry,/processTaskWithContext|CFWriteStream|FromRawData|TLinkC01|\b(?:YES|NO)\b/);
  assert.match(hardware,/return sendHardwareKeyEvent\(\[data\[0\] intValue\],\[data\[1\] intValue\],error\)/);
  const hardwareCore=hardware.slice(hardware.indexOf('static IOHIDEventSystemClientRef hardwareKeyClient'));
  const numericHardware=hardware.slice(hardware.indexOf('int sendHardwareKeyEvent(int action'));
  assert.match(numericHardware,/isDown = action == HARDWARE_KEY_ACTION_DOWN/);
  assert.match(numericHardware,/@try \{ IOHIDEventSystemClientDispatchEvent[\s\S]*@finally \{ CFRelease\(event\); \}/);
  assert.doesNotMatch(numericHardware,/componentsSeparatedByString|stringWithUTF8String/);
  const hardwareLegacy=await read("test/fixtures/hardware-key-handler-legacy-v1.inc");
  assert.equal(between(task,"    else if (taskType == TASK_HARDWARE_KEY)","    else if (taskType == TASK_APP_KILL)").trim(),hardwareLegacy.slice(hardwareLegacy.indexOf('\n')+1).trim());
  await writeFile(join(temp,"NativeHardwareKeyBridge.inc"),hardwareBridge);
  await writeFile(join(temp,"NativeHardwareKeyEntry.inc"),hardwareEntry);
  await writeFile(join(temp,"HardwareKeyCoreUnderTest.inc"),hardwareCore);
  const scheduler=await read("pccontrol/Scheduler.xm");
  const awakeBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodKeepAwake])","    else if ([method isEqualToString:TLinkJSNativeMethodTouchIndicator])");
  const awakeEntry=between(task,"// BEGIN typed keep awake task entry.","// END typed keep awake task entry.");
  const awakeCore=between(scheduler,"NSString* keepAwakeFromRawData","NSString* stopScriptFromRawData");
  assert.match(awakeBridge,/boolValue[\s\S]*TLinkExecuteNativeKeepAwake\(enabled,context\)/);
  assert.doesNotMatch(awakeBridge,/executeRawPayload|stringWithFormat|CFWriteStream/);
  assert.match(awakeEntry,/TLinkNativeCallContext\(context,false,false\)[\s\S]*budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_KEEP_AWAKE,&denial\)[\s\S]*budget->stopped\(\)[\s\S]*TLinkSetKeepAwakeEnabled\(enabled\)[\s\S]*zx_typedTouchReply/);
  assert.equal([...awakeEntry.matchAll(/TLinkRootfullLicenseTaskAllowed\(/g)].length,1);
  assert.doesNotMatch(awakeEntry,/processTaskWithContext|CFWriteStream|FromRawData|TLinkC01|\b(?:YES|NO)\b/);
  assert.match(awakeCore,/BOOL enabled = \[value intValue\] != 0;[\s\S]*TLinkSetKeepAwakeEnabled\(enabled\)/);
  assert.match(awakeCore,/void TLinkSetKeepAwakeEnabled\(BOOL enabled\)[\s\S]*dispatch_async\(dispatch_get_main_queue\(\),[\s\S]*idleTimerDisabled = enabled/);
  const awakeLegacy=await read("test/fixtures/keep-awake-handler-legacy-v1.inc");
  assert.equal(between(task,"    else if (taskType == TASK_KEEP_AWAKE)","    else if (taskType == TASK_APP_PID)").trim(),awakeLegacy.slice(awakeLegacy.indexOf('\n')+1).trim());
  await writeFile(join(temp,"NativeKeepAwakeBridge.inc"),awakeBridge);
  await writeFile(join(temp,"NativeKeepAwakeEntry.inc"),awakeEntry);
  await writeFile(join(temp,"KeepAwakeCoreUnderTest.inc"),awakeCore);
  const awakeLegacyCore=await read("test/fixtures/keep-awake-core-legacy-v1.inc");
  const awakeLegacySignature="NSString* keepAwakeFromRawData(UInt8 *eventData, NSError **error)\n{\n";
  assert.ok(awakeLegacyCore.includes(awakeLegacySignature));
  // Preserve the frozen oracle; explicitly consume its unused out-parameter in the generated fixture.
  await writeFile(join(temp,"KeepAwakeLegacyCoreUnderTest.inc"),awakeLegacyCore.replace(awakeLegacySignature,
    awakeLegacySignature+"    (void)error;\n"));
  const indicator=await read("pccontrol/TouchIndicator/TouchIndicatorWindow.xm");
  const indicatorBridge=between(bridge,"    else if ([method isEqualToString:TLinkJSNativeMethodTouchIndicator])","    else if ([method isEqualToString:TLinkJSNativeMethodSaveScreenshotToAlbum])");
  const indicatorEntry=between(task,"// BEGIN typed indicator task entry.","// END typed indicator task entry.");
  const indicatorCore=between(indicator,"void startTouchIndicator(NSError **error)","static void IOHIDEventCallbackForTouchIndicator");
  assert.match(indicatorBridge,/value < 0[\s\S]*TLinkExecuteNativeIndicator\(value,context\)/);
  assert.doesNotMatch(indicatorBridge,/executeRawPayload|stringWithFormat|CFWriteStream/);
  assert.match(indicatorEntry,/action<0[\s\S]*TLinkNativeCallContext\(context,false,false\)[\s\S]*budget->stopped\(\)[\s\S]*TLinkRootfullLicenseTaskAllowed\(TASK_TOUCH_INDICATOR,&denial\)[\s\S]*budget->stopped\(\)[\s\S]*handleTouchIndicatorAction\(action,&error\)/);
  assert.equal([...indicatorEntry.matchAll(/TLinkRootfullLicenseTaskAllowed\(/g)].length,1);
  assert.doesNotMatch(indicatorEntry,/processTaskWithContext|CFWriteStream|WithRawData|TLinkC01|\b(?:YES|NO)\b/);
  assert.match(indicatorCore,/stringByTrimmingCharactersInSet:[\s\S]*isEqualToString:@"0"[\s\S]*isEqualToString:@"1"[\s\S]*isEqualToString:@"2"[\s\S]*: -1;[\s\S]*handleTouchIndicatorAction\(value, error\)/);
  const numericIndicator=indicatorCore.slice(indicatorCore.indexOf('void handleTouchIndicatorAction(int action'));
  assert.doesNotMatch(numericIndicator,/stringWithUTF8String|isEqualToString|intValue/);
  assert.match(numericIndicator,/action == 0[\s\S]*stopTouchIndicator\(error\)[\s\S]*action == 1[\s\S]*startTouchIndicator\(error\)[\s\S]*action == 2[\s\S]*zx_indicatorPerformOnMain/);
  const indicatorLegacy=await read("test/fixtures/indicator-handler-legacy-v1.inc");
  assert.equal(between(task,"    else if (taskType == TASK_TOUCH_INDICATOR)","    else if (taskType == TASK_TEXT_RECOGNIZER)").trim(),indicatorLegacy.slice(indicatorLegacy.indexOf('\n')+1).trim());
  await writeFile(join(temp,"NativeIndicatorBridge.inc"),indicatorBridge);
  await writeFile(join(temp,"NativeIndicatorEntry.inc"),indicatorEntry);
  await writeFile(join(temp,"IndicatorNativeCoreUnderTest.inc"),indicatorCore);
  await writeFile(join(temp,"IndicatorNativeStateUnderTest.inc"),between(indicator,"enum TLinkIndicatorState {","static uintptr_t indicatorGeneration"));
  await writeFile(join(temp,"IndicatorNativeColorUnderTest.inc"),between(indicator,"static NSError *zx_indicatorError(","static NSError *zx_indicatorLoadColor("));
  const helpers = between(bridge,"static NSString *TLinkautoJSSafeStringPart","static NSString *TLinkautoJSBase64Encode") +
    between(bridge,"static NSString *TLinkautoJSBase64Encode","static NSDictionary *TLinkautoJSResultByAdding") +
    between(bridge,"static BOOL TLinkautoJSIsFiniteNumber","static const unsigned long long") +
    await read("test/fixtures/native-point-colors-encoder-legacy-v1.inc") +
    between(bridge,"static bool TLinkautoJSDecodePointColors","static NSDictionary *TLinkautoJSOCRResultByAddingDecodedError") +
    between(bridge,"static double TLinkautoJSDoubleOption","static NSString *TLinkautoJSStringOption") +
    between(bridge,"static NSString *TLinkautoJSStringOption","static NSString *TLinkautoJSOwnerField") +
    between(bridge,"static NSString *TLinkautoJSEncodeGesturePoints","static bool TLinkautoJSDecodePointColors") +
    between(bridge, "static NSString *TLinkNativeStopCode", "@protocol TLinkInProcessFacadeInterface") +
    between(bridge, "static NSString *TLinkautoJSOwnerField", "static BOOL TLinkautoJSValidToken") +
    between(bridge,"static BOOL TLinkautoJSValidToken","static BOOL TLinkautoJSValidProtocolString") +
    between(bridge, "static NSDictionary *TLinkautoJSResultByAdding", "static double TLinkautoJSDoubleOption") +
    between(bridge,"static NSDictionary *TLinkautoJSOCRResultByAddingDecodedError","static NSDictionary *TLinkautoJSStateResult");
  for (const name of new Set([...`${rawBridge}\n${press}\n${typedTouch}\n${batchBridge}\n${colorBridge}\n${framePickBridge}\n${frameManyBridge}\n${frameSearchBridge}\n${frameColorsBridge}\n${frameMultiBridge}\n${colorRangeBridge}\n${colorPointsBridge}\n${colorMultiBridge}\n${frameImageBridge}\n${frameOCRBridge}\n${frameReleaseBridge}\n${imageReleaseBridge}\n${imageCaptureBridge}\n${imageOpenBridge}\n${frameCaptureBridge}`.matchAll(/\b(TLinkautoJS\w+)\s*\(/g)].map(match => match[1]))) {
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
  assert.match(runtimeFixture,/#include "native-frontmost-runtime-fixture.inc"\n#include "native-path-runtime-fixture.inc"/,'path fixture requires the shared scalar formatter first');
  assert.match(runtimeFixture,/#undef YES\n#undef NO\n#include "NativeTouchEntryUnderTest.inc"\n#include "NativeColorEntryUnderTest.inc"\n#include "NativeColorRangeEntry.inc"\n#include "NativeColorPointsEntry.inc"\n#include "NativeColorMultiEntry.inc"\n#include "NativeFrameImageEntry.inc"\n#include "NativeFrameOCREntry.inc"\n#include "NativeFramePickEntry.inc"/);
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
