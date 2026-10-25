// Frozen adf0a93 action-2 handler before C02b20.
static NSString *legacyImageOpenTask(UInt8 *eventData,NSError **error){
    NSArray *data=[[NSString stringWithFormat:@"%s",(const char *)eventData] componentsSeparatedByString:@";;"];
    int action=[data[0] intValue];
    if(false){}
    else if (action == 2) {
        TLinkImageWork work(gImageCompute);
        if (!work) { if (error) *error = zx_frameError(@"-1;;image_compute_busy\r\n"); return nil; }
        if ([data count] < 2) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image open format should be action;;path\r\n"}];
            }
            return nil;
        }
        NSString *path = zx_resolveImagePath(data[1]);
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Image not found. Path: %@\r\n", path ?: data[1]]}];
            }
            return nil;
        }
        std::shared_ptr<TLinkImageCharge> charge;
        NSError *decodeError = nil;
        Mat gray = zx_decodeBoundedImage(path, charge, &decodeError);
        if (gray.empty()) {
            if (error) {
                *error = decodeError ?: [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to read image. Path: %@\r\n", path]}];
            }
            return nil;
        }
        auto pendingImage = std::make_shared<ZXImageObject>();
        ZXImageObject &image = *pendingImage;
        image.charge = std::move(charge);
        image.gray = std::move(gray);
        image.w = image.gray.cols;
        image.h = image.gray.rows;
        image.createdAtMs = zx_nowMs();
        image.ttlMs = 0;
        zx_applyImageOwner(image, data, 2);
        __block uint32_t imageId = 0;
        TLinkNativeDispatchSync(zx_imageQueue(), ^{
            imageId = zx_storeImageLocked(pendingImage);
        });
        if (imageId == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
            }
            return nil;
        }
        return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, image.w, image.h];
    }
    return nil;
}
