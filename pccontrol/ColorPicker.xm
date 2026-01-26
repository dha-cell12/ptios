#include "ColorPicker.h"
#include "Screen.h"
#include "Image.h"
#import <imgcodecs/ios.h>
#import <mach/mach.h>


#define COLOR_SEARCHER_SEARCH_SINGLE_POINT 1

// Multi-point color operations
#define COLOR_SEARCHER_IS_COLORS 2
#define COLOR_SEARCHER_FIND_MULTI_POINT 3

typedef struct {
    int dx;
    int dy;
    int r;
    int g;
    int b;
} ZXPointColor;

static BOOL zx_parsePointTable(NSString *tableStr, NSMutableArray<NSValue *> *outPoints, NSError **error)
{
    if (!tableStr || [tableStr length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Point table is empty.\r\n"}];
        }
        return NO;
    }

    NSArray<NSString *> *items = [tableStr componentsSeparatedByString:@"|"];
    for (NSString *item in items) {
        if (!item || [item length] == 0) {
            continue;
        }
        NSArray<NSString *> *parts = [item componentsSeparatedByString:@",,"];
        if ([parts count] != 5) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Invalid point table format. Expect dx,,dy,,r,,g,,b|...\r\n"}];
            }
            return NO;
        }
        ZXPointColor pc;
        pc.dx = [parts[0] intValue];
        pc.dy = [parts[1] intValue];
        pc.r = [parts[2] intValue];
        pc.g = [parts[3] intValue];
        pc.b = [parts[4] intValue];
        [outPoints addObject:[NSValue valueWithBytes:&pc objCType:@encode(ZXPointColor)]];
    }

    if ([outPoints count] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Point table has no valid points.\r\n"}];
        }
        return NO;
    }
    return YES;
}

static inline BOOL zx_colorMatch(int r, int g, int b, int tr, int tg, int tb, int mode, double value)
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

static unsigned char *zx_copyRGBABufferFromCGImage(CGImageRef img, CGRect region, int *outW, int *outH)
{
    if (!img) {
        return NULL;
    }
    int width = (int)region.size.width;
    int height = (int)region.size.height;
    if (width <= 0 || height <= 0) {
        return NULL;
    }

    CGImageRef imageRef = CGImageCreateWithImageInRect(img, region);
    if (!imageRef) {
        return NULL;
    }

    int bytesPerElement = 4;
    int bytesPerRow = bytesPerElement * width;
    int totalBufferBytes = bytesPerRow * height;
    unsigned char *buffer = (unsigned char *)malloc((size_t)totalBufferBytes);
    if (!buffer) {
        CGImageRelease(imageRef);
        return NULL;
    }
    memset(buffer, 0, (size_t)totalBufferBytes);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0.f, 0.f, width, height), imageRef);
    CGImageRelease(imageRef);
    CGContextRelease(context);

    if (outW) *outW = width;
    if (outH) *outH = height;
    return buffer;
}

void report_memory(void);


using namespace cv;
using namespace std;

NSDictionary* getRGBFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 2)
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to pick color. The data format should be \"x;;y\"\r\n"}];
        return @{@"blue": @(-1), @"red": @(-1), @"green": @(-1)};
    }
    CGImageRef screen = [Screen createScreenShotCGImageRef];
    
    int x = [data[0] intValue];
    int y = [data[1] intValue];

    NSDictionary* result = [ColorPicker colorAtPositionFromCGImage:screen x:x andY:y];

    CGImageRelease(screen);
    return result;

}

