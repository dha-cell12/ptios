BOOL SCCaptureScreenIntoPixelBuffer(CVPixelBufferRef target)
{
    if (!target || CVPixelBufferGetPixelFormatType(target) != kCVPixelFormatType_32BGRA) return NO;

    uint64_t totalStartedUs = SCMonotonicMicroseconds();
    os_unfair_lock_lock(&sSCCaptureLock);

    BOOL forceLegacy = [sSCRequestedMode isEqualToString:@"legacy"];
    if (forceLegacy) {
        uint64_t captureStartedUs = SCMonotonicMicroseconds();
        CGImageRef image = SCCreateScreenShotCGImage();
        sSCLastCaptureUs = SCMonotonicMicroseconds() - captureStartedUs;
        if (image) {
            sSCCaptureWidth = (int)CGImageGetWidth(image);
            sSCCaptureHeight = (int)CGImageGetHeight(image);
        }
        uint64_t scaleStartedUs = SCMonotonicMicroseconds();
        BOOL succeeded = image && SCCopyCGImageWithCoreGraphics(image, target);
        sSCLastScaleUs = SCMonotonicMicroseconds() - scaleStartedUs;
        if (image) CGImageRelease(image);
        sSCCaptureCount++;
        if (succeeded) {
            sSCLegacyCount++;
            sSCActiveBackend = @"coregraphics_legacy_per_frame_surface";
            sSCLastResult = @"legacy";
        } else {
            sSCFailureCount++;
            sSCActiveBackend = @"failed";
            sSCLastResult = @"legacy_capture_copy_failed";
        }
        sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
        SCRecordMetricsLocked(sSCLastCaptureUs, sSCLastScaleUs, sSCLastTotalUs);
        os_unfair_lock_unlock(&sSCCaptureLock);
        return succeeded;
    }

    BOOL forcePrivateAccelerator = [sSCRequestedMode isEqualToString:@"accelerated"];
    if (!forcePrivateAccelerator) {
        // Device qualification proved that a freshly allocated render surface,
        // followed by UICreateCGImageFromIOSurface + CGContextDrawImage, is the
        // only path that consistently materializes every compositor layer.
        // Do not reuse a source IOSurface here: CARenderServerRenderDisplay may
        // return while layer tiles still reference the previous surface epoch.
        uint64_t captureStartedUs = SCMonotonicMicroseconds();
        CGImageRef image = SCCreateScreenShotCGImage();
        sSCLastCaptureUs = SCMonotonicMicroseconds() - captureStartedUs;
        if (image) {
            sSCCaptureWidth = (int)CGImageGetWidth(image);
            sSCCaptureHeight = (int)CGImageGetHeight(image);
        }
        uint64_t scaleStartedUs = SCMonotonicMicroseconds();
        BOOL succeeded = image && SCCopyCGImageWithCoreGraphics(image, target);
        sSCLastScaleUs = SCMonotonicMicroseconds() - scaleStartedUs;
        if (image) CGImageRelease(image);
        sSCCaptureCount++;
        if (succeeded) {
            sSCSafeCopyCount++;
            sSCActiveBackend = @"coregraphics_fresh_surface_safe";
            sSCLastResult = @"fresh_surface_snapshot_safe";
        } else {
            sSCSafeCopyFailureCount++;
            sSCFailureCount++;
            sSCActiveBackend = @"failed";
            sSCLastResult = @"fresh_surface_snapshot_failed";
        }
        sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
        SCRecordMetricsLocked(sSCLastCaptureUs, sSCLastScaleUs, sSCLastTotalUs);
        os_unfair_lock_unlock(&sSCCaptureLock);
        return succeeded;
    }

    int sourceWidth = 0;
    int sourceHeight = 0;
    if (!SCDisplayPixelSize(&sourceWidth, &sourceHeight) ||
        !SCEnsureCaptureSurfacesLocked(sourceWidth, sourceHeight)) {
        sSCFailureCount++;
        sSCLastResult = @"source_surface_unavailable";
        sSCActiveBackend = @"failed";
        sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
        os_unfair_lock_unlock(&sSCCaptureLock);
        return NO;
    }

    IOSurfaceRef source = sSCCaptureSurfaces[sSCCaptureSurfaceIndex];
    sSCCaptureSurfaceIndex = (sSCCaptureSurfaceIndex + 1) % kSCCaptureSurfacePoolSize;

    uint64_t captureStartedUs = SCMonotonicMicroseconds();
    IOSurfaceLock(source, 0, NULL);
    CARenderServerRenderDisplay(0, CFSTR("LCD"), source, 0, 0);
    sSCLastCaptureUs = SCMonotonicMicroseconds() - captureStartedUs;
    sSCLastSourceSeedBefore = IOSurfaceGetSeed(source);

    BOOL succeeded = NO;
    NSString *fallbackReason = @"accelerator_unavailable";
    int targetWidth = (int)CVPixelBufferGetWidth(target);
    int targetHeight = (int)CVPixelBufferGetHeight(target);
    IOSurfaceRef staging = SCStagingSurfaceLocked(targetWidth, targetHeight);
    if (staging && SCEnsureSurfaceAcceleratorLocked()) {
            uint64_t scaleStartedUs = SCMonotonicMicroseconds();
            sSCLastDestinationSeedBefore = IOSurfaceGetSeed(staging);
            kern_return_t transfer = KERN_FAILURE;
            kern_return_t stagingLockResult = IOSurfaceLock(staging, 0, NULL);
            if (stagingLockResult == KERN_SUCCESS) {
                transfer = sSCAcceleratorTransfer(
                    sSCSurfaceAccelerator, source, staging, NULL, NULL);
                kern_return_t stagingUnlockResult = IOSurfaceUnlock(staging, 0, NULL);
                if (transfer == KERN_SUCCESS && stagingUnlockResult != KERN_SUCCESS) {
                    transfer = stagingUnlockResult;
                }
            } else {
                transfer = stagingLockResult;
            }
            BOOL coherent = NO;
            if (transfer == KERN_SUCCESS) {
                coherent = SCCopyStagingSurfaceToPixelBuffer(staging, target);
            }
            sSCLastSourceSeedAfter = IOSurfaceGetSeed(source);
            sSCLastDestinationSeedAfter = IOSurfaceGetSeed(staging);
            sSCLastScaleUs = SCMonotonicMicroseconds() - scaleStartedUs;
            sSCLastTransferResult = transfer;

            BOOL sourceStable = sSCLastSourceSeedBefore == sSCLastSourceSeedAfter;
            if (!sourceStable) {
                sSCSourceSeedMismatchCount++;
            }
            if (sSCLastDestinationSeedBefore == sSCLastDestinationSeedAfter) {
                sSCDestinationSeedUnchangedCount++;
            }

            if (transfer == KERN_SUCCESS && coherent && sourceStable) {
                succeeded = YES;
                sSCAcceleratedCount++;
                sSCActiveBackend = @"iosurface_accelerator_staged_copy_unsafe_opt_in";
                sSCLastResult = @"accelerated_staged_copy_unsafe_opt_in";
            } else if (transfer == KERN_SUCCESS) {
                sSCIntegrityFallbackCount++;
                fallbackReason = coherent ? @"source_seed_changed" : @"coherence_barrier_failed";
            } else {
                fallbackReason = @"accelerator_transfer_failed";
            }
    } else if (!staging) {
        fallbackReason = @"staging_surface_unavailable";
    }

    if (!succeeded) {
        uint64_t fallbackStartedUs = SCMonotonicMicroseconds();
        CGImageRef retryImage = SCCreateScreenShotCGImage();
        succeeded = retryImage && SCCopyCGImageWithCoreGraphics(retryImage, target);
        if (retryImage) CGImageRelease(retryImage);
        sSCLastScaleUs = SCMonotonicMicroseconds() - fallbackStartedUs;
        if (succeeded) {
            sSCFallbackCount++;
            sSCActiveBackend = @"coregraphics_fallback";
            sSCLastResult = [@"fallback_after_" stringByAppendingString:fallbackReason];
        }
    }

    IOSurfaceUnlock(source, 0, NULL);
    sSCCaptureCount++;
    if (!succeeded) {
        sSCFailureCount++;
        sSCActiveBackend = @"failed";
        sSCLastResult = @"capture_copy_failed";
    }
    sSCLastTotalUs = SCMonotonicMicroseconds() - totalStartedUs;
    SCRecordMetricsLocked(sSCLastCaptureUs, sSCLastScaleUs, sSCLastTotalUs);
    os_unfair_lock_unlock(&sSCCaptureLock);
    return succeeded;
}

