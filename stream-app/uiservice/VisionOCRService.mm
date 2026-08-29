#import "VisionOCRService.h"

#import <CoreML/CoreML.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *const kTLinkVisionCPUErrorDomain = @"com.tlinkauto.uiservice.vision.cpu";
static NSString *const kTLinkVisionOCRDebugLogPath = @"/var/mobile/Library/TLinkauto/runtime/vision-ocr-debug.log";
static const uint16_t kTLinkVisionOCRPort = 6018;
static const NSTimeInterval kTLinkVisionOCRWatchdogSeconds = 15.0;

static BOOL sTLinkVisionServerStarted = NO;
static BOOL sTLinkVisionServerListening = NO;
static BOOL sTLinkVisionRequestInFlight = NO;
static NSUInteger sTLinkVisionRequestCount = 0;
static NSUInteger sTLinkVisionSuccessCount = 0;
static NSUInteger sTLinkVisionFailureCount = 0;
static NSString *sTLinkVisionLastResult = @"not_started";
static dispatch_queue_t sTLinkVisionQueue = nil;

static void TLinkVisionAppendDebug(NSString *profile, NSString *phase, NSString *detail)
{
    NSString *runtimeDir = [kTLinkVisionOCRDebugLogPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:runtimeDir
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0755}
                                                    error:nil];
    NSString *safeDetail = [[detail ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "]
                            stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSString *line = [NSString stringWithFormat:@"%.6f pid=%d uid=%d profile=%@ host=background_uiservice_6018 phase=%@ %@\n",
                      CFAbsoluteTimeGetCurrent(), getpid(), getuid(),
                      profile.length > 0 ? profile : @"unknown",
                      phase.length > 0 ? phase : @"unknown", safeDetail];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized([NSProcessInfo class]) {
        int fd = open([kTLinkVisionOCRDebugLogPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) return;
        struct stat logStat;
        if (fstat(fd, &logStat) == 0 && logStat.st_size > (1024 * 1024)) ftruncate(fd, 0);
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        NSUInteger remaining = data.length;
        while (remaining > 0) {
            ssize_t written = write(fd, bytes, remaining);
            if (written <= 0) break;
            bytes += written;
            remaining -= (NSUInteger)written;
        }
        close(fd);
    }
}

static CVReturn TLinkVisionProbePixelBuffer(size_t width,
                                             size_t height,
                                             OSType pixelFormat,
                                             BOOL useIOSurface,
                                             BOOL requireOpenGLES,
                                             BOOL requireMetal)
{
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (useIOSurface) attributes[(id)kCVPixelBufferIOSurfacePropertiesKey] = @{};
    if (requireOpenGLES) attributes[(id)kCVPixelBufferOpenGLESCompatibilityKey] = @YES;
    if (requireMetal) attributes[(id)kCVPixelBufferMetalCompatibilityKey] = @YES;
    CVPixelBufferRef buffer = NULL;
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat,
        attributes.count > 0 ? (__bridge CFDictionaryRef)attributes : NULL, &buffer);
    if (buffer) CVPixelBufferRelease(buffer);
    return result;
}

static BOOL TLinkVisionConfigureCPUOnly(VNRequest *request, NSError **outError)
{
    if (!request) return NO;
    if (@available(iOS 17.0, *)) {
        NSError *deviceError = nil;
        NSDictionary *supportedDevices = [request supportedComputeStageDevicesAndReturnError:&deviceError];
        if (supportedDevices.count == 0) {
            if (outError) {
                *outError = [NSError errorWithDomain:kTLinkVisionCPUErrorDomain code:2
                    userInfo:@{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:@"vision_cpu_device_query_failed %@",
                         deviceError.localizedDescription ?: @"no_compute_stages"]}];
            }
            return NO;
        }
        for (VNComputeStage stage in supportedDevices) {
            id<MLComputeDeviceProtocol> cpuDevice = nil;
            for (id<MLComputeDeviceProtocol> device in supportedDevices[stage]) {
                if ([device isKindOfClass:[MLCPUComputeDevice class]]) {
                    cpuDevice = device;
                    break;
                }
            }
            if (!cpuDevice) {
                if (outError) {
                    *outError = [NSError errorWithDomain:kTLinkVisionCPUErrorDomain code:3
                        userInfo:@{NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"vision_cpu_unavailable_for_stage %@", stage]}];
                }
                return NO;
            }
            [request setComputeDevice:cpuDevice forComputeStage:stage];
        }
        return YES;
    }
    request.usesCPUOnly = YES;
    return YES;
}