NSString* searchRGBFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
    
    int searchType = [data[0] intValue];
    
    if (searchType == COLOR_SEARCHER_SEARCH_SINGLE_POINT)
    {
        
        if ([data count] < 12)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to search color. The data format should be \"searchtype;;x;;y;;width;;height;;redMin;;redMax;;greenMin;;greenMax;;blueMin;;blueMax;;skip\"\r\n"}];
            return @"";
        }
        CGImageRef screen = [Screen createScreenShotCGImageRef];

        if (!screen)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to search color. Internal error! Screenshot is null.\r\n"}];
            return @"";
        }

        size_t screenWidth = CGImageGetWidth(screen);
        size_t screenHeight = CGImageGetHeight(screen);


        int x = [data[1] intValue];
        int y = [data[2] intValue];
        int width =  [data[3] intValue];
        int height =  [data[4] intValue];
        int redMin = [data[5] intValue];
        int redMax = [data[6] intValue];
        int greenMin =  [data[7] intValue];
        int greenMax =  [data[8] intValue];
        int blueMin =  [data[9] intValue];
        int blueMax =  [data[10] intValue];
        int skip =  [data[11] intValue];

        if (x > screenWidth)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;The range of the x coordinate should be less than the width of your screen. The width of your screen is %d. Your x: %d\r\n", screenWidth, x]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }
        if (y > screenHeight)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;The range of the y coordinate should be less than the height of your screen. The height of your screen is %d. Your y: %d\r\n", screenHeight, y]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }
        if (redMax < 0 || redMin < 0 || redMax > 255 || redMin > 255 || redMax < redMin)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Max red rgb and min reb rgb should <= 255  && >= 0 and max red rgb should be <= red min rgb. You redMax: %d, redMin: %d\r\n", redMax, redMin]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }
        if (greenMax < 0 || greenMin < 0 || greenMax > 255 || greenMin > 255 || greenMax < greenMin)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Max green rgb and min green rgb should <= 255 && >= 0 and max green rgb should be <= green min rgb. You greenMax: %d, greenMin: %d\r\n", greenMax, greenMin]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }
        if (blueMax < 0 || blueMin < 0 || blueMax > 255 || blueMin > 255 || blueMax < blueMin)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Max blue rgb and min blue rgb should <= 255 && >= 0  and max blue rgb should be <= blue min rgb. You blueMax: %d, blueMin: %d\r\n", blueMax, blueMin]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }
        if (skip < 0)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;Skip cannot be negative\r\n", skip]}];
            NSLog(@"com.zjx.springboard: %@", *error);
            return @"";
        }

        if (width <= 0 || x + width > screenWidth)
        {
            width = screenWidth - x;
        }    
        if (height <= 0 || y + height > screenHeight)
        {
            height = screenHeight - y;
        }
    
        NSString *result = [ColorPicker searchRGBFromCGImageRef:screen region:CGRectMake(x, y, width, height) redMin:redMin redMax:redMax greenMin:greenMin greenMax:greenMax blueMin:blueMin blueMax:blueMax skip:skip];
        CGImageRelease(screen);

        return result;
    }
    else if (searchType == COLOR_SEARCHER_IS_COLORS)
    {
        if ([data count] < 4)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to check colors. The data format should be \"searchtype;;table;;mode;;value\"\r\n"}];
            return @"";
        }

        NSString *tableStr = data[1];
        int mode = [data[2] intValue];
        double value = [data[3] doubleValue];
        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        NSError *parseErr = nil;
        if (!zx_parsePointTable(tableStr, points, &parseErr))
        {
            if (error) *error = parseErr;
            return @"";
        }

        CGImageRef screen = [Screen createScreenShotCGImageRef];
        if (!screen)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to check colors. Internal error! Screenshot is null.\r\n"}];
            return @"";
        }

        int screenW = (int)CGImageGetWidth(screen);
        int screenH = (int)CGImageGetHeight(screen);

        int minX = INT_MAX, minY = INT_MAX, maxX = INT_MIN, maxY = INT_MIN;
        for (NSValue *v in points) {
            ZXPointColor pc;
            [v getValue:&pc];
            int x = pc.dx;
            int y = pc.dy;
            if (x < 0 || y < 0 || x >= screenW || y >= screenH) {
                CGImageRelease(screen);
                *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Point out of screen bounds.\r\n"}];
                return @"";
            }
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
        }

        CGRect crop = CGRectMake(minX, minY, (maxX - minX + 1), (maxY - minY + 1));
        int bufW = 0, bufH = 0;
        unsigned char *buffer = zx_copyRGBABufferFromCGImage(screen, crop, &bufW, &bufH);
        CGImageRelease(screen);
        if (!buffer) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to read screenshot buffer.\r\n"}];
            return @"";
        }

        BOOL matched = YES;
        for (NSValue *v in points) {
            ZXPointColor pc;
            [v getValue:&pc];
            int lx = pc.dx - minX;
            int ly = pc.dy - minY;
            int base = (ly * bufW + lx) * 4;
            int r = buffer[base];
            int g = buffer[base + 1];
            int b = buffer[base + 2];
            if (!zx_colorMatch(r, g, b, pc.r, pc.g, pc.b, mode, value)) {
                matched = NO;
                break;
            }
        }
        free(buffer);

        return matched ? @"1" : @"0";
    }
    else if (searchType == COLOR_SEARCHER_FIND_MULTI_POINT)
    {
        if ([data count] < 9)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to find multi-point color. The data format should be \"searchtype;;x;;y;;width;;height;;table;;mode;;value;;skip\"\r\n"}];
            return @"";
        }

        int regionX = [data[1] intValue];
        int regionY = [data[2] intValue];
        int regionW = [data[3] intValue];
        int regionH = [data[4] intValue];
        NSString *tableStr = data[5];
        int mode = [data[6] intValue];
        double value = [data[7] doubleValue];
        int skip = [data[8] intValue];

        NSMutableArray<NSValue *> *points = [NSMutableArray array];
        NSError *parseErr = nil;
        if (!zx_parsePointTable(tableStr, points, &parseErr))
        {
            if (error) *error = parseErr;
            return @"";
        }

        CGImageRef screen = [Screen createScreenShotCGImageRef];
        if (!screen)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to search color. Internal error! Screenshot is null.\r\n"}];
            return @"";
        }

        int screenW = (int)CGImageGetWidth(screen);
        int screenH = (int)CGImageGetHeight(screen);

        if (regionX < 0) regionX = 0;
        if (regionY < 0) regionY = 0;
        if (regionX >= screenW) regionX = screenW - 1;
        if (regionY >= screenH) regionY = screenH - 1;

        if (regionW <= 0 || regionX + regionW > screenW) {
            regionW = screenW - regionX;
        }
        if (regionH <= 0 || regionY + regionH > screenH) {
            regionH = screenH - regionY;
        }

        int minDx = INT_MAX, minDy = INT_MAX, maxDx = INT_MIN, maxDy = INT_MIN;
        for (NSValue *v in points) {
            ZXPointColor pc;
            [v getValue:&pc];
            if (pc.dx < minDx) minDx = pc.dx;
            if (pc.dy < minDy) minDy = pc.dy;
            if (pc.dx > maxDx) maxDx = pc.dx;
            if (pc.dy > maxDy) maxDy = pc.dy;
        }

        int axStart = MAX(regionX, -minDx);
        int ayStart = MAX(regionY, -minDy);
        int axEnd = MIN(regionX + regionW - 1, screenW - 1 - maxDx);
        int ayEnd = MIN(regionY + regionH - 1, screenH - 1 - maxDy);
        if (axStart > axEnd || ayStart > ayEnd) {
            CGImageRelease(screen);
            return @"-1;;-1";
        }

        int cropX = axStart + minDx;
        int cropY = ayStart + minDy;
        int cropW = (axEnd - axStart + 1) + (maxDx - minDx);
        int cropH = (ayEnd - ayStart + 1) + (maxDy - minDy);
        CGRect crop = CGRectMake(cropX, cropY, cropW, cropH);

        int bufW = 0, bufH = 0;
        unsigned char *buffer = zx_copyRGBABufferFromCGImage(screen, crop, &bufW, &bufH);
        CGImageRelease(screen);
        if (!buffer) {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to read screenshot buffer.\r\n"}];
            return @"";
        }

        int step = skip + 1;
        if (step <= 0) step = 1;
        for (int ay = ayStart; ay <= ayEnd; ay += step) {
            for (int ax = axStart; ax <= axEnd; ax += step) {
                BOOL ok = YES;
                for (NSValue *v in points) {
                    ZXPointColor pc;
                    [v getValue:&pc];
                    int px = ax + pc.dx;
                    int py = ay + pc.dy;
                    int lx = px - cropX;
                    int ly = py - cropY;
                    int base = (ly * bufW + lx) * 4;
                    int r = buffer[base];
                    int g = buffer[base + 1];
                    int b = buffer[base + 2];
                    if (!zx_colorMatch(r, g, b, pc.r, pc.g, pc.b, mode, value)) {
                        ok = NO;
                        break;
                    }
                }
                if (ok) {
                    free(buffer);
                    return [NSString stringWithFormat:@"%d;;%d", ax, ay];
                }
            }
        }

        free(buffer);
        return @"-1;;-1";
    }
    else
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to search color. Unknown search color task type.\r\n"}];
        NSLog(@"com.zjx.springboard: %@", *error);
        return nil;
    }
}


