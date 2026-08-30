#ifndef STREAM_CAPTURE_SOURCE_H
#define STREAM_CAPTURE_SOURCE_H

#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Create a retained CGImage of the current display using the same
// CARenderServerRenderDisplay + IOSurface path proven by CaptureCore.
// Caller owns the returned image and must CGImageRelease().
CGImageRef SCCreateScreenShotCGImage(void);

// Capture the current display into an encoder-sized BGRA pixel buffer.
// The preferred path reuses a small full-resolution IOSurface pool and asks
// Auto mode uses pooled IOSurface capture plus public Accelerate/vImage scaling
// directly into `buffer`; this is the production-safe path. The private
// IOSurfaceAccelerator staging path remains available only through explicit
// `accelerated` diagnostic mode because device validation found visual tearing
// despite successful transfer/synchronization counters. CoreGraphics remains
// the per-frame fail-safe.
BOOL SCCaptureScreenIntoPixelBuffer(CVPixelBufferRef buffer);

// Runtime diagnostics are included in task 60 under
// adaptive_streaming.capture_pipeline.
NSDictionary *SCCapturePipelineStatus(void);

// Runtime A/B control used by licensed task 93. Supported values are
// `auto`, `accelerated`, and `legacy`. Auto selects pooled vImage scaling;
// accelerated explicitly opts into the visually unsafe private accelerator for
// diagnosis; legacy forces the historical CoreGraphics path for comparison.
BOOL SCSetCapturePipelineMode(NSString *mode, BOOL resetMetrics);

// Release cached IOSurfaces/accelerator after a persistent capture failure.
// The next capture lazily rebuilds the pipeline.
void SCResetCapturePipeline(void);

#ifdef __cplusplus
}
#endif

#endif
