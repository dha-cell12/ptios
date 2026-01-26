//
//  TemplateMatch.cpp
//  OpenCVTest
//
//  Created by Yun CHEN on 2018/2/8.
//  Copyright © 2018年 Yun CHEN. All rights reserved.
//


#import "TemplateMatch.h"
#include <vector>
#include <math.h>

#ifdef ZX_DAEMON
#include <stdarg.h>

// Minimal file logger for daemon builds.
// We intentionally avoid depending on zxtouch-binary/SocketServer.mm static zx_logf().
static NSString *zx_tm_logFilePath(void)
{
    return @"/var/mobile/Library/ZXTouch/zxtouchd.log";
}

static void zx_tm_logf(const char *fmt, ...)
{
    @autoreleasepool {
        char msg[2048];
        va_list args;
        va_start(args, fmt);
        vsnprintf(msg, sizeof(msg), fmt, args);
        va_end(args);

        NSString *dir = @"/var/mobile/Library/ZXTouch";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:true
                                                   attributes:nil
                                                        error:nil];

        NSDate *now = [NSDate date];
        static NSDateFormatter *df = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            df = [[NSDateFormatter alloc] init];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });

        NSString *line = [NSString stringWithFormat:@"%@ [TemplateMatch] %s\n", [df stringFromDate:now], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;

        NSString *path = zx_tm_logFilePath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:true];
        }

        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {
        }
        @try { [fh closeFile]; } @catch (__unused NSException *e) {}
    }
}

#define TMLOGF(fmt, ...) zx_tm_logf((fmt), ##__VA_ARGS__)
#else
#define TMLOGF(fmt, ...) NSLog(@"com.zjx.springboard: " fmt, ##__VA_ARGS__)
#endif



using namespace cv;
using namespace std;



@interface TemplateMatch() {
    UIImage *_templateImage;
    vector<Mat> _scaledTempls;
    int maxTryTimes;
    float acceptableValue;
    float scaleRation;
    float resizeRatio;
}

@end



@implementation TemplateMatch

//static float resizeRatio = 0.35;              //原图缩放比例，越小性能越好，但识别度越低
//static int maxTryTimes = 4;                   //未达到预定识别度时，再尝试的次数限制
//static float acceptableValue = 0.9;           //达到此识别度才被认为正确
//static float scaleRation = 0.75;              //当模板未被识别时，尝试放大/缩小模板。 指定每次模板缩小的比例

- (void)setScaleRation:(float)sr {
    scaleRation = sr;
}

- (void)setAcceptableValue:(float)av {
    acceptableValue = av;
}

- (void)setMaxTryTimes:(int)mtt {
    maxTryTimes = mtt;
}

- (id)init {
    self = [super init];
    if (self) {
        resizeRatio = 1.0f;
    }
    return self;
}

- (CGRect)templateMatchWithCGImage:(CGImageRef)img templatePath:(NSString*)templatePath error:(NSError**)err {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(img);
    CGFloat cols = CGImageGetWidth(img);
    CGFloat rows = CGImageGetHeight(img);

    cv::Mat screenMat(rows, cols, CV_8UC4); // 8 bits per component, 4 channels

    
    CGContextRef contextRef = CGBitmapContextCreate(screenMat.data,                 // Pointer to backing data
                                                    cols,                      // Width of bitmap
                                                    rows,                     // Height of bitmap
                                                    8,                          // Bits per component
                                                    screenMat.step[0],              // Bytes per row
                                                    colorSpace,                 // Colorspace
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap info flags

    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), img);

    CGContextRelease(contextRef);
    // CGImageGetColorSpace() does not transfer ownership.
    
    Mat templ = imread([templatePath UTF8String], IMREAD_GRAYSCALE); //[templatePath UTF8String]
    if (templ.cols == 0 && templ.rows == 0)
    {
        if (err) {
            *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Read failed! Check permission or file existance. The height and width of the template image is 0! Template path: %@\r\n", templatePath]}];
        }
        return CGRect();    
    }
    cv::Mat greyMat;
    cv::cvtColor(screenMat, greyMat, COLOR_RGBA2GRAY);

    return [self matchWithMat:greyMat andTemplate:templ];
}