@implementation ColorPicker
{

}

+ (NSDictionary *)colorAtPositionFromCGImage:(CGImageRef)img x:(int)x andY:(int)y {
    CGRect sourceRect = CGRectMake(x, y, 1.f, 1.f);
    CGImageRef imageRef = CGImageCreateWithImageInRect(img, sourceRect);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *buffer = (unsigned char *)malloc(4);
    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef context = CGBitmapContextCreate(buffer, 1, 1, 8, 4, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0.f, 0.f, 1.f, 1.f), imageRef);
    CGImageRelease(imageRef);
    CGContextRelease(context);
    
    uchar r = buffer[0];
    uchar g = buffer[1];
    uchar b = buffer[2];

    free(buffer);
    return @{@"blue": @(b), @"red": @(r), @"green": @(g)};
}

/*
+ (NSDictionary*) getRgbFromMat:(Mat)img x:(int)x y:(int)y {
    //NSLog(@"com.zjx.springboard: height: %d, width: %d, channels: %d. scale: %f", img.rows, img.cols, img.channels(), [Screen getScale]);

    Vec3b intensity = img.at<Vec3b>(y, x);
    // Don't know why. This version of opencv stores read at [0] rather than [2]
    uchar blue = intensity.val[0];
    uchar green = intensity.val[1];
    uchar red = intensity.val[2];
    //NSLog(@"com.zjx.springboard: blue: %u, green: %u, red: %u.", blue, green, red);

    NSDictionary *result = @{@"blue": @(blue), @"red": @(red), @"green": @(green)};
    return result;
}
*/

