// Real file/ImageIO/store/owner adapters; only script environment and CV are doubled.
using cv::Mat;
static NSString *imageOpenFixtureRoot,*imageOpenFixtureScript;
static NSString *zx_currentScriptDir(){return imageOpenFixtureScript;}
static NSString *getScriptsFolder(){return imageOpenFixtureRoot;}
#include "ImageOpenResolverUnderTest.inc"
#include "ImageOpenOwnerUnderTest.inc"
#include "ImageOpenUnderTest.inc"
#include "ImageOpenActionUnderTest.inc"
#include "fixtures/image-open-handler-legacy-v1.inc"
static void imageOpenWritePNG(NSString *path){
    NSMutableData *encoded=[NSMutableData data];uint8_t pixels[24]={};
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(pixels,2,3,8,8,color,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(color);assert(context);
    CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);assert(image);
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded,CFSTR("public.png"),1,nullptr);assert(destination);
    CGImageDestinationAddImage(destination,image,nullptr);assert(CGImageDestinationFinalize(destination));CFRelease(destination);CGImageRelease(image);
    assert([encoded writeToFile:path atomically:true]);
}
static void clearImageOpenFixture(){TLinkNativeImageReleaseRequest release;release.all=true;releaseStoredImages(release);assert(gImageMemory.stats().images==0);}
static ZXImageRef imageOpenReader(uint32_t id){__block ZXImageRef reader;dispatch_sync(zx_imageQueue(),^{auto it=gImageStore.find(id);if(it!=gImageStore.end())reader=it->second;});return reader;}
static void imageOpenRuntimeCases(NSString *directory){
    imageOpenFixtureRoot=directory;imageOpenFixtureScript=directory;
    NSString *path=[directory stringByAppendingPathComponent:@"open.png"];imageOpenWritePNG(path);
    NSString *unicodePath=[directory stringByAppendingPathComponent:@"ảnh🙂.png"];imageOpenWritePNG(unicodePath);
    cv::decoderWidth=2;cv::decoderHeight=3;
    NSArray *names=@[@"open.png",path,@"ảnh🙂.png",@"./open.png",@"open.png;;shifted",@"open.png;",@"missing.png"];
    NSArray *owners=@[@"session;;run;;js",@";;;;",@"a;;b;;js \t",@"a;;;;legacy",@"a;;;b;;js",@"a;;b;;js;;ignored"];
    for(unsigned n=0;n<96;++n){
        imageOpenFixtureScript=n%2?directory:nil;
        NSString *command=[NSString stringWithFormat:@"2;;%@;;%@",names[n%names.count],owners[(n/3)%owners.count]];
        NSError *oldError=nil;NSString *old=legacyImageOpenTask((UInt8 *)command.UTF8String,&oldError);
        NSArray *oldParts=[old componentsSeparatedByString:@";;"];auto oldReader=old?imageOpenReader(uint32_t([oldParts[0] intValue])):ZXImageRef{};
        TLinkNativeImageReleaseRequest release;release.all=true;releaseStoredImages(release);
        for(unsigned variant=0;variant<2;++variant){
            NSError *error=nil;NSString *current=nil;uint32_t published=0;
            if(!variant)current=imageOpenActionUnderTest((UInt8 *)command.UTF8String,&error);
            else{
                NSArray *fields=[[NSString stringWithFormat:@"%s",command.UTF8String] componentsSeparatedByString:@";;"];
                TLinkNativeImageOpenRequest request;request.path=fields[1];request.sessionId=zx_stringFromPart(fields,2,"");request.runId=zx_stringFromPart(fields,3,"");request.runtime=zx_stringFromPart(fields,4,"legacy");
                current=openStoredImage(request,published,&error);
            }
            assert((!old&&!current)||(old&&current));assert((!error&&!oldError)||[error.localizedDescription isEqual:oldError.localizedDescription]);
            if(current){
                NSArray *parts=[current componentsSeparatedByString:@";;"];const uint32_t id=uint32_t([parts[0] intValue]);auto reader=imageOpenReader(id);
                assert(parts.count==3&&[oldParts[1] isEqual:parts[1]]&&[oldParts[2] isEqual:parts[2]]&&reader&&oldReader);
                assert(reader->w==oldReader->w&&reader->h==oldReader->h&&reader->ownerSessionId==oldReader->ownerSessionId&&reader->ownerRunId==oldReader->ownerRunId&&reader->ownerRuntime==oldReader->ownerRuntime&&reader->ttlMs==0);
                if(variant)assert(published==id);releaseStoredImages(release);assert(!reader->gray.empty());reader.reset();
            }else assert(!published);
        }
        oldReader.reset();clearImageOpenFixture();
    }
    TLinkNativeImageOpenRequest request;request.path=path;uint32_t id=999;NSError *error=nil;const int calls=cv::decoderCalls;
    {TLinkImageWork a(gImageCompute),b(gImageCompute);assert(a&&b);assert(!openStoredImage(request,id,&error)&&!id&&cv::decoderCalls==calls&&[error.localizedDescription containsString:@"image_compute_busy"]);}
    {auto full=gImageMemory.reserve(TLinkImageKind::Image,64*1024*1024);assert(full);error=nil;assert(!openStoredImage(request,id,&error)&&!id&&cv::decoderCalls==calls&&[error.localizedDescription containsString:@"image_memory_budget"]);}
    for(unsigned n=0;n<64;++n)publishImage(imageFixture());error=nil;
    assert(!openStoredImage(request,id,&error)&&!id&&cv::decoderCalls==calls&&[error.localizedDescription containsString:@"image_memory_budget"]);clearImageOpenFixture();
    __block uint32_t saved=0;dispatch_sync(zx_imageQueue(),^{saved=gNextImageId;gNextImageId=0;});error=nil;
    assert(!openStoredImage(request,id,&error)&&!id&&[error.localizedDescription containsString:@"Image object limit reached"]);dispatch_sync(zx_imageQueue(),^{gNextImageId=saved;});clearImageOpenFixture();
    cv::decoderWidth=4;error=nil;assert(!openStoredImage(request,id,&error)&&!id&&[error.localizedDescription containsString:@"image_decode_dimension_mismatch"]);cv::decoderWidth=2;clearImageOpenFixture();
    error=nil;NSString *missing=imageOpenActionUnderTest((UInt8 *)"2",&error);assert(!missing&&[error.localizedDescription containsString:@"Image open format"]);
    NSString *bad=[directory stringByAppendingPathComponent:@"open-bad.png"];assert([[NSData dataWithBytes:"invalid" length:7] writeToFile:bad atomically:true]);request.path=bad;error=nil;
    assert(!openStoredImage(request,id,&error)&&!id&&[error.localizedDescription containsString:@"image_pixel_limit_or_invalid_metadata"]);clearImageOpenFixture();
    NSString *large=[directory stringByAppendingPathComponent:@"open-large.png"];NSData *oversized=[NSMutableData dataWithLength:32*1024*1024+1];assert([oversized writeToFile:large atomically:true]);request.path=large;error=nil;
    assert(!openStoredImage(request,id,&error)&&!id&&[error.localizedDescription containsString:@"image_encoded_limit_or_read_failed"]);clearImageOpenFixture();
    imageOpenFixtureRoot=nil;imageOpenFixtureScript=nil;
    puts("Image open Foundation passed: 96 frozen old/RAW/direct path/owner/store comparisons, real PNG/ImageIO, held readers, admission/count/bytes/decode/publication faults and zero final charges. CV decoding remains controlled.");
}
