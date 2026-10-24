#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <atomic>
#include "../shared/TLinkNativeBudget.h"
#include "../shared/TLinkNativeColorRequest.h"
static std::atomic<uint64_t> offset{0};
static uint64_t FixtureNow(){return TLinkNativeNowNs()+offset.load();}
#include "ColorPolicyUnderTest.h"
#include "../shared/TLinkNativeColorRange.h"
#include "../shared/TLinkNativeColorPoints.h"
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
static void numericRangeCases(){
    const auto check=[](double x,double y,double width,double height,int skip,int low,int high){
        NSString *wire=[NSString stringWithFormat:@"1;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;0;;255;;0;;255;;%d",x,y,width,height,low,high,skip];
        NSError *rawError=nil,*numericError=nil;NSString *raw=search(wire,&rawError);TLinkNativeColorRangeRequest r;r.setRegion(x,y,width,height);r.redMin=low;r.redMax=high;r.skip=skip;TLinkColorResult value;
        const bool ok=searchRGBRange(r,value,&numericError);assert(ok==(raw!=nil));
        if(ok){NSString *expected=[NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d",value.x,value.y,value.r,value.g,value.b];assert([raw isEqualToString:expected]);}
        else assert([rawError.localizedDescription isEqualToString:numericError.localizedDescription]);settled();
    };
    for(double x:{-1e308,-1.5,-0.5,-0.0,0.5,1.5,7.49,7.5,8191.5,1e308})for(double width:{double(INT_MIN),-0.5,0.5,2.5,double(INT_MAX),1e308})for(int skip:{0,1,INT_MAX})check(x,0.5,width,0,skip,0,255);
    check(0,0,0,0,0,11,255);check(0,0,0,0,-1,0,255);check(0,0,0,0,0,-1,255);check(0,0,0,0,0,20,19);
    TLinkNativeColorRangeRequest r;r.setRegion(0,0,0,0);TLinkColorResult value;
    bool *faults[]={&failAllocate,&failCrop,&failSpace,&failContext,&throwDraw,&expireDraw,&expireCapture,&failCapture};
    NSString *codes[]={@"color_allocation_failed",@"color_crop_failed",@"color_space_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out",@"color_cancelled_or_timed_out",@"color_capture_failed"};
    for(unsigned n=0;n<8;++n){NSError *retained=nil;@autoreleasepool{*faults[n]=true;assert(!searchRGBRange(r,value,&retained));}assert([retained.localizedDescription containsString:codes[n]]);offset=0;settled();}
    {TLinkColorRequest first({}),second({});const unsigned before=captures;r.x=-1;NSError *error=nil;assert(!searchRGBRange(r,value,&error)&&[error.localizedDescription containsString:@"color_compute_busy"]&&captures==before);}r.x=0;settled();
    {auto hold=TLinkColorMemory().reserve(TLinkImageKind::Frame,32*1024*1024);assert(hold);NSError *error=nil;assert(!searchRGBRange(r,value,&error)&&[error.localizedDescription containsString:@"color_memory_budget"]);}settled();
    {auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,4096);TLinkNativeBudgetScope scope(budget);cancelOnDraw=token;NSError *error=nil;
        assert(!searchRGBRange(r,value,&error)&&[error.localizedDescription containsString:@"color_cancelled_or_timed_out"]);cancelOnDraw.reset();const unsigned before=captures;error=nil;assert(!searchRGBRange(r,value,&error)&&captures==before);}settled();
    {TLinkColorRequest first({}),second({});assert(first.admitted()&&second.admitted());}
    puts("Numeric live range Foundation passed: 180 RAW/numeric ROI/skip cases, signed/overflow extents, hit/miss/parameter order, capture/graphics faults, NSError lifetime, busy/memory/cancel recovery and zero retained buffers.");
}
static void numericPointsCases(){
    const auto check=[](const TLinkNativeColorPointsRequest &r,NSString *table,NSString *threshold){
        NSString *wire=[NSString stringWithFormat:@"2;;%@;;%d;;%@",table,r.mode,threshold];NSError *rawError=nil,*numericError=nil;NSString *raw=search(wire,&rawError);bool matched=false;
        const bool ok=testRGBPoints(r,matched,&numericError);assert(ok==(raw!=nil));
        if(ok)assert([raw isEqualToString:matched?@"1":@"0"]);else assert([rawError.localizedDescription isEqualToString:numericError.localizedDescription]);settled();
    };
    for(double x:{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.5,8191.5,double(INT_MAX),1e308})for(int mode:{0,1})for(unsigned n=0;n<5;++n){
        const double value=mode?std::vector<double>{-0.00004,0,0.99995,255.00004,255.00006}[n]:std::vector<double>{-0.00006,-0.00004,0.99995,1,1.00006}[n];
        TLinkNativeColorPointsRequest r;r.mode=mode;r.append(x,1.5,10,20,30);r.append(0,0,10,20,30);
        NSString *threshold=[NSString stringWithFormat:@"%.4f",value];r.toleranceUnits=threshold.length;r.toleranceValid=TLinkColorDouble(threshold.UTF8String,r.tolerance);
        check(r,[NSString stringWithFormat:@"%.0f,,%.0f,,10,,20,,30|0,,0,,10,,20,,30",x,1.5],threshold);
    }
    TLinkNativeColorPointsRequest r;NSMutableString *table=[NSMutableString string];
    for(unsigned i=0;i<512;++i){r.append(0,0,10,20,30);if(i)[table appendString:@"|"];[table appendString:@"0,,0,,10,,20,,30"];}
    check(r,table,@"0.0000");r.append(0,0,10,20,30);[table appendString:@"|0,,0,,10,,20,,30"];check(r,table,@"0.0000");
    r=TLinkNativeColorPointsRequest{};r.append(0,0,11,20,30);r.append(0,0,999,0,0);const unsigned beforeInvalid=captures;check(r,@"0,,0,,11,,20,,30|0,,0,,999,,0,,0",@"0.0000");assert(captures==beforeInvalid);
    r=TLinkNativeColorPointsRequest{};r.append(0,0,11,20,30);r.append(8,0,10,20,30);check(r,@"0,,0,,11,,20,,30|8,,0,,10,,20,,30",@"0.0000"); // full source bounds before early mismatch
    r=TLinkNativeColorPointsRequest{};r.append(0,0,10,20,30);bool matched=false;
    bool *faults[]={&failAllocate,&failCrop,&failSpace,&failContext,&throwDraw,&expireDraw,&expireCapture,&failCapture};
    NSString *codes[]={@"color_allocation_failed",@"color_crop_failed",@"color_space_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out",@"color_cancelled_or_timed_out",@"color_capture_failed"};
    for(unsigned n=0;n<8;++n){NSError *retained=nil;@autoreleasepool{*faults[n]=true;assert(!testRGBPoints(r,matched,&retained));}assert([retained.localizedDescription containsString:codes[n]]);offset=0;settled();}
    {TLinkColorRequest first({}),second({});const unsigned before=captures;r.mode=2;NSError *error=nil;assert(!testRGBPoints(r,matched,&error)&&[error.localizedDescription containsString:@"color_compute_busy"]&&captures==before);}r.mode=1;settled();
    {auto hold=TLinkColorMemory().reserve(TLinkImageKind::Frame,32*1024*1024);assert(hold);NSError *error=nil;assert(!testRGBPoints(r,matched,&error)&&[error.localizedDescription containsString:@"color_memory_budget"]);}settled();
    {auto token=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(token,0,4096);TLinkNativeBudgetScope scope(budget);cancelOnDraw=token;NSError *error=nil;
        assert(!testRGBPoints(r,matched,&error)&&[error.localizedDescription containsString:@"color_cancelled_or_timed_out"]);cancelOnDraw.reset();const unsigned before=captures;error=nil;assert(!testRGBPoints(r,matched,&error)&&captures==before);}settled();
    {TLinkColorRequest first({}),second({});assert(first.admitted()&&second.admitted());}
    puts("Numeric live points Foundation passed: 110 RAW/numeric cases, scalar mode boundaries, full-table/pre/post-capture bounds, 512/513, graphics faults/NSError lifetime, busy/memory/cancel recovery and zero retained buffers.");
}
int main(){@autoreleasepool{
    fixtureImage=image(8,6);
    numericRangeCases();
    numericPointsCases();
    fputs("Color Foundation: actual parser, RGBA conversion, encoder and wire results\n",stderr);
    NSError *error=nil;NSDictionary *rgb=getRGBFromRawData((UInt8 *)"2;;1",&error);
    assert(!error&&[rgb[@"red"] intValue]==10&&[rgb[@"green"] intValue]==20&&[rgb[@"blue"] intValue]==30);settled();
    for(double x:{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2.5,7.49,7.5,8.0,8191.49,8191.5,1e308}){
        for(double y:{-0.5,0.5,1.5,5.49,5.5}){
            NSString *wire=[NSString stringWithFormat:@"%.0f;;%.0f",x,y];NSError *rawError=nil,*numericError=nil;
            NSDictionary *rawRGB=getRGBFromRawData((UInt8 *)wire.UTF8String,&rawError);
            const TLinkNativeColorPickRequest position(x,y);
            NSDictionary *numericRGB=getRGBAtPosition(position.x,position.y,&numericError);
            assert((rawRGB&&[rawRGB isEqualToDictionary:numericRGB])||(!rawRGB&&!numericRGB));
            assert((!rawError&&!numericError)||[rawError.localizedDescription isEqualToString:numericError.localizedDescription]);settled();
        }
    }
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
    for(unsigned n=0;n<8;++n){NSError *retained=nil;@autoreleasepool{*faults[n]=true;(void)getRGBAtPosition(0,0,&retained);}assert([retained.localizedDescription containsString:codes[n]]);offset=0;settled();}
    {TLinkColorRequest first({}),second({});unsigned prior=captures;error=nil;assert(!getRGBAtPosition(-1,-1,&error)&&[error.localizedDescription containsString:@"color_compute_busy"]&&captures==prior);}settled();
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
