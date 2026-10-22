#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <atomic>
#include "../shared/TLinkNativeBudget.h"
static std::atomic<uint64_t> offset{0};
static uint64_t FixtureNow(){return TLinkNativeNowNs()+offset.load();}
#include "ColorPolicyUnderTest.h"
#include "ColorHeaderUnderTest.h"
static bool failAllocate=false,failCrop=false,failSpace=false,failContext=false,throwDraw=false,expireDraw=false,expireCapture=false,failCapture=false;
static unsigned buffers=0,providers=0,captures=0;
static std::shared_ptr<TLinkNativeCancellation> cancelOnDraw;
static CGImageRef fixtureImage=NULL;
static void *FixtureCalloc(size_t count,size_t size){if(failAllocate){failAllocate=false;return NULL;}void *value=calloc(count,size);if(value)++buffers;return value;}
static void FixtureFree(uint8_t *value){assert(buffers>0);--buffers;free(value);}
static CGImageRef FixtureCrop(CGImageRef image,CGRect rect){if(failCrop){failCrop=false;return NULL;}return CGImageCreateWithImageInRect(image,rect);}
static CGColorSpaceRef FixtureSpace(){if(failSpace){failSpace=false;return NULL;}return CGColorSpaceCreateDeviceRGB();}
static CGContextRef FixtureContext(void *bytes,size_t width,size_t height,size_t bits,size_t stride,CGColorSpaceRef space,uint32_t flags){if(failContext){failContext=false;return NULL;}return CGBitmapContextCreate(bytes,width,height,bits,stride,space,flags);}
static void FixtureDraw(CGContextRef context,CGRect rect,CGImageRef image){
    if(throwDraw){throwDraw=false;@throw [NSException exceptionWithName:@"fixture.draw" reason:@"injected" userInfo:nil];}
    CGContextDrawImage(context,rect,image);
    if(expireDraw){expireDraw=false;offset.fetch_add(3100000000ULL);}
    if(cancelOnDraw)cancelOnDraw->cancel();
}
@interface Screen:NSObject
+ (CGImageRef)createScreenShotCGImageRef;
@end
@implementation Screen
+ (CGImageRef)createScreenShotCGImageRef{++captures;if(expireCapture){expireCapture=false;offset.fetch_add(3100000000ULL);}if(failCapture){failCapture=false;return NULL;}return CGImageRetain(fixtureImage);}
@end
#include "ColorUnderTest.inc"
static bool TLinkautoJSIsFiniteNumber(double value){return std::isfinite(value);}
#include "ColorEncoderUnderTest.inc"
static CGImageRef image(unsigned width,unsigned height){
    const size_t size=size_t(width)*height*4;uint8_t *bytes=static_cast<uint8_t *>(calloc(size,1));assert(bytes);
    for(size_t i=0;i<size;i+=4){bytes[i]=10;bytes[i+1]=20;bytes[i+2]=30;bytes[i+3]=255;}
    ++providers;CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,bytes,size,[](void *,const void *data,size_t){free((void *)data);assert(providers>0);--providers;});assert(provider);
    CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();CGImageRef result=CGImageCreate(width,height,8,32,size_t(width)*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(rgb);CGDataProviderRelease(provider);assert(result);return result;
}
static void settled(){assert(buffers==0&&TLinkColorMemory().stats().total==0);}
static NSString *search(NSString *payload,NSError **error){return searchRGBFromRawData((UInt8 *)payload.UTF8String,error);}
static void rejected(NSString *payload,NSString *code,bool beforeCapture){
    NSError *error=nil;unsigned prior=captures;assert(!search(payload,&error)&&[error.localizedDescription containsString:code]);if(beforeCapture)assert(captures==prior);settled();
}
int main(){@autoreleasepool{
    fixtureImage=image(8,6);
    fputs("Color Foundation: actual parser, RGBA conversion, encoder and wire results\n",stderr);
    NSError *error=nil;NSDictionary *rgb=getRGBFromRawData((UInt8 *)"2;;1",&error);
    assert(!error&&[rgb[@"red"] intValue]==10&&[rgb[@"green"] intValue]==20&&[rgb[@"blue"] intValue]==30);settled();
    assert([search(@"1;;2;;1;;3;;2;;10;;10;;20;;20;;30;;30;;0",&error) isEqualToString:@"2;;1;;10;;20;;30"]&&!error);settled();
    assert([search(@"1;;0;;0;;0;;0;;40;;50;;20;;20;;30;;30;;2147483647",&error) isEqualToString:@"-1;;-1;;-1;;-1;;-1"]&&!error);settled();
    NSString *table=@"0,,0,,10,,20,,30|3,,2,,10,,20,,30";
    assert([search([NSString stringWithFormat:@"2;;%@;;1;;0",table],&error) isEqualToString:@"1"]&&!error);
    assert([search(@"2;;0,,0,,11,,20,,30;;1;;0",&error) isEqualToString:@"0"]&&!error);
    assert([search(@"3;;0;;0;;0;;0;;-1,,-1,,10,,20,,30|2,,1,,10,,20,,30;;1;;0;;0",&error) isEqualToString:@"1;;1"]&&!error);
    assert([search(@"3;;0;;0;;0;;0;;-2147483648,,0,,10,,20,,30|2147483647,,0,,10,,20,,30;;1;;0;;0",&error) isEqualToString:@"-1;;-1"]&&!error);settled();
    NSArray *points=@[@{@"x":@0,@"y":@0,@"red":@10,@"green":@20,@"blue":@30},@{@"x":@3,@"y":@2,@"r":@10,@"g":@20,@"b":@30}];
    NSString *encoded=TLinkautoJSEncodePointColorTable(points);assert([encoded isEqualToString:table]);
    assert([search([NSString stringWithFormat:@"2;;%@;;1;;0",encoded],&error) isEqualToString:@"1"]&&!error);settled();
    fputs("Color Foundation: invalid pre/post-capture input, fault cleanup and retained NSError\n",stderr);
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        rejected(@"1;;0;;0;;1;;1;;-1;;255;;0;;255;;0;;255;;0",@"color_parameters_invalid",true);
        rejected(@"1;;8;;0;;1;;1;;0;;255;;0;;255;;0;;255;;0",@"color_region_invalid",false);
    }}
    rejected(@"2;;0,,0,,256,,0,,0;;1;;0",@"color_point_table_invalid",true);
    rejected(@"2;;0,,0,,0,,0,,0;;1;;nan",@"color_parameters_invalid",true);
    rejected(@"3;;0;;0;;0;;0;;0,,0,,0,,0,,0;;1;;0;;-1",@"color_parameters_invalid",true);
    rejected(@"2;;8,,0,,0,,0,,0;;1;;0",@"color_point_out_of_bounds",false);
    rejected(@"2;;-1,,0,,0,,0,,0;;1;;0",@"color_point_out_of_bounds",true);
    NSMutableArray *tooMany=[NSMutableArray array];for(unsigned n=0;n<513;++n)[tooMany addObject:@"0,,0,,0,,0,,0"];
    rejected([NSString stringWithFormat:@"2;;%@;;1;;0",[tooMany componentsJoinedByString:@"|"]],@"color_point_table_limit",true);
    rejected([@"x" stringByPaddingToLength:262145 withString:@"x" startingAtIndex:0],@"color_payload_limit",true);
    error=nil;assert(!getRGBFromRawData((UInt8 *)"8;;0",&error)&&[error.localizedDescription containsString:@"color_roi_invalid_or_too_large"]);settled();
    bool *faults[]={&failAllocate,&failCrop,&failSpace,&failContext,&throwDraw,&expireDraw,&expireCapture,&failCapture};
    NSString *codes[]={@"color_allocation_failed",@"color_crop_failed",@"color_space_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out",@"color_cancelled_or_timed_out",@"color_capture_failed"};
    for(unsigned n=0;n<8;++n){NSError *retained=nil;@autoreleasepool{*faults[n]=true;(void)getRGBFromRawData((UInt8 *)"0;;0",&retained);}assert([retained.localizedDescription containsString:codes[n]]);offset=0;settled();}
    {auto hold=TLinkColorMemory().reserve(TLinkImageKind::Frame,32*1024*1024);assert(hold);error=nil;assert(!getRGBFromRawData((UInt8 *)"0;;0",&error)&&[error.localizedDescription containsString:@"color_memory_budget"]);}settled();
    {TLinkColorRequest first({}),second({});unsigned prior=captures;error=nil;assert(!getRGBFromRawData((UInt8 *)"0;;0",&error)&&[error.localizedDescription containsString:@"color_compute_busy"]&&captures==prior);}settled();
    {auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,4096);TLinkNativeBudgetScope scope(budget);cancelOnDraw=token;error=nil;assert(!getRGBFromRawData((UInt8 *)"0;;0",&error)&&[error.localizedDescription containsString:@"color_cancelled_or_timed_out"]);cancelOnDraw.reset();unsigned prior=captures;error=nil;assert(!getRGBFromRawData((UInt8 *)"0;;0",&error)&&captures==prior);}settled();
    assert([[ColorPicker colorAtPositionFromCGImage:fixtureImage x:0 andY:0][@"red"] intValue]==10);
    assert([[ColorPicker colorAtPositionFromCGImage:fixtureImage x:8 andY:0][@"red"] intValue]==-1);assert(CGImageGetWidth(fixtureImage)==8);settled();
    CGImageRelease(fixtureImage);fixtureImage=image(8193,1);error=nil;assert(!getRGBFromRawData((UInt8 *)"0;;0",&error)&&[error.localizedDescription containsString:@"color_source_pixel_limit"]);settled();
    CGImageRelease(fixtureImage);fixtureImage=image(4096,2048);rejected(@"1;;0;;0;;0;;0;;0;;255;;0;;255;;0;;255;;0",@"color_roi_invalid_or_too_large",false);settled();
    CGImageRelease(fixtureImage);fixtureImage=NULL;
    assert(providers==0);settled();
    puts("Color Foundation passed: production parser/scan/encoder, actual RGBA channels, golden wire shapes, 1000 invalid lifecycles, allocation/crop/space/context/exception faults, error lifetime, bounds/byte/busy/cancel and zero final buffers/providers. Real capture/device checks remain pending.");
}}
