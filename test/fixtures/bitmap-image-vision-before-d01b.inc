// BEGIN frame Vision provider.
CGImageRef TLinkCreateVisionImageFromFrame(uint32_t frameId,CGRect region,NSString *coord,uint64_t maxAgeMs,
                                          CGRect *pixelRegion,uint64_t *ageMs,NSError **error)
{
    if(TLinkNativeStopped()){if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(!frameId||frameId>INT_MAX||maxAgeMs>5000||(![coord isEqualToString:@"pixel"]&&![coord isEqualToString:@"point"])){
        if(error)*error=zx_frameError(@"-1;;vision_frame_parameters_invalid\r\n");return NULL;
    }
    TLinkImageWork work(gImageCompute);
    if(!work){if(error)*error=zx_frameError(@"-1;;vision_frame_compute_busy\r\n");return NULL;}
    auto frame=zx_snapshotFrame(frameId);
    if(TLinkNativeStopped()){if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(!frame){if(error)*error=zx_frameError(@"-1;;vision_frame_not_found\r\n");return NULL;}
    const uint64_t now=zx_nowMs(),age=now>=frame->createdAtMs?now-frame->createdAtMs:0;
    if(now>=frame->expiresAtMs||age>(maxAgeMs?maxAgeMs:1000)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_expired\r\n");return NULL;
    }
    TLinkVisionROI roi;
    if(!TLinkFrameVisionRegion(frame->width,frame->height,frame->scale,[coord isEqualToString:@"point"],
        region.origin.x,region.origin.y,region.size.width,region.size.height,roi)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_roi_invalid_or_too_large\r\n");return NULL;
    }
    if(!frame->hasBGRA||frame->bgra.empty()||frame->bytesPerRow<frame->width*4||
        size_t(frame->bytesPerRow)>frame->bgra.size()/size_t(frame->height)){
        if(error)*error=zx_frameError(@"-1;;vision_frame_missing_bgra\r\n");return NULL;
    }
    // This reader holds the original ledger charge after store erase/TTL/eviction.
    auto holder=std::unique_ptr<ZXFrameRef>(new(std::nothrow) ZXFrameRef(frame));
    if(!holder){if(error)*error=zx_frameError(@"-1;;vision_frame_provider_failed\r\n");return NULL;}
    CGDataProviderRef provider=CGDataProviderCreateWithData(holder.get(),frame->bgra.data(),
        size_t(frame->bytesPerRow)*frame->height,[](void *info,const void *,size_t){delete static_cast<ZXFrameRef *>(info);});
    if(!provider){if(error)*error=zx_frameError(@"-1;;vision_frame_provider_failed\r\n");return NULL;}
    holder.release(); // Provider now owns the reader; failed creation below also releases it.
    CGImageRef image=NULL;
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    if(color){
        image=CGImageCreate(frame->width,frame->height,8,32,frame->bytesPerRow,color,
            kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst,provider,NULL,false,kCGRenderingIntentDefault);
        CGColorSpaceRelease(color);
    }
    CGDataProviderRelease(provider);
    if(!image){if(error)*error=zx_frameError(@"-1;;vision_frame_image_failed\r\n");return NULL;}
    if(TLinkNativeStopped()){CGImageRelease(image);if(error)*error=zx_frameError(@"-1;;vision_cancelled_or_timed_out\r\n");return NULL;}
    if(pixelRegion)*pixelRegion=CGRectMake(roi.x,roi.y,roi.width,roi.height);
    if(ageMs)*ageMs=age;
    return image;
}