- (CGRect)templateMatchWithPath:(NSString*)imgPath templatePath:(NSString*)templatePath error:(NSError**)err {
    TMLOGF("templateMatchWithPath start. imgPath=%s templatePath=%s", [imgPath UTF8String], [templatePath UTF8String]);
    Mat image = imread([imgPath UTF8String], IMREAD_GRAYSCALE); //[imgPath UTF8String]
    Mat templ = imread([templatePath UTF8String], IMREAD_GRAYSCALE); //[templatePath UTF8String]

    TMLOGF("imread done. img=%dx%d templ=%dx%d", image.cols, image.rows, templ.cols, templ.rows);
    
    if (image.cols == 0 && image.rows == 0)
    {
        if (err) {
            *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Read failed! Check permission or file existance. The height and width of the screenshot photo is 0! Screenshot path: %@\r\n", imgPath]}];
        }
        return CGRect();    
    }
    if (templ.cols == 0 && templ.rows == 0)
    {
        if (err) {
            *err = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Read failed! Check permission or file existance. The height and width of the template image is 0! Template path: %@\r\n", templatePath]}];
        }
        return CGRect();    
    }

    return [self matchWithMat:image andTemplate:templ];
}

//uncompleted
- (CGRect)templateMatchWithUIImage:(UIImage*)img template:(UIImage*)templ {
    //return [self matchWithMat:[self cvMatFromUIImage:img] andTemplate:[self cvMatFromUIImage:templ]];
    return CGRect();
}