static NSString *TLinkVisionSafeText(NSString *text)
{
    NSMutableString *safe = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "] mutableCopy];
    [safe replaceOccurrencesOfString:@"\n" withString:@" " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@";;" withString:@"; " options:0 range:NSMakeRange(0, safe.length)];
    [safe replaceOccurrencesOfString:@",," withString:@", " options:0 range:NSMakeRange(0, safe.length)];
    return safe ?: @"";
}

static NSString *TLinkVisionDecodeBase64(NSString *field)
{
    if (field.length == 0) return @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:field options:0];
    return data ? ([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"") : @"";
}

static NSArray<NSString *> *TLinkVisionNonEmptyValues(NSString *value)
{
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *item in [value ?: @"" componentsSeparatedByString:@",,"]) {
        if (item.length > 0) [result addObject:item];
    }
    return result;
}

static CGImageRef TLinkVisionCreateRGBImage(NSData *imageData, NSString **error) CF_RETURNS_RETAINED
{
    if (imageData.length == 0) {
        if (error) *error = @"empty_image_data";
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!source) {
        if (error) *error = @"image_source_create_failed";
        return nil;
    }
    CGImageRef decoded = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!decoded) {
        if (error) *error = @"image_decode_failed";
        return nil;
    }
    size_t width = CGImageGetWidth(decoded);
    size_t height = CGImageGetHeight(decoded);
    if (width == 0 || height == 0 || width > 12000 || height > 12000) {
        CGImageRelease(decoded);
        if (error) *error = @"image_bad_dimensions";
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = width * 4;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, bytesPerRow, colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        CGImageRelease(decoded);
        if (error) *error = @"compact_bgra_context_create_failed";
        return nil;
    }
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), decoded);
    CGImageRef rgbImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(decoded);
    if (!rgbImage && error) *error = @"rgb_image_create_failed";
    return rgbImage;
}

static BOOL TLinkVisionPerform(CGImageRef image,
                               NSString *profile,
                               VNRequestTextRecognitionLevel level,
                               CGFloat minimumTextHeight,
                               NSArray<NSString *> *customWords,
                               NSArray<NSString *> *languages,
                               BOOL languageCorrection,
                               VNRecognizeTextRequest **outRequest,
                               NSError **outError)
{
    BOOL xxtCompat = [profile isEqualToString:@"xxt_compat"];
    VNRecognizeTextRequest *request = xxtCompat
        ? [[VNRecognizeTextRequest alloc] init]
        : [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(__unused VNRequest *finished,
                                                                      __unused NSError *error) {}];
    request.recognitionLevel = level;
    if (minimumTextHeight > 0.0) request.minimumTextHeight = minimumTextHeight;
    if (customWords.count > 0) request.customWords = customWords;
    request.recognitionLanguages = languages.count > 0 ? languages : @[@"en-US"];
    request.usesLanguageCorrection = languageCorrection;
    if (!xxtCompat && !TLinkVisionConfigureCPUOnly(request, outError)) return NO;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image
        orientation:kCGImagePropertyOrientationUp options:@{}];
    NSError *visionError = nil;
    BOOL ok = [handler performRequests:@[request] error:&visionError];
    if (ok) {
        if (outRequest) *outRequest = request;
        return YES;
    }
    if (outError) *outError = visionError;
    return NO;
}

