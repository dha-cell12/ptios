#import "Image.h"
#import "Image.h"
#import "Screen.h"
#import "Common.h"
#import "ScriptPlayer.h"

#include <dispatch/dispatch.h>
#include <unordered_map>
#include <climits>
#include <math.h>
#include <vector>
#include <stdint.h>

// From Play.xm
extern ScriptPlayer *scriptPlayer;

using namespace cv;
using namespace std;

typedef struct {
    cv::Mat gray;
    int w;
    int h;
} ZXImageObject;

typedef struct {
    uint32_t frameId;
    int width;
    int height;
    int bytesPerRow;
    double scale;
    uint64_t createdAtMs;
    uint64_t expiresAtMs;
    bool hasBGRA;
    bool hasGray;
    std::vector<uint8_t> bgra;
    cv::Mat gray;
} ZXFrameObject;

typedef struct {
    int dx;
    int dy;
    int r;
    int g;
    int b;
} ZXPointColor;

static dispatch_queue_t zx_imageQueue(void)
{
    static dispatch_queue_t q;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.zjx.zxtouch.imageStore", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static unordered_map<uint32_t, ZXImageObject> gImageStore;
static uint32_t gNextImageId = 1;
static const size_t kMaxImageObjects = 64;

static unordered_map<uint32_t, ZXFrameObject> gFrameStore;
static uint32_t gNextFrameId = 1;
static const size_t kMaxFrameObjects = 3;
static const uint64_t kDefaultFrameTtlMs = 1000;
static const uint64_t kHardFrameTtlMs = 5000;

static uint64_t zx_nowMs(void)
{
    return (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000.0);
}

static NSError *zx_frameError(NSString *message)
{
    return [NSError errorWithDomain:@"com.zjx.zxtouchsp"
                               code:999
                           userInfo:@{NSLocalizedDescriptionKey:message ?: @"1;;frame_error\r\n"}];
}

static NSString *zx_currentScriptDir(void)
{
    if (scriptPlayer) {
        NSString *p = [scriptPlayer getCurrentBundlePath];
        if (p && [p length] > 0) {
            return p;
        }
    }
    return nil;
}

static NSString *zx_resolveImagePath(NSString *path)
{
    if (!path) return nil;
    if ([path hasPrefix:@"/"]) {
        return path;
    }
    NSString *bundle = zx_currentScriptDir();
    if (bundle && [bundle length] > 0) {
        return [bundle stringByAppendingPathComponent:path];
    }
    return [getScriptsFolder() stringByAppendingPathComponent:path];
}

static cv::Mat zx_cvMatGrayFromCGImage(CGImageRef img, NSError **error)
{
    if (!img) {
        return cv::Mat();
    }
    const size_t cols = CGImageGetWidth(img);
    const size_t rows = CGImageGetHeight(img);
    if (cols == 0 || rows == 0 || cols > 20000 || rows > 20000) {
        return cv::Mat();
    }

    cv::Mat rgba((int)rows, (int)cols, CV_8UC4);
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(img);
    BOOL createdColorSpace = false;
    if (!colorSpace) {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        createdColorSpace = true;
    }
    CGContextRef ctx = CGBitmapContextCreate(rgba.data,
                                             cols,
                                             rows,
                                             8,
                                             rgba.step[0],
                                             colorSpace,
                                             kCGImageAlphaNoneSkipLast | kCGBitmapByteOrderDefault);
    if (createdColorSpace) {
        CGColorSpaceRelease(colorSpace);
    }
    if (!ctx) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to create bitmap context.\r\n"}];
        }
        return cv::Mat();
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, cols, rows), img);
    CGContextRelease(ctx);

    cv::Mat gray;
    cv::cvtColor(rgba, gray, COLOR_RGBA2GRAY);
    return gray;
}

static long long zx_sad_match_region(const Mat &img, const Mat &templ,
                                    int x0, int y0, int x1, int y1,
                                    int step, int *bestX, int *bestY)
{
    const int w = templ.cols;
    const int h = templ.rows;

    long long bestSad = LLONG_MAX;
    int bx = 0;
    int by = 0;

    if (step <= 0) step = 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    const int maxX = img.cols - w;
    const int maxY = img.rows - h;
    if (x1 > maxX) x1 = maxX;
    if (y1 > maxY) y1 = maxY;
    if (x0 > x1 || y0 > y1) {
        if (bestX) *bestX = 0;
        if (bestY) *bestY = 0;
        return bestSad;
    }

    for (int y = y0; y <= y1; y += step) {
        for (int x = x0; x <= x1; x += step) {
            long long sad = 0;
            for (int ty = 0; ty < h; ty++) {
                const unsigned char *imgRow = img.ptr<unsigned char>(y + ty) + x;
                const unsigned char *tRow = templ.ptr<unsigned char>(ty);
                for (int tx = 0; tx < w; tx++) {
                    sad += (long long)abs((int)imgRow[tx] - (int)tRow[tx]);
                }
                if (sad >= bestSad) {
                    break;
                }
            }
            if (sad < bestSad) {
                bestSad = sad;
                bx = x;
                by = y;
            }
        }
    }

    if (bestX) *bestX = bx;
    if (bestY) *bestY = by;
    return bestSad;
}

