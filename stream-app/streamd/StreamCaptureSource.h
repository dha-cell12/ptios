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
// IOSurfaceAccelerator scales into an explicitly allocated BGRA staging
// IOSurface. The accelerator never writes directly into VideoToolbox pool
// memory; a read-coherent, bytes-per-row-aware CPU copy populates `buffer`
// only after the source seed remains stable. A CoreGraphics copy is retained
// as a per-frame fail-safe for unavailable or integrity-unsafe transfers.
BOOL SCCaptureScreenIntoPixelBuffer(CVPixelBufferRef buffer);

// Runtime diagnostics are included in task 60 under
// adaptive_streaming.capture_pipeline.
NSDictionary *SCCapturePipelineStatus(void);

// Runtime A/B control used by licensed task 93. Supported values are
// `auto`, `accelerated`, and `legacy`. Auto and accelerated both prefer the
// IOSurface accelerator and retain the compatibility fallback; legacy forces
// the historical CoreGraphics copy path for an apples-to-apples benchmark.
BOOL SCSetCapturePipelineMode(NSString *mode, BOOL resetMetrics);

// Release cached IOSurfaces/accelerator after a persistent capture failure.
// The next capture lazily rebuilds the pipeline.
void SCResetCapturePipeline(void);

#ifdef __cplusplus
}
#endif

#endif
