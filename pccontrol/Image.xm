#import "Image.h"
#import "Image.h"
#import "Screen.h"
#import "Common.h"
#import "ScriptPlayer.h"

#include <dispatch/dispatch.h>
#include <unordered_map>
#include <climits>
#include <math.h>

// From Play.xm
extern ScriptPlayer *scriptPlayer;

using namespace cv;
using namespace std;

typedef struct {
    cv::Mat gray;
    int w;
    int h;
} ZXImageObject;

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
