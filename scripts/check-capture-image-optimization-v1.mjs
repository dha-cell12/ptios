import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const [captureHeader, capture, server, visionService, makefile, appEntitlements, streamdEntitlements, settings, photoTest] = await Promise.all([
  read("stream-app/streamd/CaptureCore.h"),
  read("stream-app/streamd/CaptureCore.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/uiservice/VisionOCRService.mm"),
  read("stream-app/streamd/Makefile"),
  read("stream-app/app/entitlements.plist"),
  read("stream-app/streamd/entitlements.plist"),
  read("stream-app/app/SettingsViewController.mm"),
  read("scripts/Test-TLinkPhotoAutomation.ps1"),
]);

assert.match(captureHeader, /runProductionCapture/);
assert.match(captureHeader, /rgbaData[\s\S]*?bytesPerRow/);
const productionCapture = capture.slice(
  capture.indexOf("+ (CaptureOutcome *)runProductionCapture"),
  capture.indexOf("+ (CaptureOutcome *)runCaptureProbe"),
);
assert.match(productionCapture, /SCCreateScreenShotCGImage/);
assert.match(productionCapture, /dataWithBytesNoCopy/);
assert.match(productionCapture, /production_capture_ready/);
assert.doesNotMatch(productionCapture, /appendCaptureEntitlementSnapshot|UIImagePNGRepresentation|writeToFile/);
assert.match(server, /TLinkRunCaptureOnMain[\s\S]{0,1000}runProductionCapture/);
assert.match(server, /TLinkCaptureOutcomeForVision/);
assert.match(server, /TLinkRunUIServiceVisionOCRRawRGBA/);
assert.match(server, /vision_png_v3_fallback/);

const visionHotPath = visionService.slice(
  visionService.indexOf("static NSString *TLinkVisionPerformRequest"),
  visionService.indexOf("static NSString *TLinkVisionHandleLine"),
);
assert.match(visionHotPath, /version4Request/);
assert.match(visionHotPath, /TLinkVisionCreateRGBAImage/);
assert.doesNotMatch(visionHotPath, /TLinkVisionProbePixelBuffer/);
assert.match(visionService, /TLinkVisionRunPixelBufferProbeOnce/);
assert.match(visionService, /pixelbuffer_probe=startup_once/);

assert.match(server, /#import <Accelerate\/Accelerate\.h>/);
assert.match(server, /TLinkScaleRGBAData/);
assert.match(server, /vImageScale_ARGB8888/);
assert.match(server, /scaleMin[\s\S]*?scaleMax[\s\S]*?scaleStep/);
assert.match(server, /scaleCount < 64/);
assert.match(server, /BOOL pruned = NO[\s\S]*?!pruned && sad < bestSad/);
assert.match(server, /TLinkImageObject[\s\S]*?rgbaData[\s\S]*?bytesPerRow/);
assert.match(server, /TLinkFrameObject \*hayFrame[\s\S]*?hayFrame\.rgbaData/);
assert.match(server, /imageMatch=multiscale_vimage_rgba_v2/);
assert.match(makefile, /Accelerate/);

for (const entitlements of [appEntitlements, streamdEntitlements]) {
  assert.match(entitlements, /com\.apple\.private\.tcc\.allow/);
  assert.match(entitlements, /kTCCServicePhotos/);
  assert.match(entitlements, /kTCCServicePhotosAdd/);
}
assert.match(server, /TLinkPrivatePhotoAccessEntitled/);
assert.match(server, /private_tcc_entitlement_missing/);
assert.match(settings, /TLinkAppHasAutomaticPhotoAccess/);
assert.match(settings, /No manual approval is required/);
assert.match(photoTest, /291;;\$deviceImagePath/);
assert.match(photoTest, /292;;\$deviceImagePath/);

console.log("Capture/image optimization v1 OK: RGBA capture, raw OCR v4, vImage matching, and zero-touch Photos TCC wired");
