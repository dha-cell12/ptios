import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const [header, capture, h264, server, makefile, doc, deviceTest, buildWorkflow, trollWorkflow] =
  await Promise.all([
    read("stream-app/streamd/StreamCaptureSource.h"),
    read("stream-app/streamd/StreamCaptureSource.mm"),
    read("stream-app/streamd/H264Stream.mm"),
    read("stream-app/streamd/POCSocketServer.mm"),
    read("stream-app/streamd/Makefile"),
    read("docs/stream-capture-pipeline-v2.md"),
    read("scripts/Test-TLinkStreamCapturePipelineV2.ps1"),
    read(".github/workflows/build.yml"),
    read(".github/workflows/stream-app.yml"),
  ]);

assert.match(header, /SCCaptureScreenIntoPixelBuffer/);
assert.match(header, /SCCapturePipelineStatus/);
assert.match(header, /SCResetCapturePipeline/);
assert.match(header, /SCSetCapturePipelineMode/);

assert.match(capture, /kSCCaptureSurfacePoolSize = 2/);
assert.match(capture, /IOSurfaceAcceleratorCreate/);
assert.match(capture, /IOSurfaceAcceleratorTransferSurface/);
assert.match(capture, /IOSurfaceAcceleratorGetRunLoopSource/);
assert.match(capture, /CFRunLoopAddSource/);
assert.match(capture, /kSCStagingSurfaceCacheSize = 4/);
assert.match(capture, /SCStagingSurfaceLocked/);
assert.match(capture, /SCCopyStagingSurfaceToPixelBuffer/);
assert.match(capture, /kSCIOSurfaceLockReadOnly/);
assert.match(capture, /IOSurfaceGetSeed/);
assert.match(capture, /IOSurfaceGetBytesPerRow/);
assert.match(capture, /memcpy\(targetBase \+ row \* targetBytesPerRow/);
assert.match(capture, /SCCopySurfaceWithCoreGraphics/);
assert.match(capture, /@"capture_pipeline_v2"/);
assert.match(capture, /@"accelerated_count"/);
assert.match(capture, /@"fallback_count"/);
assert.match(capture, /@"coherence_barrier_count"/);
assert.match(capture, /@"coherence_barrier_failure_count"/);
assert.match(capture, /@"source_seed_mismatch_count"/);
assert.match(capture, /@"integrity_fallback_count"/);
assert.match(capture, /@"staged_copy_count"/);
assert.match(capture, /@"staging_copy_failure_count"/);
assert.match(capture, /@"direct_encoder_surface_transfer"/);
assert.match(capture, /@"accelerator_run_loop_attached"/);
assert.match(capture, /@"last_total_us"/);
assert.match(capture, /coregraphics_legacy_per_frame_surface/);
assert.match(capture, /@"total_metrics"/);

assert.match(h264, /kCVPixelBufferIOSurfacePropertiesKey/);
assert.match(h264, /VTCompressionSessionGetPixelBufferPool/);
assert.match(h264, /CVPixelBufferPoolCreatePixelBuffer/);
assert.match(h264, /SCCaptureScreenIntoPixelBuffer\(pb\)/);
assert.match(h264, /SCResetCapturePipeline\(\)/);
assert.match(h264, /consecutiveSuccessfulFrames >= 300/);
assert.doesNotMatch(h264, /CGContextDrawImage/);
assert.doesNotMatch(h264, /SCCreateScreenShotCGImage\(\)/);

assert.match(makefile, /IOSurface/);
for (const marker of [
  "streamCapturePipeline=iosurface_pool_gpu_scale_v2",
  "streamCapturePreferredBackend=iosurface_accelerator",
  "streamCaptureFallback=coregraphics_v1",
  "streamCaptureSourcePool=2",
  "streamCaptureStagingCache=4",
  "streamCaptureTarget=encoder_iosurface_pixel_buffer",
  "streamCaptureAcceleratorTarget=explicit_bgra_staging_surface",
  "streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline",
  "streamCaptureBenchmark=task93_legacy_vs_accelerated_v2",
  "streamCaptureSynchronization=accelerator_runloop_staged_stride_copy_seed_v2",
  "streamCaptureRecovery=capture_reset_once_encoder_budget_reset_300_frames",
  "streamCaptureIntegrityDeviceValidated=0",
  "streamCaptureDeviceValidated=1",
]) {
  assert.ok(server.includes(marker), `task 97 missing ${marker}`);
  assert.ok(doc.includes(marker), `documentation missing ${marker}`);
}

assert.match(deviceTest, /capture_pipeline/);
assert.match(deviceTest, /accelerated_count/);
assert.match(deviceTest, /fallback_count/);
assert.match(deviceTest, /coherence_barrier_count/);
assert.match(deviceTest, /coherence_barrier_failure_count/);
assert.match(deviceTest, /source_seed_mismatch_count/);
assert.match(deviceTest, /integrity_fallback_count/);
assert.match(deviceTest, /staged_copy_count/);
assert.match(deviceTest, /staging_copy_failure_count/);
assert.match(deviceTest, /pass_accelerated_staged/);
assert.match(deviceTest, /direct_encoder_surface_transfer/);
assert.match(buildWorkflow, /check-stream-capture-pipeline-v2\.mjs/);
assert.match(trollWorkflow, /check-stream-capture-pipeline-v2\.mjs/);

console.log("Stream Capture Pipeline v2 OK: staged IOSurface accelerator, stride-safe encoder copy and integrity fallback wired");