/*
+ (NSString*) searchRGBFromMat:(Mat)img region:(CGRect)region redMin:(int)redMin redMax:(int)redMax greenMin:(int)greenMin greenMax:(int)greenMax blueMin:(int)blueMin blueMax:(int)blueMax skip:(int)skip {
    //NSLog(@"com.zjx.springboard: image height: %d, width: %d, channels: %d. scale: %f. Rect: %@. skip: %d. redSearch: (%d, %d), greenSearch: (%d, %d), blueSearch: (%d, %d)", img.rows, img.cols, img.channels(), [Screen getScale], NSStringFromCGRect(region), skip, redMin, redMax, greenMin, greenMax, blueMin, blueMax);
    
    int x = region.origin.x;
    int y = region.origin.y;

    int width = region.size.width;
    int height = region.size.height;

    int searchMaxX = x + width;
    int searchMaxY = y + height;

    for (int currentY = y; currentY <= searchMaxY; currentY += skip + 1)
    {
        for (int currentX = x; currentX <= searchMaxX; currentX += skip + 1)
        {
            Vec3b intensity = img.at<Vec3b>(currentY, currentX);
            uchar blue = intensity.val[0];
            uchar green = intensity.val[1];
            uchar red = intensity.val[2];

            //NSLog(@"com.zjx.springboard: x: %d, y: %d, blue: %u, green: %u, red: %u.", currentX, currentY, blue, green, red);
            if (red >= redMin && red <= redMax && green >= greenMin && green <= greenMax && blue >= blueMin && blue <= blueMax)
            {
                return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d", currentX, currentY, red, green, blue];
            }
        }
    }

    return @"-1;;-1;;-1";
}
*/

+ (NSString*)searchRGBFromCGImageRef:(CGImageRef)img region:(CGRect)region redMin:(int)redMin redMax:(int)redMax greenMin:(int)greenMin greenMax:(int)greenMax blueMin:(int)blueMin blueMax:(int)blueMax skip:(int)skip {
    int x = region.origin.x;
    int y = region.origin.y; 
    
    int width = region.size.width;
    int height = region.size.height;

    CGImageRef imageRef = CGImageCreateWithImageInRect(img, region);
    
    int bytesPerElement = 4;
    int bytesPerRow = bytesPerElement * width;
    int totalBufferBytes = bytesPerRow * height;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    unsigned char *buffer = (unsigned char *)malloc(totalBufferBytes);
    memset(buffer, 0, totalBufferBytes);

    CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0.f, 0.f, width, height), imageRef);
    CGImageRelease(imageRef);
    CGContextRelease(context);
    
    for (int currentY = 0; currentY < height; currentY += skip + 1)
    {
        for (int currentX = 0; currentX < width; currentX += skip + 1)
        {
            int baseAddress = (currentY * width + currentX) * 4;

            if (baseAddress >= totalBufferBytes-3)
            {
                NSLog(@"com.zjx.springboard: cannot search rgb from cgimage. Internal error. start coordinate on img: (%d, %d). current coordinate: (%d, %d), baseaddress: %d, totalBufferBytes: %d", x, y, currentX, currentY, baseAddress, totalBufferBytes);
                return @"-1;;-1;;-1;;-1;;-1";
            }

            uchar red = buffer[baseAddress];
            uchar green = buffer[baseAddress+1];
            uchar blue = buffer[baseAddress+2];


            //NSLog(@"com.zjx.springboard: x: %d, y: %d, blue: %u, green: %u, red: %u.", currentX, currentY, blue, green, red);
            if (red >= redMin && red <= redMax && green >= greenMin && green <= greenMax && blue >= blueMin && blue <= blueMax)
            {
                free(buffer);
                return [NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d", x+currentX, y+currentY, red, green, blue];
            }
        }
    }
    

    free(buffer);
    return @"-1;;-1;;-1;;-1;;-1";
}




@end
