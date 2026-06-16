#import "TesseractOCRTask.h"
#import "Image.h"

#if ENABLE_TESSERACT_OCR
#import <UIKit/UIKit.h>
#import <TesseractOCR/G8Tesseract.h>
#import <TesseractOCR/G8RecognizedBlock.h>
#import <TesseractOCR/G8TesseractParameters.h>
#endif

#include <dispatch/dispatch.h>
#include <math.h>

static NSString *const kZXTessdataRoot = @"/var/mobile/Library/ZXTouch";

static NSArray<NSString *> *zx_tessSplitEventData(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    return [raw componentsSeparatedByString:@";;"];
}

static NSString *zx_tessBase64(NSString *s)
{
    NSData *data = [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return [data base64EncodedStringWithOptions:0] ?: @"";
}

static NSString *zx_tessDecodeBase64(NSString *s)
{
    if (!s || [s length] == 0) return @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:s options:0];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSError *zx_tessError(NSString *code, NSString *message)
{
    NSString *resp = [NSString stringWithFormat:@"1;;%@;;%@\r\n", code ?: @"ocr_error", zx_tessBase64(message ?: @"")];
    return [NSError errorWithDomain:@"com.zjx.zxtouchsp.ocr"
                               code:999
                           userInfo:@{NSLocalizedDescriptionKey:resp}];
}

static NSString *zx_tessCheckLangs(void)
{
    NSString *dir = [kZXTessdataRoot stringByAppendingPathComponent:@"tessdata"];
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray<NSString *> *langs = [NSMutableArray array];
    for (NSString *file in files ?: @[]) {
        if ([[file pathExtension] isEqualToString:@"traineddata"]) {
            [langs addObject:[file stringByDeletingPathExtension]];
        }
    }
    [langs sortUsingSelector:@selector(compare:)];
    return [NSString stringWithFormat:@"check_langs;;%@", zx_tessBase64([langs componentsJoinedByString:@","])];
}

#if ENABLE_TESSERACT_OCR
static dispatch_queue_t zx_tessQueue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.zjx.zxtouch.tesseractOCR", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSMutableDictionary<NSString *, G8Tesseract *> *zx_tessCache(void)
{
    static NSMutableDictionary<NSString *, G8Tesseract *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

static G8PageSegmentationMode zx_tessPSM(int psm)
{
    switch (psm) {
        case 6: return G8PageSegmentationModeSingleBlock;
        case 8: return G8PageSegmentationModeSingleWord;
        case 7:
        default: return G8PageSegmentationModeSingleLine;
    }
}

static G8OCREngineMode zx_tessOEM(int oem)
{
    if (oem < 0 || oem > 3) return G8OCREngineModeLSTMOnly;
    return (G8OCREngineMode)oem;
}

static UIImage *zx_tessUIImageFromGrayMat(const cv::Mat &gray)
{
    if (gray.empty() || gray.type() != CV_8UC1) return nil;
    cv::Mat continuous = gray.isContinuous() ? gray : gray.clone();
    NSData *data = [NSData dataWithBytes:continuous.data length:(NSUInteger)(continuous.total() * continuous.elemSize())];
    if (!data) return nil;

    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    if (!provider) return nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    if (!colorSpace) {
        CGDataProviderRelease(provider);
        return nil;
    }

    CGImageRef imageRef = CGImageCreate((size_t)continuous.cols,
                                        (size_t)continuous.rows,
                                        8,
                                        8,
                                        (size_t)continuous.step[0],
                                        colorSpace,
                                        kCGImageAlphaNone,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);
    UIImage *image = imageRef ? [UIImage imageWithCGImage:imageRef] : nil;
    if (imageRef) CGImageRelease(imageRef);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    return image;
}

static double zx_tessMeanConfidence(G8Tesseract *tesseract)
{
    NSArray *blocks = [tesseract recognizedBlocksByIteratorLevel:G8PageIteratorLevelTextline];
    if ([blocks count] == 0) {
        blocks = [tesseract recognizedBlocksByIteratorLevel:G8PageIteratorLevelWord];
    }
    double sum = 0.0;
    NSUInteger count = 0;
    for (G8RecognizedBlock *block in blocks ?: @[]) {
        if (![block isKindOfClass:[G8RecognizedBlock class]]) continue;
        sum += block.confidence;
        count++;
    }
    return count > 0 ? sum / (double)count : -1.0;
}

static NSString *zx_tessRunOCR(cv::Mat &gray,
                               NSString *lang,
                               int oem,
                               int psm,
                               NSString *whitelist,
                               int scaleUp,
                               int thresholdMode,
                               uint64_t frameAgeMs,
                               NSError **error)
{
    CFAbsoluteTime total0 = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime prep0 = CFAbsoluteTimeGetCurrent();

    cv::Mat work = gray;
    if (scaleUp < 1) scaleUp = 1;
    if (scaleUp > 4) scaleUp = 4;
    if (scaleUp > 1) {
        cv::resize(work, work, cv::Size(), scaleUp, scaleUp, cv::INTER_CUBIC);
    } else {
        work = work.clone();
    }

    if (thresholdMode == 1) {
        cv::threshold(work, work, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    } else if (thresholdMode == 2) {
        int blockSize = MAX(11, ((MIN(work.cols, work.rows) / 12) | 1));
        if (blockSize % 2 == 0) blockSize++;
        cv::adaptiveThreshold(work, work, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, blockSize, 7);
    }

    UIImage *image = zx_tessUIImageFromGrayMat(work);
    double preprocessMs = (CFAbsoluteTimeGetCurrent() - prep0) * 1000.0;
    if (!image) {
        if (error) *error = zx_tessError(@"image_convert_failed", @"Failed to convert OCR region to UIImage.");
        return nil;
    }

    NSString *key = [NSString stringWithFormat:@"%@|%d|%d|%@", lang ?: @"vie", oem, psm, whitelist ?: @""];
    G8Tesseract *tesseract = zx_tessCache()[key];
    if (!tesseract) {
        tesseract = [[G8Tesseract alloc] initWithLanguage:(lang && [lang length] > 0) ? lang : @"vie"
                                         configDictionary:nil
                                          configFileNames:nil
                                         absoluteDataPath:kZXTessdataRoot
                                               engineMode:zx_tessOEM(oem)];
        if (!tesseract || !tesseract.isEngineConfigured) {
            if (error) *error = zx_tessError(@"engine_init_failed", @"Failed to initialize Tesseract. Check tessdata files and OEM compatibility.");
            return nil;
        }
        tesseract.pageSegmentationMode = zx_tessPSM(psm);
        if (whitelist && [whitelist length] > 0) {
            tesseract.charWhitelist = whitelist;
        }
        tesseract.maximumRecognitionTime = 3.0;
        zx_tessCache()[key] = tesseract;
    }

    CFAbsoluteTime ocr0 = CFAbsoluteTimeGetCurrent();
    tesseract.image = image;
    tesseract.rect = CGRectMake(0, 0, image.size.width, image.size.height);
    BOOL recognized = [tesseract recognize];
    double ocrMs = (CFAbsoluteTimeGetCurrent() - ocr0) * 1000.0;
    if (!recognized) {
        if (error) *error = zx_tessError(@"recognize_failed", @"Tesseract recognition failed.");
        return nil;
    }

    NSString *text = [tesseract.recognizedText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    double confidence = zx_tessMeanConfidence(tesseract);
    double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
    return [NSString stringWithFormat:@"%@;;%.2f;;%llu;;%.3f;;%.3f;;%.3f",
            zx_tessBase64(text),
            confidence,
            (unsigned long long)frameAgeMs,
            ocrMs,
            preprocessMs,
            totalMs];
}
#endif

NSString *handleTesseractOCRTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([[raw lowercaseString] isEqualToString:@"check_langs"]) {
        return zx_tessCheckLangs();
    }

#if !ENABLE_TESSERACT_OCR
    if (error) *error = zx_tessError(@"disabled", @"Tesseract OCR is not enabled in this build.");
    return nil;
#else
    NSArray<NSString *> *data = zx_tessSplitEventData(eventData);
    if ([data count] < 13) {
        if (error) *error = zx_tessError(@"bad_format", @"Format: frame_id;;x;;y;;w;;h;;lang;;oem;;psm;;whitelist_b64;;scale_up;;threshold_mode;;coord;;max_age_ms");
        return nil;
    }

    uint32_t frameId = (uint32_t)[data[0] intValue];
    int x = [data[1] intValue];
    int y = [data[2] intValue];
    int w = [data[3] intValue];
    int h = [data[4] intValue];
    NSString *lang = ([data[5] length] > 0) ? data[5] : @"vie";
    int oem = ([data[6] length] > 0) ? [data[6] intValue] : 1;
    int psm = ([data[7] length] > 0) ? [data[7] intValue] : 7;
    NSString *whitelist = zx_tessDecodeBase64(data[8]);
    int scaleUp = ([data[9] length] > 0) ? [data[9] intValue] : 2;
    int thresholdMode = ([data[10] length] > 0) ? [data[10] intValue] : 0;
    NSString *coord = ([data[11] length] > 0) ? data[11] : @"pixel";
    uint64_t maxAgeMs = (uint64_t)MAX(0, [data[12] longLongValue]);
    if (maxAgeMs == 0) maxAgeMs = 1000;

    __block NSString *ret = nil;
    __block NSError *blockErr = nil;
    dispatch_sync(zx_tessQueue(), ^{
        cv::Mat gray;
        uint64_t frameAgeMs = 0;
        if (!zx_copyFrameGrayRegionForOCR(frameId, x, y, w, h, coord, maxAgeMs, gray, &frameAgeMs, &blockErr)) {
            return;
        }
        ret = zx_tessRunOCR(gray, lang, oem, psm, whitelist, scaleUp, thresholdMode, frameAgeMs, &blockErr);
    });

    if (blockErr) {
        if (error) *error = blockErr;
        return nil;
    }
    return ret;
#endif
}
