import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/ocr-p1-cpu-only.json"));

assert.equal(fixture.phase, "P1");
assert.equal(fixture.task, 27);
assert.equal(fixture.profileFieldIndex, 8);
assert.equal(fixture.defaultProfile, "app_cpu");
assert.deepEqual(fixture.allowedProfiles, ["app_cpu", "worker_cpu", "xxt_compat"]);

function task27Parts(request) {
  const line = request.replace(/\r?\n$/, "");
  assert.ok(line.startsWith("27"), "fixture must use task 27");
  return line.slice(2).split(";;");
}

const legacyParts = task27Parts(fixture.legacyRequest);
assert.equal(legacyParts.length, 8);
assert.equal(legacyParts[fixture.profileFieldIndex], undefined);
for (const request of [fixture.appCPURequest, fixture.workerCPURequest, fixture.xxtCompatRequest]) {
  const parts = task27Parts(request);
  assert.equal(parts.length, 9);
  assert.ok(fixture.allowedProfiles.includes(parts[fixture.profileFieldIndex]));
}

const [
  server,
  app,
  uiService,
  serverMakefile,
  appMakefile,
  uiServiceMakefile,
  appEntitlements,
  uiServiceEntitlements,
  collector,
  qualification,
  p1Doc,
  p2Doc,
  findingsDoc,
  buildWorkflow,
  trollstoreWorkflow,
] = await Promise.all([
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/app/AppDelegate.mm"),
  read("stream-app/uiservice/VisionOCRService.mm"),
  read("stream-app/streamd/Makefile"),
  read("stream-app/app/Makefile"),
  read("stream-app/uiservice/Makefile"),
  read("stream-app/app/entitlements.plist"),
  read("stream-app/uiservice/entitlements.plist"),
  read("scripts/Collect-TLinkOCRBaseline.ps1"),
  read("scripts/Collect-TLinkVisionOCRQualification.ps1"),
  read("docs/ocr-p1-cpu-only.md"),
  read("docs/ocr-p2-xxt-compat.md"),
  read("docs/ocr-p1-device-findings.md"),
  read(".github/workflows/build.yml"),
  read(".github/workflows/stream-app.yml"),
]);