static NSString *TLinkVisionPerformRequest(NSString *line)
{
    NSArray<NSString *> *parts = [[line ?: @"" stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@";;"];
    BOOL version2Request = parts.count >= 12 && [parts[0] isEqualToString:@"2"];
    if (!version2Request) return @"-1;;uiservice_ocr_bad_request protocol=2_required\r\n";

    NSString *imagePath = parts[1];
    if (![imagePath hasPrefix:@"/var/mobile/Library/TLinkauto/tmp/appocr-"]) {
        return @"-1;;uiservice_ocr_path_rejected\r\n";
    }
    NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
    if (imageData.length == 0 || imageData.length > (32 * 1024 * 1024)) {
        return [NSString stringWithFormat:@"-1;;uiservice_ocr_png_missing_or_too_large path=%@\r\n", imagePath];
    }
    if (@available(iOS 13.0, *)) {
        // Continue below. Keeping this check local makes the RPC fail closed
        // on an older runtime without touching the toast service.
    } else {
        return @"-1;;uiservice_ocr_requires_ios13\r\n";
    }

    CGFloat originX = [parts[2] doubleValue];
    CGFloat originY = [parts[3] doubleValue];
    CGFloat regionW = MAX(1.0, [parts[4] doubleValue]);
    CGFloat regionH = MAX(1.0, [parts[5] doubleValue]);
    CGFloat minimumTextHeight = (CGFloat)[parts[6] doubleValue];
    int levelValue = [parts[7] intValue];
    NSString *customWords = TLinkVisionDecodeBase64(parts[8]);
    NSString *languages = TLinkVisionDecodeBase64(parts[9]);
    BOOL languageCorrection = [parts[10] intValue] != 0;
    NSString *profile = [parts[11] lowercaseString];
    if (![profile isEqualToString:@"app_cpu"] && ![profile isEqualToString:@"xxt_compat"]) {
        return [NSString stringWithFormat:@"-1;;uiservice_ocr_bad_profile %@\r\n", profile ?: @""];
    }

    NSString *decodeError = nil;
    CGImageRef rgbImage = TLinkVisionCreateRGBImage(imageData, &decodeError);
    if (!rgbImage) {
        return [NSString stringWithFormat:@"-1;;uiservice_ocr_rgb_decode_failed %@\r\n",
                                          decodeError ?: @"unknown"];
    }
    VNRequestTextRecognitionLevel level = levelValue == 1
        ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    NSString *imageDetail = [NSString stringWithFormat:
        @"app_state=%ld width=%zu height=%zu bpc=%zu bpp=%zu bpr=%zu bitmapInfo=0x%lx level=%d",
        (long)UIApplication.sharedApplication.applicationState, CGImageGetWidth(rgbImage),
        CGImageGetHeight(rgbImage), CGImageGetBitsPerComponent(rgbImage),
        CGImageGetBitsPerPixel(rgbImage), CGImageGetBytesPerRow(rgbImage),
        (unsigned long)CGImageGetBitmapInfo(rgbImage), levelValue];
    TLinkVisionAppendDebug(profile, @"uiservice_request_setup", imageDetail);

    size_t width = CGImageGetWidth(rgbImage);
    size_t height = CGImageGetHeight(rgbImage);
    CVReturn bgraMemory = TLinkVisionProbePixelBuffer(width, height, kCVPixelFormatType_32BGRA, NO, NO, NO);
    CVReturn yuvMemory = TLinkVisionProbePixelBuffer(width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, NO, NO, NO);
    CVReturn yuvIOSurface = TLinkVisionProbePixelBuffer(width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, YES, NO, NO);
    CVReturn yuvOpenGLES = TLinkVisionProbePixelBuffer(width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, YES, YES, NO);
    CVReturn yuvMetal = TLinkVisionProbePixelBuffer(width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, YES, NO, YES);
    TLinkVisionAppendDebug(profile, @"uiservice_pixelbuffer_probe", [NSString stringWithFormat:
        @"width=%zu height=%zu bgra_memory=%d 420f_memory=%d 420f_iosurface=%d 420f_opengles=%d 420f_metal=%d",
        width, height, (int)bgraMemory, (int)yuvMemory, (int)yuvIOSurface,
        (int)yuvOpenGLES, (int)yuvMetal]);
    TLinkVisionAppendDebug(profile, @"uiservice_perform_begin", imageDetail);

    VNRecognizeTextRequest *request = nil;
    NSError *visionError = nil;
    CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
    BOOL ok = TLinkVisionPerform(rgbImage, profile, level, minimumTextHeight,
        TLinkVisionNonEmptyValues(customWords), TLinkVisionNonEmptyValues(languages),
        languageCorrection, &request, &visionError);
    NSString *firstError = visionError.localizedDescription ?: @"unknown";
    if (!ok && [profile isEqualToString:@"app_cpu"] && level == VNRequestTextRecognitionLevelFast) {
        visionError = nil;
        ok = TLinkVisionPerform(rgbImage, profile, VNRequestTextRecognitionLevelAccurate,
            minimumTextHeight, TLinkVisionNonEmptyValues(customWords),
            TLinkVisionNonEmptyValues(languages), languageCorrection, &request, &visionError);
    }
    double elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000.0;
    CGImageRelease(rgbImage);
    if (!ok) {
        TLinkVisionAppendDebug(profile, @"uiservice_perform_failed", [NSString stringWithFormat:
            @"elapsed_ms=%.3f first=%@ retry=%@", elapsedMs, firstError,
            visionError.localizedDescription ?: @"unknown"]);
        return [NSString stringWithFormat:@"-1;;uiservice_ocr_failed profile=%@ error=%@\r\n",
            profile, visionError.localizedDescription ?: firstError];
    }
    TLinkVisionAppendDebug(profile, @"uiservice_perform_end", [NSString stringWithFormat:
        @"elapsed_ms=%.3f observations=%lu", elapsedMs, (unsigned long)request.results.count]);

    NSMutableArray<NSString *> *output = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        if (![observation isKindOfClass:[VNRecognizedTextObservation class]]) continue;
        VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
        if (!candidate.string.length) continue;
        CGRect bb = observation.boundingBox;
        int x = (int)llround(originX + bb.origin.x * regionW);
        int y = (int)llround(originY + (1.0 - bb.origin.y - bb.size.height) * regionH);
        int w = (int)llround(bb.size.width * regionW);
        int h = (int)llround(bb.size.height * regionH);
        [output addObject:[NSString stringWithFormat:@"%@,,%d,,%d,,%d,,%d",
            TLinkVisionSafeText(candidate.string), x, y, w, h]];
    }
    TLinkVisionAppendDebug(profile, @"uiservice_response_ready",
        [NSString stringWithFormat:@"results=%lu", (unsigned long)output.count]);
    return [NSString stringWithFormat:@"0;;%@\r\n", [output componentsJoinedByString:@";;"]];
}

