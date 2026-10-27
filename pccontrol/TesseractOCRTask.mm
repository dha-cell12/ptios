#include "../shared/TLinkNativeDispatch.h"
#include "../shared/TLinkOCRPolicy.h"
#import "TesseractOCRTask.h"
#import "Image.h"

#if ENABLE_TESSERACT_OCR
#import <UIKit/UIKit.h>
#import <TesseractOCR/G8Tesseract.h>
#import <TesseractOCR/G8RecognizedBlock.h>
#import <TesseractOCR/G8TesseractParameters.h>

@interface ZXTessBudgetDelegate : NSObject <G8TesseractDelegate> {
    TLinkOCRBudgetPtr _budget;
}
- (instancetype)initWithBudget:(TLinkOCRBudgetPtr)budget;
@end
@implementation ZXTessBudgetDelegate
- (instancetype)initWithBudget:(TLinkOCRBudgetPtr)budget { self = [super init]; if (self) _budget = std::move(budget); return self; }
- (BOOL)shouldCancelImageRecognitionForTesseract:(G8Tesseract *)tesseract { (void)tesseract; return _budget && _budget->stopped(); }
@end

#endif

#include <dispatch/dispatch.h>
#include <math.h>

static std::atomic<unsigned> sZXTessActive{0}, sZXTessEntries{0};
static std::atomic<bool> sZXTessPurgeQueued{false};
static std::atomic<uint64_t> sZXTessEpoch{1}, sZXTessHits{0}, sZXTessMisses{0}, sZXTessBusy{0}, sZXTessPressure{0};
NSDictionary *TLinkTesseractOCRPerformance(void) {
    return @{@"cache_entries": @(sZXTessEntries.load()), @"cache_entry_limit": @2, @"cache_hits": @(sZXTessHits.load()),
        @"cache_misses": @(sZXTessMisses.load()), @"active_requests": @(sZXTessActive.load()), @"request_limit": @2,
        @"busy_count": @(sZXTessBusy.load()), @"memory_pressure_count": @(sZXTessPressure.load()),
        @"scaled_pixel_limit": @(kTLinkOCRMaxScaledPixels), @"visible_gray_byte_limit": @(kTLinkOCRVisibleGrayBytes),
        @"request_budget_ms": @3000};
}

static NSString *const kZXTessdataRoot = @"/var/mobile/Library/TLinkauto";

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
    return [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp.ocr"
                               code:999
                           userInfo:@{NSLocalizedDescriptionKey:resp}];
}

// BEGIN structured frame OCR result.
TLinkNativeFrameOCRValue TLinkFormatFrameOCRValue(NSString *text,double confidence,uint64_t ageMs,double ocrMs,double preprocessMs,double totalMs){
    TLinkNativeFrameOCRValue value;
    NSData *utf8=[(text?:@"") dataUsingEncoding:NSUTF8StringEncoding];
    // Keep the legacy UTF-8 normalization without decoding our own Base64 column.
    value.text=utf8?([[NSString alloc] initWithData:utf8 encoding:NSUTF8StringEncoding]?:@""):@"";
    value.columns=@[[utf8 base64EncodedStringWithOptions:0]?:@"",[NSString stringWithFormat:@"%.2f",confidence],
        [NSString stringWithFormat:@"%llu",(unsigned long long)ageMs],[NSString stringWithFormat:@"%.3f",ocrMs],
        [NSString stringWithFormat:@"%.3f",preprocessMs],[NSString stringWithFormat:@"%.3f",totalMs]];
    value.body=[value.columns componentsJoinedByString:@";;"];
    return value;
}
// END structured frame OCR result.

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

NSString *TLinkTesseractOCRLanguages(void)
{
    return zx_tessCheckLangs();
}

#if ENABLE_TESSERACT_OCR
static dispatch_queue_t zx_tessQueue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.tlinkauto.tlinkauto.tesseractOCR", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