static BOOL zx_findTemplateSAD(const Mat &img, const Mat &templ,
                              double acceptable,
                              float scaleMin, float scaleMax, float scaleStep,
                              int pixelSkip,
                              int *outX, int *outY, int *outW, int *outH,
                              double *outScore)
{
    if (outX) *outX = -1;
    if (outY) *outY = -1;
    if (outW) *outW = 0;
    if (outH) *outH = 0;
    if (outScore) *outScore = 0;

    if (img.empty() || templ.empty()) {
        return false;
    }

    float r = 1.0f;
    long long pixels = (long long)img.cols * (long long)img.rows;
    if (pixels > 600000) {
        r = 0.5f;
    }

    Mat imgWork = img;
    if (r != 1.0f) {
        cv::resize(img, imgWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
    }

    int coarseStep = pixelSkip + 1;
    if (coarseStep < 4) coarseStep = 4;

    double bestOverallScore = -1.0;
    int bestX = -1, bestY = -1, bestW = 0, bestH = 0;

    if (scaleStep <= 0.0f) {
        scaleStep = 0.1f;
    }
    if (scaleMax < scaleMin) {
        float tmp = scaleMax;
        scaleMax = scaleMin;
        scaleMin = tmp;
    }

    for (float s = scaleMax; s >= scaleMin - 0.0001f; s -= scaleStep) {
        Mat templScaled;
        if (fabsf(s - 1.0f) < 0.0001f) {
            templScaled = templ;
        } else {
            int interp = s < 1.0f ? cv::INTER_AREA : cv::INTER_LINEAR;
            cv::resize(templ, templScaled, cv::Size(0, 0), s, s, interp);
        }
        if (templScaled.empty()) {
            continue;
        }
        Mat templWork = templScaled;
        if (r != 1.0f) {
            cv::resize(templScaled, templWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
        }

        if (templWork.cols <= 0 || templWork.rows <= 0 ||
            templWork.cols > imgWork.cols || templWork.rows > imgWork.rows) {
            continue;
        }

        int bx = 0, by = 0;
        long long bestSad = zx_sad_match_region(imgWork, templWork,
                                               0, 0,
                                               imgWork.cols - templWork.cols,
                                               imgWork.rows - templWork.rows,
                                               coarseStep,
                                               &bx, &by);

        int refineRadius = coarseStep * 2;
        int rbx = bx, rby = by;
        long long refinedSad = zx_sad_match_region(imgWork, templWork,
                                                   bx - refineRadius, by - refineRadius,
                                                   bx + refineRadius, by + refineRadius,
                                                   1,
                                                   &rbx, &rby);
        if (refinedSad < bestSad) {
            bestSad = refinedSad;
            bx = rbx;
            by = rby;
        }

        const long long denom = 255LL * (long long)templWork.cols * (long long)templWork.rows;
        double score = (denom > 0) ? (1.0 - ((double)bestSad / (double)denom)) : 0.0;
        if (score > bestOverallScore) {
            bestOverallScore = score;
            bestX = bx;
            bestY = by;
            bestW = templWork.cols;
            bestH = templWork.rows;
        }

        if (score >= acceptable) {
            const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
            if (outX) *outX = (int)round(bx * inv);
            if (outY) *outY = (int)round(by * inv);
            if (outW) *outW = (int)round(templWork.cols * inv);
            if (outH) *outH = (int)round(templWork.rows * inv);
            if (outScore) *outScore = score;
            return true;
        }
    }

    if (bestX >= 0 && bestY >= 0 && bestW > 0 && bestH > 0) {
        const double inv = (r == 0.0f) ? 1.0 : (1.0 / (double)r);
        if (outX) *outX = (int)round(bestX * inv);
        if (outY) *outY = (int)round(bestY * inv);
        if (outW) *outW = (int)round(bestW * inv);
        if (outH) *outH = (int)round(bestH * inv);
    }
    if (outScore) *outScore = (bestOverallScore < 0.0) ? 0.0 : bestOverallScore;
    return false;
}

NSString* handleFrameCaptureTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray<NSString *> *data = zx_splitEventData(eventData);
    bool needGray = true;
    bool needBGRA = true;
    uint64_t ttlMs = kDefaultFrameTtlMs;
    if ([data count] >= 1 && [data[0] length] > 0) needGray = [data[0] intValue] != 0;
    if ([data count] >= 2 && [data[1] length] > 0) needBGRA = [data[1] intValue] != 0;
    if ([data count] >= 3 && [data[2] length] > 0) ttlMs = (uint64_t)MAX(0, [data[2] longLongValue]);
    if (!needGray && !needBGRA) {
        needGray = true;
        needBGRA = true;
    }
    if (ttlMs == 0) ttlMs = kDefaultFrameTtlMs;
    if (ttlMs > kHardFrameTtlMs) ttlMs = kHardFrameTtlMs;

    CFAbsoluteTime total0 = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime capture0 = CFAbsoluteTimeGetCurrent();
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    double captureMs = (CFAbsoluteTimeGetCurrent() - capture0) * 1000.0;
    if (!screen) {
        if (error) *error = zx_frameError(@"1;;capture_failed\r\n");
        return nil;
    }

    ZXFrameObject frame;
    frame.width = (int)CGImageGetWidth(screen);
    frame.height = (int)CGImageGetHeight(screen);
    frame.bytesPerRow = frame.width * 4;
    frame.scale = [Screen getScale];
    frame.createdAtMs = zx_nowMs();
    frame.expiresAtMs = frame.createdAtMs + ttlMs;
    frame.hasBGRA = false;
    frame.hasGray = false;

    std::vector<uint8_t> tmpBGRA;
    int w = 0, h = 0, bpr = 0;
    CFAbsoluteTime bgra0 = CFAbsoluteTimeGetCurrent();
    if (!zx_renderBGRAFromCGImage(screen, needBGRA ? frame.bgra : tmpBGRA, &w, &h, &bpr)) {
        CGImageRelease(screen);
        if (error) *error = zx_frameError(@"1;;bgra_render_failed\r\n");
        return nil;
    }
    double bgraMs = (CFAbsoluteTimeGetCurrent() - bgra0) * 1000.0;
    CGImageRelease(screen);
    frame.width = w;
    frame.height = h;
    frame.bytesPerRow = bpr;
    frame.hasBGRA = needBGRA;

    CFAbsoluteTime gray0 = CFAbsoluteTimeGetCurrent();
    if (needGray) {
        std::vector<uint8_t> &source = needBGRA ? frame.bgra : tmpBGRA;
        cv::Mat bgraMat(frame.height, frame.width, CV_8UC4, source.data(), frame.bytesPerRow);
        cv::cvtColor(bgraMat, frame.gray, COLOR_BGRA2GRAY);
        frame.hasGray = !frame.gray.empty();
    }
    double grayMs = (CFAbsoluteTimeGetCurrent() - gray0) * 1000.0;
    if (needGray && !frame.hasGray) {
        if (error) *error = zx_frameError(@"1;;gray_convert_failed\r\n");
        return nil;
    }

    __block uint32_t frameId = 0;
    dispatch_sync(zx_imageQueue(), ^{
        frameId = zx_storeFrameLocked(frame);
    });
    double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
    return [NSString stringWithFormat:@"%u;;%d;;%d;;%d;;%.3f;;pixel;;BGRA;;%d;;%d;;%llu;;%.3f;;%.3f;;%.3f;;%.3f",
            frameId, frame.width, frame.height, frame.bytesPerRow, frame.scale,
            frame.hasBGRA ? 1 : 0, frame.hasGray ? 1 : 0,
            (unsigned long long)frame.createdAtMs,
            captureMs, bgraMs, grayMs, totalMs];
}

NSString* handleFrameReleaseTaskFromRawData(UInt8 *eventData, NSError **error)
{
    (void)error;
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData] ?: @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    __block NSUInteger removed = 0;
    dispatch_sync(zx_imageQueue(), ^{
        if ([[raw lowercaseString] isEqualToString:@"all"]) {
            removed = gFrameStore.size();
            gFrameStore.clear();
        } else {
            uint32_t frameId = (uint32_t)[raw intValue];
            removed = gFrameStore.erase(frameId);
        }
    });
    return [NSString stringWithFormat:@"%lu", (unsigned long)removed];
}