//调用OpenCV进行匹配
//此方法具体解释参考OpenCV官方文档: https://docs.opencv.org/3.2.0/de/da9/tutorial_template_matching.html
- (CGRect)matchWithMat:(Mat)img andTemplate:(Mat)templ {
    // OpenCV on iOS can behave better with fixed thread count.
    cv::setNumThreads(1);

    // Downscale before matching to keep CPU usage reasonable.
    // This avoids matchTemplate() appearing to "hang" on larger screens.
    float r = resizeRatio;
    if (r <= 0.0f || r > 1.0f) {
        r = 1.0f;
    }
    if (r == 1.0f) {
        const long long pixels = (long long)img.cols * (long long)img.rows;
        if (pixels > 600000) {
            r = 0.5f;
        }
    }
    TMLOGF("using resizeRatio=%.3f", r);

    Mat imgWork = img;
    Mat templWork = templ;
    if (r != 1.0f) {
        cv::resize(img, imgWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
        cv::resize(templ, templWork, cv::Size(0, 0), r, r, cv::INTER_AREA);
    }

    double minVal;
    double maxVal;
    cv::Point minLoc;
    cv::Point maxLoc;

    // New instance is usually created per request, but keep this method safe anyway.
    _scaledTempls.clear();
    _scaledTempls.push_back(templWork);

    Mat templResized;

    //由于模板图和原图大小比例不一致，需要放大缩小模板图，来多次比较。所以建立不同比例的模板图。
    for(int i=0;i<maxTryTimes;i++) {
        //放大模板图
        float powIncreaRation = pow(2 - scaleRation, i+1);
        resize(templWork, templResized, cv::Size(0, 0), powIncreaRation, powIncreaRation);
        _scaledTempls.push_back(templResized); //由于push_back方法执行值拷贝，所以可以复用templResized变量。

        //缩小模板图
        float powReduceRation = pow(scaleRation, i+1);
        NSLog(@"powReduceRation: %f", powReduceRation);
        resize(templWork, templResized, cv::Size(0, 0), powReduceRation, powReduceRation);
        _scaledTempls.push_back(templResized);

    }

    TMLOGF("start matching. screen=%dx%d templates=%lu", imgWork.cols, imgWork.rows, (unsigned long)_scaledTempls.size());

    //匹配不同大小的模板图

    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    const CFTimeInterval timeoutSeconds = 8.0;

    //创建结果矩阵，用于存放单次匹配到的位置信息(单次会匹配到很多，后面根据不同算法取最大或最小值)
        //匹配不同大小的模板图
    for (int i=0; i < _scaledTempls.size(); i++) {
        if (CFAbsoluteTimeGetCurrent() - t0 > timeoutSeconds) {
            TMLOGF("match timeout after %.2fs", (double)timeoutSeconds);
            return CGRect();
        }

        Mat currentTemplate = _scaledTempls[i];

        // If template becomes larger than the screenshot, OpenCV will assert/crash.
        if (currentTemplate.cols <= 0 || currentTemplate.rows <= 0 ||
            currentTemplate.cols > imgWork.cols || currentTemplate.rows > imgWork.rows) {
            continue;
        }

        int result_cols = imgWork.cols - currentTemplate.cols + 1;
        int result_rows = imgWork.rows - currentTemplate.rows + 1;
        if (result_cols <= 0 || result_rows <= 0) {
            continue;
        }
        Mat result;
        result.create(result_rows, result_cols, CV_32FC1);

        // OpenCV match
        CFAbsoluteTime one0 = CFAbsoluteTimeGetCurrent();
        // Note: matchTemplate can be expensive on large images.
        TMLOGF("matchTemplate #%d templ=%dx%d result=%dx%d", i, currentTemplate.cols, currentTemplate.rows, result_cols, result_rows);
        // TM_CCOEFF_NORMED has been observed to hang on some devices/builds.
        // TM_SQDIFF_NORMED is simpler and more robust; we invert the score to keep
        // acceptableValue semantics (higher is better).
        matchTemplate(imgWork, currentTemplate, result, TM_SQDIFF_NORMED);
        TMLOGF("matchTemplate #%d done in %.3fs", i, (double)(CFAbsoluteTimeGetCurrent() - one0));

        //整理出本次匹配的最大最小值
        minMaxLoc(result, &minVal, &maxVal, &minLoc, &maxLoc, Mat());

        // TM_SQDIFF_NORMED: lower is better. Convert to "higher is better" score.
        const double score = 1.0 - minVal;
        if (score >= acceptableValue) {
            TMLOGF("match success. x=%d y=%d width=%d height=%d score=%.4f", minLoc.x, minLoc.y, currentTemplate.cols, currentTemplate.rows, score);

            const CGFloat inv = (r == 0.0f) ? 1.0 : (1.0 / (CGFloat)r);
            return CGRectMake(minLoc.x * inv, minLoc.y * inv,
                              currentTemplate.cols * inv, currentTemplate.rows * inv);
        }
    }
    
    //未匹配到，则返回空区域
    TMLOGF("match failed");
    return CGRect();
}

//UIImage转为OpenCV灰图矩阵
- (Mat)cvMatGrayFromUIImage:(UIImage *)image {
    Mat img;
    Mat img_color = [self cvMatFromUIImage:image];
    cvtColor(img_color, img, COLOR_BGR2GRAY);
    
    return img;
}

//UIImage转为OpenCV矩阵 BUGS exists for color picker!!! Do NOT USE THIS
- (Mat)cvMatFromUIImage:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
    CGFloat cols = image.size.width;
    CGFloat rows = image.size.height;
    
    Mat cvMat(rows, cols, CV_8UC4); // 8位图, 4通道 (颜色 通道 + alpha)
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data,                 // 数据来源
                                                    cols,                       // 宽
                                                    rows,                       // 高
                                                    8,                          // 8位
                                                    cvMat.step[0],              // 每行字节
                                                    colorSpace,                 // 颜色空间
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderDefault); // Bitmap图信息
    
    CGContextDrawImage(contextRef, CGRectMake(0, 0, cols, rows), image.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

//Buffer转为OpenCV矩阵
- (Mat)cvMatFromBuffer:(CMSampleBufferRef)buffer {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    
    //取得高宽，以及数据起始地址
    int bufferWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int bufferHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    unsigned char *pixel = (unsigned char *)CVPixelBufferGetBaseAddress(pixelBuffer);
    
    //转为OpenCV矩阵
    Mat mat = Mat(bufferHeight,bufferWidth,CV_8UC4,pixel,CVPixelBufferGetBytesPerRow(pixelBuffer));
    
    //结束处理
    CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
    
    //转为灰度图矩阵
    Mat matGray;
    cvtColor(mat, matGray, COLOR_BGR2GRAY);
    
    return matGray;
}


@end