using ZXTessCache = TLinkOCRLRU<std::string, G8Tesseract *>;
static ZXTessCache &zx_tessCache(void) {
    static ZXTessCache cache;
    return cache;
}
static void zx_tessPurgeCache(void) { zx_tessCache().clear(); sZXTessEntries.store(0); }
static void zx_tessMemoryPressure(void) {
    sZXTessPressure.fetch_add(1); sZXTessEpoch.fetch_add(1);
    if (!sZXTessPurgeQueued.exchange(true)) dispatch_async(zx_tessQueue(), ^{ sZXTessPurgeQueued.store(false); zx_tessPurgeCache(); });
}
static void zx_tessObserveMemoryPressure(void) {
    static dispatch_once_t once;
    static dispatch_source_t source;
    static id warningObserver;
    dispatch_once(&once, ^{
        warningObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
            object:nil queue:nil usingBlock:^(NSNotification *note) { (void)note; zx_tessMemoryPressure(); }];
        (void)warningObserver;
        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
            DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        if (source) {
            dispatch_source_set_event_handler(source, ^{ zx_tessMemoryPressure(); });
            dispatch_resume(source);
        }
    });
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

static bool zx_tessRunOCR(cv::Mat &gray,
                               NSString *lang,
                               int oem,
                               int psm,
                               NSString *whitelist,
                               int scaleUp,
                               int thresholdMode,
                               uint64_t frameAgeMs,
                               TLinkNativeFrameOCRValue &value,
                               NSError **error,
                               TLinkOCRBudgetPtr requestBudget)
{
    if (requestBudget->stopped()) return false;
    const uint64_t total0 = TLinkNativeNowNs(), prep0 = total0;

    TLinkOCRImagePlan plan;
    if (gray.empty() || gray.type() != CV_8UC1 || !TLinkOCRPlanImage(gray.cols, gray.rows, scaleUp, thresholdMode == 1 || thresholdMode == 2, plan)) {
        if (error) *error = zx_tessError(@"ocr_scaled_image_too_large", @"OCR accepts at most 4,000,000 scaled pixels; reduce ROI or scale_up.");
        return false;
    }
    cv::Mat work = gray;
    if (plan.scale > 1) cv::resize(gray, work, cv::Size(plan.width, plan.height), 0, 0, cv::INTER_CUBIC);
    else if (plan.separateWork) work = gray.clone();
    if (requestBudget->stopped()) return false;

    if (thresholdMode == 1) {
        cv::threshold(work, work, 0, 255, cv::THRESH_BINARY | cv::THRESH_OTSU);
    } else if (thresholdMode == 2) {
        int blockSize = MAX(11, ((MIN(work.cols, work.rows) / 12) | 1));
        if (blockSize % 2 == 0) blockSize++;
        cv::adaptiveThreshold(work, work, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, blockSize, 7);
    }

    if (requestBudget->stopped()) return false;
    UIImage *image = zx_tessUIImageFromGrayMat(work);
    work.release(); // UIImage owns its provider bytes; discard the scaled work buffer before engine init.
    if (requestBudget->stopped()) return false;
    double preprocessMs = (TLinkNativeNowNs() - prep0) / 1e6;
    if (!image) {
        if (error) *error = zx_tessError(@"image_convert_failed", @"Failed to convert OCR region to UIImage.");
        return false;
    }

    // Retain the complete prior engine identity, with an unambiguous encoding.
    NSData *identity = [NSJSONSerialization dataWithJSONObject:@[lang ?: @"vie", @(oem), @(psm), whitelist ?: @""] options:0 error:NULL];
    if (!identity.length) { if (error) *error = zx_tessError(@"engine_identity_failed", @"Unable to encode engine configuration."); return false; }
    std::string key((const char *)identity.bytes, identity.length);
    zx_tessObserveMemoryPressure();
    const uint64_t cacheEpoch = sZXTessEpoch.load();
    G8Tesseract *tesseract = zx_tessCache().find(key);
    if (tesseract) sZXTessHits.fetch_add(1);
    else { sZXTessMisses.fetch_add(1); zx_tessCache().prepareMiss(); sZXTessEntries.store((unsigned)zx_tessCache().size()); }
    if (!tesseract) {
        tesseract = [[G8Tesseract alloc] initWithLanguage:(lang && [lang length] > 0) ? lang : @"vie"
                                         configDictionary:nil
                                          configFileNames:nil
                                         absoluteDataPath:kZXTessdataRoot
                                               engineMode:zx_tessOEM(oem)];
        if (!tesseract || !tesseract.isEngineConfigured) {
            if (error) *error = zx_tessError(@"engine_init_failed", @"Failed to initialize Tesseract. Check tessdata files and OEM compatibility.");
            return false;
        }
        tesseract.pageSegmentationMode = zx_tessPSM(psm);
        if (whitelist && [whitelist length] > 0) {
            tesseract.charWhitelist = whitelist;
        }
        tesseract.maximumRecognitionTime = 3.0;
        // A completed cold init may warm the bounded cache even if this request has expired.
        if (sZXTessEpoch.load() == cacheEpoch) zx_tessCache().insert(key, tesseract);
        sZXTessEntries.store((unsigned)zx_tessCache().size());
    }

    const uint64_t ocr0 = TLinkNativeNowNs();
    if (requestBudget->stopped()) return false;
    __attribute__((objc_precise_lifetime)) ZXTessBudgetDelegate *delegate = [[ZXTessBudgetDelegate alloc] initWithBudget:requestBudget];
    tesseract.delegate = delegate;

    BOOL recognized = false;
    @try {
        tesseract.image = image;
        tesseract.rect = CGRectMake(0, 0, image.size.width, image.size.height);
        if (requestBudget->stopped()) return false;
        tesseract.maximumRecognitionTime = requestBudget->remainingSeconds();
        if (tesseract.maximumRecognitionTime <= 0) return false;
        // The wrapper converts seconds to integer milliseconds; avoid a positive remainder becoming zero/unlimited.
        if (tesseract.maximumRecognitionTime < 0.001) tesseract.maximumRecognitionTime = 0.001;
        recognized = [tesseract recognize];
        if (requestBudget->stopped()) return false;
        double ocrMs = (TLinkNativeNowNs() - ocr0) / 1e6;
        if (!recognized) {
            if (error) *error = zx_tessError(@"recognize_failed", @"Tesseract recognition failed.");
            return false;
        }

        NSString *text = [tesseract.recognizedText ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!TLinkNativeOutputAllowed(256 + 4 * (([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 2) / 3))) return false;
        double confidence = zx_tessMeanConfidence(tesseract);
        double totalMs = (TLinkNativeNowNs() - total0) / 1e6;
        value=TLinkFormatFrameOCRValue(text,confidence,frameAgeMs,ocrMs,preprocessMs,totalMs);
        return true;
    } @finally { tesseract.delegate = nil; tesseract.image = nil; }
}
static bool zx_tessRecognizeFrame(const TLinkNativeFrameOCRRequest &request,TLinkNativeFrameOCRValue &value,NSError **error,TLinkOCRBudgetPtr requestBudget){
    const uint32_t frameId=request.frameId;const int x=request.x,y=request.y,w=request.width,h=request.height;
    NSString *lang=request.lang.length?request.lang:@"vie",*whitelist=request.whitelist?:@"",*coord=request.coord.length?request.coord:@"pixel";
    const int oem=request.oem,psm=request.psm,scaleUp=request.scaleUp,thresholdMode=request.thresholdMode;const uint64_t maxAgeMs=request.maxAgeMs?request.maxAgeMs:1000;
    __block TLinkNativeFrameOCRValue completed;
    __block bool ready=false;
    __block NSError *blockErr = nil;
    const uint64_t queuedEpoch = sZXTessEpoch.load();
    TLinkNativeDispatchSync(zx_tessQueue(), ^{
        @autoreleasepool {
            try {
                @try {
                    if (queuedEpoch != sZXTessEpoch.load()) zx_tessPurgeCache();
                    if (requestBudget->stopped()) return;
                    cv::Mat gray;
                    uint64_t frameAgeMs = 0;
                    if (!zx_copyFrameGrayRegionForOCR(frameId, x, y, w, h, coord, maxAgeMs, gray, &frameAgeMs, &blockErr, scaleUp)) return;
                    ready = zx_tessRunOCR(gray, lang, oem, psm, whitelist, scaleUp, thresholdMode, frameAgeMs, completed, &blockErr, requestBudget);
                } @catch (NSException *exception) {
                    blockErr = zx_tessError(@"ocr_exception", exception.reason ?: @"OCR failed.");
                    zx_tessPurgeCache();
                } @finally {
                    // A warning may arrive while this owner is in an opaque engine operation.
                    if (queuedEpoch != sZXTessEpoch.load()) zx_tessPurgeCache();
                }
            } catch (const std::exception &exception) {
                blockErr = zx_tessError(@"ocr_exception", [NSString stringWithUTF8String:exception.what()] ?: @"OCR failed.");
                zx_tessPurgeCache();
            }
        }
    });
    if (requestBudget->stopped()) {
        if (error) *error = zx_tessError(@"ocr_cancelled_or_timed_out", @"OCR request cancelled or its 3-second cooperative budget expired.");
        return false;
    }

    if (blockErr) {
        if (error) *error = blockErr;
        return false;
    }
    if(ready)value=std::move(completed);
    return ready;
}
#endif

NSString *handleTesseractOCRTaskFromRawData(UInt8 *eventData, NSError **error)
{

#if ENABLE_TESSERACT_OCR
    const uint64_t enteredAt = TLinkNativeNowNs();
#endif
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([[raw lowercaseString] isEqualToString:@"check_langs"]) {
        return zx_tessCheckLangs();
    }

#if !ENABLE_TESSERACT_OCR
    if (error) *error = zx_tessError(@"disabled", @"Tesseract OCR is not enabled in this build.");
    return nil;
#else
    TLinkOCRAdmission admission(sZXTessActive);
    if (!admission) { sZXTessBusy.fetch_add(1); if (error) *error = zx_tessError(@"ocr_busy", @"Only two OCR requests may be active or queued."); return nil; }
    auto requestBudget = std::make_shared<TLinkOCRRequestBudget>(TLinkCurrentNativeBudget(), enteredAt);
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

    TLinkNativeFrameOCRRequest request;request.frameId=frameId;request.x=x;request.y=y;request.width=w;request.height=h;
    request.lang=lang;request.oem=oem;request.psm=psm;request.whitelist=whitelist;request.scaleUp=scaleUp;request.thresholdMode=thresholdMode;request.coord=coord;request.maxAgeMs=maxAgeMs;
    TLinkNativeFrameOCRValue value;
    return zx_tessRecognizeFrame(request,value,error,requestBudget)?value.body:nil;
#endif
}

bool recognizeFrameWithTesseract(const TLinkNativeFrameOCRRequest &request,TLinkNativeFrameOCRValue &value,NSError **error){
    value=TLinkNativeFrameOCRValue();
#if !ENABLE_TESSERACT_OCR
    (void)request;if(error)*error=zx_tessError(@"disabled",@"Tesseract OCR is not enabled in this build.");return false;
#else
    const uint64_t enteredAt=TLinkNativeNowNs();
    TLinkOCRAdmission admission(sZXTessActive);
    if(!admission){sZXTessBusy.fetch_add(1);if(error)*error=zx_tessError(@"ocr_busy",@"Only two OCR requests may be active or queued.");return false;}
    auto requestBudget=std::make_shared<TLinkOCRRequestBudget>(TLinkCurrentNativeBudget(),enteredAt);
    return zx_tessRecognizeFrame(request,value,error,requestBudget);
#endif
}