static NSString *TLinkVisionHandleLine(NSString *line)
{
    NSString *trimmed = [line ?: @"" stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed isEqualToString:@"0"]) {
        TLinkVisionAppendDebug(@"bridge", @"uiservice_bridge_probe",
            [NSString stringWithFormat:@"app_state=%ld", (long)UIApplication.sharedApplication.applicationState]);
        return [NSString stringWithFormat:
            @"0;;uiservice_ocr_ready;;version=1;;port=6018;;pid=%d;;uid=%d;;app_state=%ld;;scene_required=0\r\n",
            getpid(), getuid(), (long)UIApplication.sharedApplication.applicationState];
    }

    @synchronized([NSProcessInfo class]) {
        if (sTLinkVisionRequestInFlight) return @"-1;;uiservice_ocr_busy previous_request_in_flight\r\n";
        sTLinkVisionRequestInFlight = YES;
        sTLinkVisionRequestCount += 1;
    }
    __block NSString *response = nil;
    dispatch_semaphore_t completed = dispatch_semaphore_create(0);
    dispatch_async(sTLinkVisionQueue, ^{
        @autoreleasepool {
            response = TLinkVisionPerformRequest(line);
            @synchronized([NSProcessInfo class]) {
                sTLinkVisionRequestInFlight = NO;
                if ([response hasPrefix:@"0"] ) sTLinkVisionSuccessCount += 1;
                else sTLinkVisionFailureCount += 1;
                sTLinkVisionLastResult = [response hasPrefix:@"0"] ? @"success" : @"failed";
            }
            dispatch_semaphore_signal(completed);
        }
    });
    long waitResult = dispatch_semaphore_wait(completed,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTLinkVisionOCRWatchdogSeconds * NSEC_PER_SEC)));
    if (waitResult != 0) {
        TLinkVisionAppendDebug(@"unknown", @"uiservice_watchdog_timeout", @"timeout_ms=15000");
        @synchronized([NSProcessInfo class]) {
            sTLinkVisionFailureCount += 1;
            sTLinkVisionLastResult = @"watchdog_timeout";
        }
        return @"-1;;uiservice_ocr_timeout timeout_ms=15000 restart_TLinkUIService_before_retry\r\n";
    }
    return response ?: @"-1;;uiservice_ocr_empty_response\r\n";
}