assert.match(server, /parts\.count >= 9[\s\S]*?parts\[8\][\s\S]*?: @"app_cpu"/);
assert.match(server, /isEqualToString:@"app_cpu"[\s\S]*?isEqualToString:@"worker_cpu"/);
assert.match(server, /isEqualToString:@"worker_cpu"[\s\S]*?isEqualToString:@"xxt_compat"/);
assert.match(server, /vision_profile_app_cpu_uiservice[\s\S]*?TLinkRunUIServiceVisionOCRRawRGBA/);
assert.match(server, /vision_profile_worker_cpu[\s\S]*?VNRecognizeTextRequest/);
assert.match(server, /isEqualToString:@"app_cpu"\] \|\| \[profile isEqualToString:@"xxt_compat"\][\s\S]*?vision_profile_xxt_compat_uiservice[\s\S]*?TLinkRunUIServiceVisionOCRRawRGBA/);
assert.match(server, /@"4;;%lu;;%d;;%d;;%d;;[\s\S]*?TLinkBase64UTF8String\(customWords\)[\s\S]*?TLinkBase64UTF8String\(languages\)/);
assert.doesNotMatch(server, /vision_xxt_compat_perform_requests/);
assert.match(server, /vision-ocr-debug\.log/);
assert.match(server, /subtask == 3[\s\S]*?vision_debug_base64/);
assert.match(server, /subtask == 4[\s\S]*?vision_debug_cleared/);
assert.match(server, /vision_cpu_configure[\s\S]*?TLinkConfigureVisionRequestCPUOnly/);
assert.match(server, /supportedComputeStageDevicesAndReturnError/);
assert.match(server, /setComputeDevice:cpuDevice forComputeStage:stage/);
assert.match(server, /request\.usesCPUOnly = YES/);
assert.match(server, /@"ocrVisionState": @"experimental"/);
assert.match(server, /@"ocrVisionProfile": @"app_cpu_default_worker_cpu_opt_in_xxt_compat_background_uiservice"/);
assert.match(server, /@"ocrVisionCPUOnly": @\(YES\)/);
assert.match(server, /@"ocrVisionXXTCompat": @\(YES\)/);
assert.match(server, /@"ocrVisionXXTCompatPixelLayout": @"rgba8888_premultiplied_last_stride_width_x4"/);
assert.match(server, /@"ocrVisionXXTCompatHost": @"background_uiservice_6018"/);
assert.match(server, /@"ocrVisionXXTCompatForegroundRequired": @\(NO\)/);
assert.match(server, /@"ocrVisionAppWatchdogMs": @15000/);
assert.match(server, /@"ocrVisionAppBridgeProtocol": @4/);
assert.match(server, /@"ocrVisionTransport": @"inline_rgba8888_bounded_32mib_v2"/);
assert.match(server, /@"ocrVisionFallbackProtocol": @3/);
assert.match(server, /@"ocrVisionDispatch": @"direct_streamd_to_uiservice_no_worker_v1"/);
assert.match(server, /@"ocrVisionInlineMaxBytes": @33554432/);
assert.match(server, /@"ocrVisionPixelBufferProbe": @"startup_once_bgra_420f_memory_iosurface_opengles_metal_v2"/);
assert.match(server, /@"ocrVisionGraphicsEntitlements": @"iosurface_ioaccel_agx_v1"/);
assert.match(server, /@"ocrVisionAppBridgeProbe": @"task275_uiservice_v1"/);
assert.match(server, /@"ocrVisionQualification": @"background_direct_raw_fast20_accurate1_largefast1_v5"/);
assert.match(server, /htons\(6018\)/);
assert.match(server, /uiservice_ocr_bridge_probe_empty_response/);
assert.match(server, /@"4;;%lu;;%d;;%d;;%d;;/);
assert.match(server, /inline_bytes/);
assert.match(server, /vision_png_v3_fallback/);
assert.match(server, /dispatch=direct_streamd_to_uiservice_no_worker_v1/);
assert.match(server, /directUIServiceRoute[\s\S]*?TLinkHandleVisionOCRInProcess/);
assert.doesNotMatch(server, /appocr-XXXXXX|uiservice_ocr_bridge_tmpdir_failed|fchmod\(imageFd/);
assert.match(app, /TLinkConfigureVisionRequestCPUOnly/);
assert.match(app, /supportedComputeStageDevicesAndReturnError/);
assert.match(app, /setComputeDevice:cpuDevice forComputeStage:stage/);
assert.match(app, /request\.usesCPUOnly = YES/);
assert.match(app, /newRGBImageFromImageData[\s\S]*?width \* 4[\s\S]*?kCGBitmapByteOrder32Little \| kCGImageAlphaPremultipliedFirst/);
assert.match(app, /xxtCompat[\s\S]*?VNRecognizeTextRequest alloc\] init\]/);
assert.match(app, /if \(!xxtCompat\)[\s\S]*?TLinkConfigureVisionRequestCPUOnly/);
assert.match(app, /app_ocr_requires_foreground/);
assert.match(app, /app_ocr_busy previous_request_in_flight/);
assert.match(app, /app_ocr_timeout timeout_ms=15000/);
assert.match(app, /com\.tlinkauto\.streamcontrol\.vision-ocr/);
assert.match(app, /host=foreground_app_6011/);
assert.match(app, /TLinkProbeVisionPixelBuffer/);
assert.match(app, /kCVPixelFormatType_420YpCbCr8BiPlanarFullRange/);
assert.match(app, /phase:@"app_pixelbuffer_probe"/);
assert.match(app, /std::atomic<NSInteger> sTLinkOCRApplicationState/);
assert.match(app, /phase:@"app_bridge_ingress"/);
assert.match(app, /app_ocr_ready/);
assert.doesNotMatch(app, /currentApplicationStateForOCR[\s\S]{0,500}dispatch_sync\(dispatch_get_main_queue/);

assert.match(uiService, /uiservice_ocr_ready/);
assert.match(uiService, /kTLinkVisionOCRPort = 6018/);
assert.match(uiService, /background_uiservice_6018/);
assert.match(uiService, /TLinkVisionCreateRGBImage[\s\S]*?width \* 4[\s\S]*?kCGBitmapByteOrder32Little \| kCGImageAlphaPremultipliedFirst/);
assert.match(uiService, /TLinkVisionCreateRGBAImage[\s\S]*?kCGImageAlphaPremultipliedLast \| kCGBitmapByteOrder32Big/);
assert.match(uiService, /TLinkVisionConfigureCPUOnly/);
assert.match(uiService, /supportedComputeStageDevicesAndReturnError/);
assert.match(uiService, /setComputeDevice:cpuDevice forComputeStage:stage/);
assert.match(uiService, /request\.usesCPUOnly = YES/);
assert.match(uiService, /uiservice_pixelbuffer_probe/);
assert.match(uiService, /uiservice_perform_end/);
assert.match(uiService, /uiservice_response_ready/);
assert.match(uiService, /scene_required=0/);
assert.match(uiService, /protocol=4/);
assert.match(uiService, /transport=inline_rgba8888/);
assert.match(uiService, /fallback_protocol=3/);
assert.match(uiService, /TLinkVisionReadExact/);
assert.doesNotMatch(uiService, /makeKeyAndVisible|UIWindowScene|FBScene/);

assert.match(serverMakefile, /streamd_FRAMEWORKS = .* Vision CoreML /);
assert.match(appMakefile, /StreamControl_FRAMEWORKS = .* Vision CoreML /);
assert.match(appMakefile, /StreamControl_FRAMEWORKS = .* CoreVideo /);
assert.match(uiServiceMakefile, /TLinkUIService_FRAMEWORKS = .* CoreVideo .* Vision CoreML ImageIO/);
assert.match(server, /#import <CoreML\/CoreML\.h>/);
assert.match(app, /#import <CoreML\/CoreML\.h>/);
assert.match(app, /#import <CoreVideo\/CoreVideo\.h>/);

for (const entitlement of [
  "com.apple.QuartzCore.displayable-context",
  "com.apple.private.IOSurface.protected-access",
  "com.apple.security.exception.iokit-user-client-class",
  "com.apple.security.iokit-user-client-class",
  "IOSurfaceRootUserClient",
  "IOSurfaceAcceleratorClient",
  "IOAccelContext2",
  "AGXCommandQueue",
  "AGXDeviceUserClient",
  "AGXGLContext",
]) {
  assert.ok(appEntitlements.includes(entitlement), `StreamControl OCR graphics entitlement missing ${entitlement}`);
  assert.ok(uiServiceEntitlements.includes(entitlement), `TLinkUIService OCR graphics entitlement missing ${entitlement}`);
}

for (const [key, value] of Object.entries(fixture.requiredCapabilityFields)) {
  assert.ok(server.includes(`${key}=${value}`), `task 97 is missing ${key}=${value}`);
}

assert.match(collector, /\[ValidateSet\("app_cpu", "worker_cpu", "xxt_compat"\)\]/);
assert.match(collector, /\[string\]\$VisionProfile = "app_cpu"/);
assert.match(collector, /\$visionTask = "271;;\$rect[\s\S]*;;;;\$VisionProfile"/);
assert.match(collector, /vision_profile = \$VisionProfile/);
assert.match(collector, /Invoke-TLinkTask -Task "273"/);
assert.match(collector, /Invoke-TLinkTask -Task "274"/);
assert.match(collector, /Add-TLinkVisionDebugText/);
assert.match(qualification, /\[int\]\$FastRepeatCount = 20/);
assert.match(qualification, /\[ValidateRange\(20, 100\)\]/);
assert.match(qualification, /background_direct_raw_fast20_accurate1_largefast1_v5/);
assert.match(qualification, /Invoke-TLinkVisionCase -Name "fast_repeat" -RecognitionLevel 1/);
assert.match(qualification, /Invoke-TLinkVisionCase -Name "accurate_small" -RecognitionLevel 0/);
assert.match(qualification, /Invoke-TLinkVisionCase -Name "fast_large" -RecognitionLevel 1/);
assert.match(qualification, /Invoke-TLinkTask -Task "97"/);
assert.match(qualification, /Invoke-TLinkTask -Task "275"/);
assert.match(qualification, /uiservice_bridge_preflight_failed/);
assert.match(qualification, /missing_postflight_markers/);
assert.match(qualification, /startup_pixel_probe_ready/);
assert.match(qualification, /Invoke-TLinkTask -Task "274"/);
assert.match(qualification, /Invoke-TLinkTask -Task "273"/);
assert.match(qualification, /\$debugClear = Invoke-TLinkTask -Task "274"[\s\S]*?\$serviceBridgePreflight = Invoke-TLinkTask -Task "275"/);
assert.match(qualification, /ocr-qualification\.json/);
assert.match(qualification, /promotion_ready = \$false/);
assert.match(p1Doc, /app_cpu/);
assert.match(p1Doc, /worker_cpu/);
assert.match(p2Doc, /xxt_compat/);
assert.match(p2Doc, /vision-ocr-debug\.log/);
assert.match(p2Doc, /VisionLanguages en-US/);
assert.match(p2Doc, /Collect-TLinkVisionOCRQualification\.ps1/);
assert.match(p2Doc, /20 Fast requests/);
assert.match(findingsDoc, /\*\*Deferred on 2026-07-31\.\*\*/);
assert.match(findingsDoc, /signal=11 phase=vision_perform_requests/);
assert.match(findingsDoc, /Fast pipeline remained blocked for at least twenty seconds/i);
assert.match(findingsDoc, /all production automation should use task `91`/i);
assert.match(buildWorkflow, /node scripts\/check-ocr-p1-cpu-only\.mjs/);
assert.match(trollstoreWorkflow, /node scripts\/check-ocr-p1-cpu-only\.mjs/);

console.log("OCR P1/P4 Vision OK: background direct inline UI-service route wired, worker_cpu isolation and legacy task 27 response preserved");