NSString* handleFindImageInFrameTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray<NSString *> *data = zx_splitEventData(eventData);
    if ([data count] < 11) {
        if (error) *error = zx_frameError(@"1;;Find image in frame format should be frame_id;;image_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip[;;coord;;max_age_ms]\r\n");
        return nil;
    }
    uint32_t frameId = (uint32_t)[data[0] intValue];
    uint32_t imageId = (uint32_t)[data[1] intValue];
    int rx = [data[2] intValue];
    int ry = [data[3] intValue];
    int rw = [data[4] intValue];
    int rh = [data[5] intValue];
    double acceptable = [data[6] doubleValue];
    float scaleMin = [data[7] floatValue];
    float scaleMax = [data[8] floatValue];
    float scaleStep = [data[9] floatValue];
    int pixelSkip = [data[10] intValue];
    bool pointCoord = ([data count] >= 12) ? zx_stringIsPointCoord(data[11]) : false;
    uint64_t maxAgeMs = ([data count] >= 13) ? (uint64_t)MAX(0, [data[12] longLongValue]) : kDefaultFrameTtlMs;

    __block NSString *ret = nil;
    __block NSError *blockErr = nil;
    dispatch_sync(zx_imageQueue(), ^{
        uint64_t nowMs = zx_nowMs();
        zx_cleanupFramesLocked(nowMs);
        auto fit = gFrameStore.find(frameId);
        if (fit == gFrameStore.end()) {
            blockErr = zx_frameError(@"1;;frame_not_found\r\n");
            return;
        }
        ZXFrameObject &frame = fit->second;
        if (!frame.hasGray || frame.gray.empty()) {
            blockErr = zx_frameError(@"1;;frame_missing_gray\r\n");
            return;
        }
        if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
        auto iit = gImageStore.find(imageId);
        if (iit == gImageStore.end() || iit->second.gray.empty()) {
            blockErr = zx_frameError(@"1;;image_not_found\r\n");
            return;
        }
        uint64_t ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
        rx = zx_coordToPixel(rx, frame.scale, pointCoord);
        ry = zx_coordToPixel(ry, frame.scale, pointCoord);
        rw = zx_coordToPixel(rw, frame.scale, pointCoord);
        rh = zx_coordToPixel(rh, frame.scale, pointCoord);
        if (rx < 0) rx = 0;
        if (ry < 0) ry = 0;
        if (rx >= frame.width) rx = frame.width - 1;
        if (ry >= frame.height) ry = frame.height - 1;
        if (rw <= 0 || rx + rw > frame.width) rw = frame.width - rx;
        if (rh <= 0 || ry + rh > frame.height) rh = frame.height - ry;

        CFAbsoluteTime total0 = CFAbsoluteTimeGetCurrent();
        cv::Rect roi(rx, ry, rw, rh);
        cv::Mat region = frame.gray(roi);
        int mx = -1, my = -1, mw = 0, mh = 0;
        double score = 0.0;
        bool match = zx_findTemplateSAD(region, iit->second.gray, acceptable, scaleMin, scaleMax, scaleStep, pixelSkip,
                                        &mx, &my, &mw, &mh, &score);
        double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
        if (!match) {
            ret = [NSString stringWithFormat:@"-1;;-1;;0;;0;;-1;;-1;;%.4f;;%llu;;%.3f;;%.3f", score, (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }
        int absX = rx + mx;
        int absY = ry + my;
        double cx = absX + mw / 2.0;
        double cy = absY + mh / 2.0;
        ret = [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f;;%llu;;%.3f;;%.3f",
               absX, absY, mw, mh, cx, cy, score, (unsigned long long)ageMs, totalMs, totalMs];
    });
    if (blockErr) {
        if (error) *error = blockErr;
        return nil;
    }
    return ret;
}

NSString* handleColorInFrameTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray<NSString *> *data = zx_splitEventData(eventData);
    if ([data count] < 2) {
        if (error) *error = zx_frameError(@"1;;Color in frame format should be frame_id;;mode;;...\r\n");
        return nil;
    }
    uint32_t frameId = (uint32_t)[data[0] intValue];
    NSString *mode = [[data[1] lowercaseString] copy];

    __block NSString *ret = nil;
    __block NSError *blockErr = nil;
    dispatch_sync(zx_imageQueue(), ^{
        uint64_t nowMs = zx_nowMs();
        zx_cleanupFramesLocked(nowMs);
        auto fit = gFrameStore.find(frameId);
        if (fit == gFrameStore.end()) {
            blockErr = zx_frameError(@"1;;frame_not_found\r\n");
            return;
        }
        ZXFrameObject &frame = fit->second;
        if (!frame.hasBGRA || frame.bgra.empty()) {
            blockErr = zx_frameError(@"1;;frame_missing_bgra\r\n");
            return;
        }
        uint64_t ageMs = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
        CFAbsoluteTime total0 = CFAbsoluteTimeGetCurrent();

        if ([mode isEqualToString:@"pick"]) {
            if ([data count] < 4) { blockErr = zx_frameError(@"1;;pick format should be frame_id;;pick;;x;;y[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 5) ? zx_stringIsPointCoord(data[4]) : false;
            uint64_t maxAgeMs = ([data count] >= 6) ? (uint64_t)MAX(0, [data[5] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            int x = zx_coordToPixel([data[2] doubleValue], frame.scale, pointCoord);
            int y = zx_coordToPixel([data[3] doubleValue], frame.scale, pointCoord);
            if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) { blockErr = zx_frameError(@"1;;point_out_of_bounds\r\n"); return; }
            int r = 0, g = 0, b = 0;
            zx_readBGRA(frame, x, y, &r, &g, &b);
            double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"%d;;%d;;%d;;%llu;;%.3f;;%.3f", r, g, b, (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"search_single"]) {
            if ([data count] < 13) { blockErr = zx_frameError(@"1;;search_single format should be frame_id;;search_single;;x;;y;;w;;h;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 14) ? zx_stringIsPointCoord(data[13]) : false;
            uint64_t maxAgeMs = ([data count] >= 15) ? (uint64_t)MAX(0, [data[14] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            int x = zx_coordToPixel([data[2] doubleValue], frame.scale, pointCoord);
            int y = zx_coordToPixel([data[3] doubleValue], frame.scale, pointCoord);
            int w = zx_coordToPixel([data[4] doubleValue], frame.scale, pointCoord);
            int h = zx_coordToPixel([data[5] doubleValue], frame.scale, pointCoord);
            int rmin = [data[6] intValue], rmax = [data[7] intValue];
            int gmin = [data[8] intValue], gmax = [data[9] intValue];
            int bmin = [data[10] intValue], bmax = [data[11] intValue];
            int step = [data[12] intValue] + 1;
            if (step <= 0) step = 1;
            if (x < 0) x = 0; if (y < 0) y = 0;
            if (x >= frame.width) x = frame.width - 1; if (y >= frame.height) y = frame.height - 1;
            if (w <= 0 || x + w > frame.width) w = frame.width - x;
            if (h <= 0 || y + h > frame.height) h = frame.height - y;
            for (int cy = 0; cy < h; cy += step) {
                const uint8_t *row = frame.bgra.data() + (size_t)(y + cy) * (size_t)frame.bytesPerRow;
                for (int cx = 0; cx < w; cx += step) {
                    const uint8_t *p = row + (size_t)(x + cx) * 4;
                    int b = p[0], g = p[1], r = p[2];
                    if (r >= rmin && r <= rmax && g >= gmin && g <= gmax && b >= bmin && b <= bmax) {
                        double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
                        ret = [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f", x + cx, y + cy, r, g, b, (unsigned long long)ageMs, totalMs, totalMs];
                        return;
                    }
                }
            }
            double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"-1;;-1;;-1;;-1;;-1;;%llu;;%.3f;;%.3f", (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"is_colors"]) {
            if ([data count] < 5) { blockErr = zx_frameError(@"1;;is_colors format should be frame_id;;is_colors;;table;;mode;;value[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 6) ? zx_stringIsPointCoord(data[5]) : false;
            uint64_t maxAgeMs = ([data count] >= 7) ? (uint64_t)MAX(0, [data[6] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            std::vector<ZXPointColor> points;
            if (!zx_parsePointTableVector(data[2], points, &blockErr)) return;
            int colorMode = [data[3] intValue];
            double value = [data[4] doubleValue];
            bool matched = true;
            for (const ZXPointColor &pc : points) {
                int x = zx_coordToPixel(pc.dx, frame.scale, pointCoord);
                int y = zx_coordToPixel(pc.dy, frame.scale, pointCoord);
                if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) { matched = false; break; }
                int r = 0, g = 0, b = 0;
                zx_readBGRA(frame, x, y, &r, &g, &b);
                if (!zx_bgraColorMatch(r, g, b, pc.r, pc.g, pc.b, colorMode, value)) { matched = false; break; }
            }
            double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"%d;;%llu;;%.3f;;%.3f", matched ? 1 : 0, (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        if ([mode isEqualToString:@"find_multi_point"]) {
            if ([data count] < 10) { blockErr = zx_frameError(@"1;;find_multi_point format should be frame_id;;find_multi_point;;x;;y;;w;;h;;table;;mode;;value;;skip[;;coord;;max_age_ms]\r\n"); return; }
            bool pointCoord = ([data count] >= 11) ? zx_stringIsPointCoord(data[10]) : false;
            uint64_t maxAgeMs = ([data count] >= 12) ? (uint64_t)MAX(0, [data[11] longLongValue]) : kDefaultFrameTtlMs;
            if (zx_frameTooOld(frame, maxAgeMs, nowMs, &blockErr)) return;
            int regionX = zx_coordToPixel([data[2] doubleValue], frame.scale, pointCoord);
            int regionY = zx_coordToPixel([data[3] doubleValue], frame.scale, pointCoord);
            int regionW = zx_coordToPixel([data[4] doubleValue], frame.scale, pointCoord);
            int regionH = zx_coordToPixel([data[5] doubleValue], frame.scale, pointCoord);
            std::vector<ZXPointColor> points;
            if (!zx_parsePointTableVector(data[6], points, &blockErr)) return;
            int colorMode = [data[7] intValue];
            double value = [data[8] doubleValue];
            int step = [data[9] intValue] + 1;
            if (step <= 0) step = 1;
            if (regionX < 0) regionX = 0; if (regionY < 0) regionY = 0;
            if (regionX >= frame.width) regionX = frame.width - 1; if (regionY >= frame.height) regionY = frame.height - 1;
            if (regionW <= 0 || regionX + regionW > frame.width) regionW = frame.width - regionX;
            if (regionH <= 0 || regionY + regionH > frame.height) regionH = frame.height - regionY;
            int minDx = INT_MAX, minDy = INT_MAX, maxDx = INT_MIN, maxDy = INT_MIN;
            for (const ZXPointColor &pc : points) { if (pc.dx < minDx) minDx = pc.dx; if (pc.dy < minDy) minDy = pc.dy; if (pc.dx > maxDx) maxDx = pc.dx; if (pc.dy > maxDy) maxDy = pc.dy; }
            int axStart = MAX(regionX, -minDx);
            int ayStart = MAX(regionY, -minDy);
            int axEnd = MIN(regionX + regionW - 1, frame.width - 1 - maxDx);
            int ayEnd = MIN(regionY + regionH - 1, frame.height - 1 - maxDy);
            if (axStart <= axEnd && ayStart <= ayEnd) {
                for (int ay = ayStart; ay <= ayEnd; ay += step) {
                    for (int ax = axStart; ax <= axEnd; ax += step) {
                        bool ok = true;
                        for (const ZXPointColor &pc : points) {
                            int r = 0, g = 0, b = 0;
                            zx_readBGRA(frame, ax + pc.dx, ay + pc.dy, &r, &g, &b);
                            if (!zx_bgraColorMatch(r, g, b, pc.r, pc.g, pc.b, colorMode, value)) { ok = false; break; }
                        }
                        if (ok) {
                            double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
                            ret = [NSString stringWithFormat:@"%d;;%d;;%llu;;%.3f;;%.3f", ax, ay, (unsigned long long)ageMs, totalMs, totalMs];
                            return;
                        }
                    }
                }
            }
            double totalMs = (CFAbsoluteTimeGetCurrent() - total0) * 1000.0;
            ret = [NSString stringWithFormat:@"-1;;-1;;%llu;;%.3f;;%.3f", (unsigned long long)ageMs, totalMs, totalMs];
            return;
        }

        blockErr = zx_frameError(@"1;;unknown_color_frame_mode\r\n");
    });
    if (blockErr) {
        if (error) *error = blockErr;
        return nil;
    }
    return ret;
}

@implementation Image
@end

static uint32_t zx_storeImageLocked(const cv::Mat &gray)
{
    if (gImageStore.size() >= kMaxImageObjects) {
        return 0;
    }
    uint32_t imageId = gNextImageId++;
    ZXImageObject obj;
    obj.gray = gray;
    obj.w = gray.cols;
    obj.h = gray.rows;
    gImageStore[imageId] = obj;
    return imageId;
}

static void zx_cleanupFramesLocked(uint64_t nowMs)
{
    std::vector<uint32_t> removeIds;
    for (auto const &kv : gFrameStore) {
        const ZXFrameObject &f = kv.second;
        if (nowMs >= f.expiresAtMs || nowMs - f.createdAtMs > kHardFrameTtlMs) {
            removeIds.push_back(kv.first);
        }
    }
    for (uint32_t fid : removeIds) {
        gFrameStore.erase(fid);
    }
}

static void zx_trimFramesLocked(void)
{
    while (gFrameStore.size() >= kMaxFrameObjects) {
        uint32_t oldestId = 0;
        uint64_t oldestMs = UINT64_MAX;
        for (auto const &kv : gFrameStore) {
            if (kv.second.createdAtMs < oldestMs) {
                oldestMs = kv.second.createdAtMs;
                oldestId = kv.first;
            }
        }
        if (oldestId == 0) break;
        gFrameStore.erase(oldestId);
    }
}

static uint32_t zx_storeFrameLocked(ZXFrameObject &frame)
{
    uint64_t nowMs = zx_nowMs();
    zx_cleanupFramesLocked(nowMs);
    zx_trimFramesLocked();
    uint32_t frameId = gNextFrameId++;
    if (frameId == 0) frameId = gNextFrameId++;
    frame.frameId = frameId;
    gFrameStore[frameId] = frame;
    return frameId;
}

static NSArray<NSString *> *zx_splitEventData(UInt8 *eventData)
{
    NSString *raw = [[NSString alloc] initWithUTF8String:(char *)eventData];
    if (!raw) return @[];
    return [raw componentsSeparatedByString:@";;"];
}

static bool zx_stringIsPointCoord(NSString *coord)
{
    return coord && [[coord lowercaseString] isEqualToString:@"point"];
}

static int zx_coordToPixel(double value, double scale, bool pointCoord)
{
    double v = pointCoord ? value * scale : value;
    if (v < 0.0) v = 0.0;
    return (int)llround(v);
}

static bool zx_frameTooOld(const ZXFrameObject &frame, uint64_t maxAgeMs, uint64_t nowMs, NSError **error)
{
    uint64_t age = nowMs >= frame.createdAtMs ? nowMs - frame.createdAtMs : 0;
    if (maxAgeMs == 0) maxAgeMs = kDefaultFrameTtlMs;
    if (age > maxAgeMs) {
        if (error) {
            *error = zx_frameError([NSString stringWithFormat:@"1;;frame_expired;;%llu\r\n", (unsigned long long)age]);
        }
        return true;
    }
    return false;
}

static bool zx_renderBGRAFromCGImage(CGImageRef img, std::vector<uint8_t> &out, int *outW, int *outH, int *outBpr)
{
    if (!img) return false;
    int width = (int)CGImageGetWidth(img);
    int height = (int)CGImageGetHeight(img);
    if (width <= 0 || height <= 0) return false;
    int bytesPerRow = width * 4;
    out.assign((size_t)bytesPerRow * (size_t)height, 0);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(out.data(),
                                             width,
                                             height,
                                             8,
                                             bytesPerRow,
                                             colorSpace,
                                             kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) {
        out.clear();
        return false;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), img);
    CGContextRelease(ctx);
    if (outW) *outW = width;
    if (outH) *outH = height;
    if (outBpr) *outBpr = bytesPerRow;
    return true;
}

static inline bool zx_bgraColorMatch(int r, int g, int b, int tr, int tg, int tb, int mode, double value)
{
    int dr = abs(r - tr);
    int dg = abs(g - tg);
    int db = abs(b - tb);
    if (mode == 1) {
        int dev = (int)value;
        return dr <= dev && dg <= dev && db <= dev;
    }
    double sim = 1.0 - ((double)dr + (double)dg + (double)db) / (3.0 * 255.0);
    return sim >= value;
}

static bool zx_parsePointTableVector(NSString *tableStr, std::vector<ZXPointColor> &points, NSError **error)
{
    if (!tableStr || [tableStr length] == 0) {
        if (error) *error = zx_frameError(@"1;;point_table_empty\r\n");
        return false;
    }
    NSArray<NSString *> *items = [tableStr componentsSeparatedByString:@"|"];
    for (NSString *item in items) {
        if (!item || [item length] == 0) continue;
        NSArray<NSString *> *parts = [item componentsSeparatedByString:@",,"];
        if ([parts count] != 5) {
            if (error) *error = zx_frameError(@"1;;invalid_point_table\r\n");
            return false;
        }
        ZXPointColor pc;
        pc.dx = [parts[0] intValue];
        pc.dy = [parts[1] intValue];
        pc.r = [parts[2] intValue];
        pc.g = [parts[3] intValue];
        pc.b = [parts[4] intValue];
        points.push_back(pc);
    }
    if (points.empty()) {
        if (error) *error = zx_frameError(@"1;;point_table_empty\r\n");
        return false;
    }
    return true;
}

static inline void zx_readBGRA(const ZXFrameObject &frame, int x, int y, int *r, int *g, int *b)
{
    const uint8_t *p = frame.bgra.data() + ((size_t)y * (size_t)frame.bytesPerRow) + ((size_t)x * 4);
    if (b) *b = p[0];
    if (g) *g = p[1];
    if (r) *r = p[2];
}

NSString* handleImageObjectTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image task missing action.\r\n"}];
        }
        return nil;
    }
    int action = [data[0] intValue];
    if (action == 1) {
        if ([data count] < 5) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image capture format should be action;;x;;y;;w;;h\r\n"}];
            }
            return nil;
        }
        int x = [data[1] intValue];
        int y = [data[2] intValue];
        int w = [data[3] intValue];
        int h = [data[4] intValue];

        CGImageRef screen = [Screen createScreenShotCGImageRef];
        if (!screen) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
            }
            return nil;
        }
        int sw = (int)CGImageGetWidth(screen);
        int sh = (int)CGImageGetHeight(screen);
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x >= sw) x = sw - 1;
        if (y >= sh) y = sh - 1;
        if (w <= 0 || x + w > sw) w = sw - x;
        if (h <= 0 || y + h > sh) h = sh - y;

        CGRect cropRect = CGRectMake(x, y, w, h);
        CGImageRef cropped = CGImageCreateWithImageInRect(screen, cropRect);
        CGImageRelease(screen);
        if (!cropped) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
            }
            return nil;
        }
        NSError *convErr = nil;
        Mat gray = zx_cvMatGrayFromCGImage(cropped, &convErr);
        CGImageRelease(cropped);
        if (gray.empty()) {
            if (error) {
                *error = convErr ?: [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to convert screenshot to mat.\r\n"}];
            }
            return nil;
        }

        __block uint32_t imageId = 0;
        dispatch_sync(zx_imageQueue(), ^{
            imageId = zx_storeImageLocked(gray);
        });
        if (imageId == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
            }
            return nil;
        }
        return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, gray.cols, gray.rows];
    }
    else if (action == 2) {
        if ([data count] < 2) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image open format should be action;;path\r\n"}];
            }
            return nil;
        }
        NSString *path = zx_resolveImagePath(data[1]);
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Image not found. Path: %@\r\n", path ?: data[1]]}];
            }
            return nil;
        }
        Mat gray = imread([path UTF8String], IMREAD_GRAYSCALE);
        if (gray.empty()) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Failed to read image. Path: %@\r\n", path]}];
            }
            return nil;
        }
        __block uint32_t imageId = 0;
        dispatch_sync(zx_imageQueue(), ^{
            imageId = zx_storeImageLocked(gray);
        });
        if (imageId == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Image object limit reached. Release unused images.\r\n"}];
            }
            return nil;
        }
        return [NSString stringWithFormat:@"%u;;%d;;%d", imageId, gray.cols, gray.rows];
    }
    else if (action == 3) {
        if ([data count] < 2) {
            return nil;
        }
        uint32_t imageId = (uint32_t)[data[1] intValue];
        dispatch_sync(zx_imageQueue(), ^{
            gImageStore.erase(imageId);
        });
        return @"";
    }

    if (error) {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unknown image task action.\r\n"}];
    }
    return nil;
}