static NSString *TLinkVisionReadLine(int client)
{
    struct timeval timeout = {3, 0};
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    NSMutableData *data = [NSMutableData data];
    char byte = 0;
    while (data.length < 65536) {
        ssize_t count = read(client, &byte, 1);
        if (count <= 0 || byte == '\n') break;
        [data appendBytes:&byte length:1];
    }
    return data.length > 0 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static void TLinkVisionWriteAll(int client, NSString *response)
{
    NSData *data = [(response ?: @"-1;;uiservice_ocr_empty_response\r\n") dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(client, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
}

static void TLinkRunVisionServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int yes = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(kTLinkVisionOCRPort);
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 4) != 0) {
        @synchronized([NSProcessInfo class]) { sTLinkVisionLastResult = @"bind_failed"; }
        TLinkVisionAppendDebug(@"bridge", @"uiservice_server_bind_failed",
            [NSString stringWithFormat:@"errno=%d", errno]);
        close(server);
        return;
    }
    @synchronized([NSProcessInfo class]) {
        sTLinkVisionServerListening = YES;
        sTLinkVisionLastResult = @"listening";
    }
    TLinkVisionAppendDebug(@"bridge", @"uiservice_server_listening", @"port=6018 scene_required=0");
    while (1) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
#ifdef SO_NOSIGPIPE
        int noSigPipe = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif
        @autoreleasepool {
            NSString *request = TLinkVisionReadLine(client);
            TLinkVisionWriteAll(client, request.length > 0
                ? TLinkVisionHandleLine(request) : @"-1;;uiservice_ocr_empty_request\r\n");
            close(client);
        }
    }
    close(server);
    @synchronized([NSProcessInfo class]) {
        sTLinkVisionServerListening = NO;
        sTLinkVisionLastResult = @"server_stopped";
    }
}

void TLinkStartVisionOCRService(void)
{
    @synchronized([NSProcessInfo class]) {
        if (sTLinkVisionServerStarted) return;
        sTLinkVisionServerStarted = YES;
        sTLinkVisionQueue = dispatch_queue_create("com.tlinkauto.uiservice.vision-ocr", DISPATCH_QUEUE_SERIAL);
    }
    NSThread *thread = [[NSThread alloc] initWithBlock:^{ TLinkRunVisionServer(); }];
    thread.name = @"com.tlinkauto.uiservice.vision-server";
    [thread start];
}

NSString *TLinkVisionOCRServiceProbeSummary(void)
{
    @synchronized([NSProcessInfo class]) {
        return [NSString stringWithFormat:
            @"vision_ocr_port=6018;;vision_ocr_protocol=1;;vision_ocr_started=%d;;vision_ocr_listening=%d;;vision_ocr_scene_required=0;;vision_ocr_request_count=%lu;;vision_ocr_success_count=%lu;;vision_ocr_failure_count=%lu;;vision_ocr_inflight=%d;;vision_ocr_last_result=%@",
            sTLinkVisionServerStarted ? 1 : 0, sTLinkVisionServerListening ? 1 : 0,
            (unsigned long)sTLinkVisionRequestCount, (unsigned long)sTLinkVisionSuccessCount,
            (unsigned long)sTLinkVisionFailureCount, sTLinkVisionRequestInFlight ? 1 : 0,
            sTLinkVisionLastResult ?: @"unknown"];
    }
}

NSDictionary<NSString *, id> *TLinkVisionOCRServiceDiagnostics(void)
{
    @synchronized([NSProcessInfo class]) {
        return @{
            @"vision_ocr_port": @(kTLinkVisionOCRPort),
            @"vision_ocr_protocol": @1,
            @"vision_ocr_started": @(sTLinkVisionServerStarted),
            @"vision_ocr_listening": @(sTLinkVisionServerListening),
            @"vision_ocr_scene_required": @NO,
            @"vision_ocr_request_count": @(sTLinkVisionRequestCount),
            @"vision_ocr_success_count": @(sTLinkVisionSuccessCount),
            @"vision_ocr_failure_count": @(sTLinkVisionFailureCount),
            @"vision_ocr_inflight": @(sTLinkVisionRequestInFlight),
            @"vision_ocr_last_result": sTLinkVisionLastResult ?: @"unknown",
        };
    }
}
