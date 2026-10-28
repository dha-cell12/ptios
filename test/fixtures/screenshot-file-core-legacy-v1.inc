// Frozen from e782771; compatibility oracle.
+ (NSString*)screenShotToPath:(NSString*)filePath region:(CGRect)region error:(NSError**)error
{
    // Fast path: if keeping and asking for full screenshot, reuse cached PNG.
    NSString *targetPath = filePath;
    if (!targetPath || [targetPath length] == 0)
    {
        targetPath = [getDocumentRoot() stringByAppendingPathComponent:@"screenshot.png"];
    }

    auto owned=TLinkCaptureReceiverSlot();
    if(owned&&(!owned->matches(targetPath.UTF8String)||!owned->valid())){
        if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_lease_missing_or_expired\r\n"}];return nil;
    }
    BOOL shouldReuseKeep = NO;
    @synchronized([Screen class]) {
        shouldReuseKeep = gKeepEnabled;
    }
    if (!owned && shouldReuseKeep && CGRectIsEmpty(region) && [[NSFileManager defaultManager] fileExistsAtPath:kTLinkautoKeepPngPath])
    {
        [[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
        NSError *copyErr = nil;
        if ([[NSFileManager defaultManager] copyItemAtPath:kTLinkautoKeepPngPath toPath:targetPath error:&copyErr])
        {
            return targetPath;
        }
        // Fall back to normal screenshot if copy fails.
        (void)copyErr;
    }

    CGImageRef screenshotRef = [Screen createScreenShotCGImageRef];
    if (!screenshotRef)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
        }
        return nil;
    }

    if(owned&&!zx_ownedCaptureContinue(error)){CGImageRelease(screenshotRef);return nil;}
    size_t ownedPixels=0;
    if(owned&&!TLinkImagePixels(CGImageGetWidth(screenshotRef),CGImageGetHeight(screenshotRef),8388608,&ownedPixels)){
        CGImageRelease(screenshotRef);
        if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_pixel_limit\r\n"}];return nil;
    }
    CGSize imageSize = CGSizeMake(CGImageGetWidth(screenshotRef), CGImageGetHeight(screenshotRef));
    CGRect bounds = CGRectMake(0, 0, imageSize.width, imageSize.height);
    CGRect targetRegion = CGRectIsEmpty(region) ? bounds : CGRectIntersection(bounds, region);

    if (CGRectIsEmpty(targetRegion))
    {
        CGImageRelease(screenshotRef);
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid screenshot region.\r\n"}];
        }
        return nil;
    }

    BOOL isFullFrame = CGRectEqualToRect(targetRegion, bounds);
    CGImageRef outputRef = isFullFrame ? screenshotRef : CGImageCreateWithImageInRect(screenshotRef, targetRegion);
    if (!isFullFrame) {
        CGImageRelease(screenshotRef);
    }
    if (!outputRef)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
        }
        return nil;
    }

    UIImage *image=nil;
    @try {image=[UIImage imageWithCGImage:outputRef];}
    @finally {CGImageRelease(outputRef);}

    if(owned&&!zx_ownedCaptureContinue(error))return nil;
    NSString *ext = [[targetPath pathExtension] lowercaseString];
    NSData *encoded = ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
        ? UIImageJPEGRepresentation(image, 0.75)
        : UIImagePNGRepresentation(image);

    if(owned)return zx_writeOwnedCapture(targetPath,encoded,error)?targetPath:nil;

    NSString *parentDir = [targetPath stringByDeletingLastPathComponent];
    if ([parentDir length] > 0 && ![[NSFileManager defaultManager] fileExistsAtPath:parentDir])
    {
        NSError *mkdirErr = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:parentDir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&mkdirErr])
        {
            if (error)
            {
                NSString *message = [NSString stringWithFormat:@"-1;;Failed to create screenshot directory: %@ (%@)\r\n",
                                     parentDir,
                                     [mkdirErr localizedDescription] ?: @"unknown error"];
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:message}];
            }
            return nil;
        }
    }

    if (!encoded || ![encoded writeToFile:targetPath atomically:NO])
    {
        if (error)
        {
            NSString *message = [NSString stringWithFormat:@"-1;;Failed to save screenshot: %@\r\n", targetPath];
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:message}];
        }
        return nil;
    }

    return targetPath;
}