NSString* handleFindImageTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 10) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Find image format should be template_id;;x;;y;;w;;h;;acceptable;;scale_min;;scale_max;;scale_step;;pixel_skip\r\n"}];
        }
        return nil;
    }
    uint32_t templateId = (uint32_t)[data[0] intValue];
    int rx = [data[1] intValue];
    int ry = [data[2] intValue];
    int rw = [data[3] intValue];
    int rh = [data[4] intValue];
    double acceptable = [data[5] doubleValue];
    float scaleMin = [data[6] floatValue];
    float scaleMax = [data[7] floatValue];
    float scaleStep = [data[8] floatValue];
    int pixelSkip = [data[9] intValue];

    __block ZXImageObject templObj;
    __block bool found = false;
    dispatch_sync(zx_imageQueue(), ^{
        auto it = gImageStore.find(templateId);
        if (it != gImageStore.end()) {
            templObj = it->second;
            found = true;
        }
    });
    if (!found || templObj.gray.empty()) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Template image object not found.\r\n"}];
        }
        return nil;
    }

    CGImageRef screen = [Screen createScreenShotCGImageRef];
    if (!screen) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screenshot.\r\n"}];
        }
        return nil;
    }
    int sw = (int)CGImageGetWidth(screen);
    int sh = (int)CGImageGetHeight(screen);
    if (rx < 0) rx = 0;
    if (ry < 0) ry = 0;
    if (rx >= sw) rx = sw - 1;
    if (ry >= sh) ry = sh - 1;
    if (rw <= 0 || rx + rw > sw) rw = sw - rx;
    if (rh <= 0 || ry + rh > sh) rh = sh - ry;

    CGRect cropRect = CGRectMake(rx, ry, rw, rh);
    CGImageRef cropped = CGImageCreateWithImageInRect(screen, cropRect);
    CGImageRelease(screen);
    if (!cropped) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to crop screenshot.\r\n"}];
        }
        return nil;
    }
    NSError *convErr = nil;
    Mat imgGray = zx_cvMatGrayFromCGImage(cropped, &convErr);
    CGImageRelease(cropped);
    if (imgGray.empty()) {
        if (error) {
            *error = convErr ?: [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Failed to convert screenshot to mat.\r\n"}];
        }
        return nil;
    }

    int mx = -1, my = -1, mw = 0, mh = 0;
    double score = 0.0;
    BOOL match = zx_findTemplateSAD(imgGray, templObj.gray, acceptable, scaleMin, scaleMax, scaleStep, pixelSkip,
                                   &mx, &my, &mw, &mh, &score);
    if (!match) {
        // Provide best score to help tuning acceptable threshold.
        return [NSString stringWithFormat:@"-1;;-1;;0;;0;;-1;;-1;;%.4f", score];
    }

    int absX = rx + mx;
    int absY = ry + my;
    double cx = absX + mw / 2.0;
    double cy = absY + mh / 2.0;
    return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%.2f;;%.2f;;%.4f", absX, absY, mw, mh, cx, cy, score];
}
