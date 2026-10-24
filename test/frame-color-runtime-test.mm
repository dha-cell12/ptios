#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "../shared/TLinkNativeDispatch.h"
#include "../shared/TLinkModernImagePolicy.h"
#include "../shared/TLinkNativeFramePick.h"
#include "../shared/TLinkNativeFrameSearch.h"
#include <cassert>
#include <cstdio>
#include <unordered_map>
#include "modern-image-fixture.h"
using namespace std;
#include "ModernPayload.inc"
using ZXPointColor=TLinkColorPoint;
static TLinkImageComputeGate gImageCompute;
static const uint64_t kDefaultFrameTtlMs=1000;
static const size_t kMaxImageObjects=64;
static unordered_map<uint32_t,ZXFrameRef> gFrameStore;
static unordered_map<uint32_t,ZXImageRef> gImageStore;
static uint64_t zx_nowMs(){return TLinkImageNowMs();}
static dispatch_queue_t zx_imageQueue(){static dispatch_queue_t q=dispatch_queue_create("fixture.image",DISPATCH_QUEUE_SERIAL);return q;}
static void zx_cleanupFramesLocked(uint64_t){}
static bool zx_rearmFrameExpiryLocked(){return true;}
static bool eraseOnSnapshot=false;static shared_ptr<TLinkNativeCancellation> cancelOnSnapshot;
static ZXFrameRef zx_snapshotFrame(uint32_t id){auto it=gFrameStore.find(id);ZXFrameRef snapshot=it==gFrameStore.end()?ZXFrameRef():it->second;if(eraseOnSnapshot)gFrameStore.erase(id);if(cancelOnSnapshot)cancelOnSnapshot->cancel();return snapshot;}
#include "FrameColorHelpers.inc"
static unsigned captures=0;
@interface Screen:NSObject
+(CGImageRef)createScreenShotCGImageRef CF_RETURNS_RETAINED;
@end
@implementation Screen
+(CGImageRef)createScreenShotCGImageRef{
    ++captures;NSData *pixels=[NSMutableData dataWithLength:256];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);assert(provider);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();assert(space);
    CGImageRef image=CGImageCreate(8,8,8,32,32,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast,provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);CGDataProviderRelease(provider);assert(image);return image;
}
@end
static cv::Mat zx_cvMatGrayFromCGImage(CGImageRef image,NSError **){return Mat(int(CGImageGetWidth(image)),int(CGImageGetHeight(image)));}
#include "ModernSadUnderTest.inc"
#include "ModernScaleUnderTest.inc"
#include "ModernFindFrame.inc"
#include "ModernBatch.inc"
#include "ModernFindFresh.inc"
static bool freezeColorClock=false;static uint64_t colorClock=100000;
static uint64_t FixtureFrameColorNow(){return freezeColorClock?colorClock:zx_nowMs();}
static double FixtureFrameColorSeconds(){return freezeColorClock?1.0:TLinkImageNowSeconds();}
#define zx_nowMs FixtureFrameColorNow
#define TLinkImageNowSeconds FixtureFrameColorSeconds
#include "FrameColorUnderTest.inc"
#undef TLinkImageNowSeconds
#undef zx_nowMs
static NSString *color(NSString *wire,NSError **error){return handleColorInFrameTaskFromRawData((UInt8 *)wire.UTF8String,error);}
static NSString *batch(NSString *wire,NSError **error){return handleFrameBatchTaskFromRawData((UInt8 *)wire.UTF8String,error);}
static NSString *find(NSString *wire,NSError **error){return handleFindImageTaskFromRawData((UInt8 *)wire.UTF8String,error);}
static NSString *findFrame(NSString *wire,NSError **error){return handleFindImageInFrameTaskFromRawData((UInt8 *)wire.UTF8String,error);}
static void numericFramePickCases(const shared_ptr<ZXFrameObject> &frame){
    const auto created=frame->createdAtMs,expires=frame->expiresAtMs;freezeColorClock=true;
    frame->createdAtMs=colorClock-10;frame->expiresAtMs=colorClock+5000;
    const unsigned beforeCapture=captures;
    for(bool point:{false,true})for(double x:{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2.5,3.49,3.5,7.5,2147483647.0,1e308})for(double y:{-0.5,0.5,1.5,3.49,5.5}){
        TLinkNativeFramePickRequest pick;pick.frameId=1;pick.maxAgeMs=5000;pick.pointCoord=point;
        pick.x=TLinkNativeFrameJSCoordinate(x);pick.y=TLinkNativeFrameJSCoordinate(y);
        NSString *wire=[NSString stringWithFormat:@"1;;pick;;%.0f;;%.0f;;%@;;5000",x,y,point?@"point":@"pixel"];
        NSError *rawError=nil,*numericError=nil;NSString *raw=color(wire,&rawError);TLinkNativeFramePickValue result;
        bool ok=readFramePixel(pick,result,&numericError);
        assert(ok==(raw!=nil));
        if(ok){NSString *expected=[NSString stringWithFormat:@"%d;;%d;;%d;;%llu;;%.3f;;%.3f",result.red,result.green,result.blue,(unsigned long long)result.ageMs,result.totalMs,result.totalMs];assert([raw isEqualToString:expected]);}
        else assert([rawError.localizedDescription isEqualToString:numericError.localizedDescription]);
    }
    TLinkNativeFramePickRequest pick;pick.frameId=1;pick.maxAgeMs=5000;TLinkNativeFramePickValue result;NSError *error=nil;
    frame->expiresAtMs=colorClock;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"frame_expired"]);frame->expiresAtMs=colorClock+5000;
    frame->createdAtMs=colorClock-1001;pick.maxAgeMs=0;error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"frame_expired"]);
    pick.maxAgeMs=5000;error=nil;assert(readFramePixel(pick,result,&error)&&result.ageMs==1001);
    frame->bgra.resize(319);error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"frame_geometry_invalid"]);frame->bgra.resize(320);
    frame->hasBGRA=false;error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"frame_missing_bgra"]);frame->hasBGRA=true;
    pick.frameId=999;error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"frame_not_found"]);pick.frameId=1;
    {TLinkColorRequest first({}),second({});pick.validCoord=false;error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"color_compute_busy"]);}pick.validCoord=true;
    {TLinkImageWork first(gImageCompute),second(gImageCompute);error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"image_compute_busy"]);}
    eraseOnSnapshot=true;error=nil;assert(readFramePixel(pick,result,&error)&&gFrameStore.count(1)==0);eraseOnSnapshot=false;gFrameStore[1]=frame;
    auto cancel=make_shared<TLinkNativeCancellation>();auto parent=make_shared<TLinkNativeBudget>(cancel,0,4096);cancel->cancel();
    {TLinkNativeBudgetScope scope(parent);error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"cancelled_or_timed_out"]);}
    auto lateCancel=make_shared<TLinkNativeCancellation>();auto lateBudget=make_shared<TLinkNativeBudget>(lateCancel,0,4096);
    cancelOnSnapshot=lateCancel;
    {TLinkNativeBudgetScope scope(lateBudget);error=nil;assert(!readFramePixel(pick,result,&error)&&[error.localizedDescription containsString:@"cancelled_or_timed_out"]);}
    cancelOnSnapshot.reset();
    assert(captures==beforeCapture);frame->createdAtMs=created;frame->expiresAtMs=expires;freezeColorClock=false;
    puts("Numeric frame pick Foundation passed: 120 RAW/typed exact reply cases, padded stride/point scaling, TTL/default age, geometry/BGRA/missing frames, two admission gates, held snapshot after erase and no recapture.");
}
static void numericFramePickManyCases(const shared_ptr<ZXFrameObject> &frame){
    const auto created=frame->createdAtMs,expires=frame->expiresAtMs;freezeColorClock=true;
    frame->createdAtMs=colorClock-10;frame->expiresAtMs=colorClock+5000;const unsigned beforeCapture=captures;
    const auto check=[](TLinkNativeFramePickManyRequest &pick,NSString *table){
        NSString *coord=pick.frame.validCoord?(pick.frame.pointCoord?@"point":@"pixel"):@"typo";
        NSString *wire=[NSString stringWithFormat:@"%d;;pick_many;;%@;;%@;;%d",pick.frame.frameId,table,coord,pick.frame.maxAgeMs];
        NSError *rawError=nil,*numericError=nil;NSString *raw=color(wire,&rawError);TLinkNativeFramePickManyValue result;
        const bool ok=readFramePixels(pick,result,&numericError);assert(ok==(raw!=nil));
        if(ok){
            NSMutableArray *rows=[NSMutableArray array];for(const auto &pixel:result.colors)[rows addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d",pixel.x,pixel.y,pixel.red,pixel.green,pixel.blue]];
            NSString *expected=[NSString stringWithFormat:@"%@;;%llu;;%.3f;;%.3f",[rows componentsJoinedByString:@"|"],(unsigned long long)result.ageMs,result.totalMs,result.totalMs];
            assert([raw isEqualToString:expected]&&result.colors.size()==pick.pointCount);
        }else assert([rawError.localizedDescription isEqualToString:numericError.localizedDescription]);
    };
    for(bool point:{false,true})for(double x:{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2.5,3.49,3.5,7.5,2147483647.0,1e308})for(double y:{-0.5,0.5,1.5,3.49,5.5}){
        TLinkNativeFramePickManyRequest pick;pick.frame.frameId=1;pick.frame.maxAgeMs=5000;pick.frame.pointCoord=point;pick.append(x,y);pick.append(0,0);
        NSString *table=[NSString stringWithFormat:@"%.0f,%.0f|0,0",x,y];check(pick,table);
    }
    TLinkNativeFramePickManyRequest pick;pick.frame.frameId=1;pick.frame.maxAgeMs=5000;pick.append(0,0);
    NSMutableString *table=[NSMutableString stringWithString:@"0,0"];
    for(unsigned i=1;i<512;++i){pick.append(0,0);[table appendString:@"|0,0"];}
    check(pick,table);pick.append(0,0);[table appendString:@"|0,0"];check(pick,table);
    // Count and coordinate failures are deliberately after snapshot/geometry/TTL.
    frame->expiresAtMs=colorClock;check(pick,table);frame->expiresAtMs=colorClock+5000;
    frame->hasBGRA=false;check(pick,table);frame->hasBGRA=true;
    frame->bgra.resize(319);check(pick,table);frame->bgra.resize(320);
    pick.frame.frameId=999;check(pick,table);pick.frame.validCoord=false;check(pick,table);
    pick.frame.frameId=1;pick.frame.validCoord=true;pick.frame.maxAgeMs=5001;check(pick,table);
    pick=TLinkNativeFramePickManyRequest{};pick.frame.frameId=1;pick.append(-1,0);pick.append(1e308,0);check(pick,@"-1,0|1e308,0");
    pick=TLinkNativeFramePickManyRequest{};pick.frame.frameId=1;pick.append(0,0);
    frame->createdAtMs=colorClock-1001;check(pick,@"0,0");pick.frame.maxAgeMs=5000;check(pick,@"0,0");frame->createdAtMs=colorClock-10;
    {TLinkColorRequest first({}),second({});check(pick,@"0,0");}
    {TLinkImageWork first(gImageCompute),second(gImageCompute);check(pick,@"0,0");}
    TLinkNativeFramePickManyValue result;NSError *error=nil;eraseOnSnapshot=true;
    assert(readFramePixels(pick,result,&error)&&gFrameStore.count(1)==0&&result.colors.size()==1);eraseOnSnapshot=false;gFrameStore[1]=frame;
    auto cancel=make_shared<TLinkNativeCancellation>();auto budget=make_shared<TLinkNativeBudget>(cancel,0,4096);cancelOnSnapshot=cancel;
    {TLinkNativeBudgetScope scope(budget);assert(!readFramePixels(pick,result,&error)&&[error.localizedDescription containsString:@"cancelled_or_timed_out"]);}
    cancelOnSnapshot.reset();
    // Both slots must be available again after every failure and held-reader cleanup.
    {TLinkColorRequest first({}),second({});assert(first.admitted()&&second.admitted());}
    {TLinkImageWork first(gImageCompute),second(gImageCompute);assert(first&&second);}
    assert(captures==beforeCapture);frame->createdAtMs=created;frame->expiresAtMs=expires;freezeColorClock=false;
    puts("Numeric frame pick-many Foundation passed: 120 RAW/numeric list cases, 512/513 counts, first failure and snapshot/geometry/TTL precedence, admissions, held-reader/cancel cleanup and no recapture.");
}
static void numericFrameSearchCases(const shared_ptr<ZXFrameObject> &frame){
    const auto created=frame->createdAtMs,expires=frame->expiresAtMs;freezeColorClock=true;
    frame->createdAtMs=colorClock-10;frame->expiresAtMs=colorClock+5000;const unsigned beforeCapture=captures;
    const auto check=[](const TLinkNativeFrameSearchRequest &r){
        NSString *coord=r.frame.validCoord?(r.frame.pointCoord?@"point":@"pixel"):@"typo";
        NSString *wire=[NSString stringWithFormat:@"%d;;search_single;;%.0f;;%.0f;;%.0f;;%.0f;;%d;;%d;;%d;;%d;;%d;;%d;;%d;;%@;;%d",r.frame.frameId,r.x,r.y,r.width,r.height,r.redMin,r.redMax,r.greenMin,r.greenMax,r.blueMin,r.blueMax,r.skip,coord,r.frame.maxAgeMs];
        NSError *rawError=nil,*numericError=nil;NSString *raw=color(wire,&rawError);TLinkNativeFrameSearchValue result;
        const bool ok=searchFrameColor(r,result,&numericError);assert(ok==(raw!=nil));
        if(ok){NSString *expected=[NSString stringWithFormat:@"%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f",result.x,result.y,result.red,result.green,result.blue,(unsigned long long)result.ageMs,result.totalMs,result.totalMs];assert([raw isEqualToString:expected]);}
        else assert([rawError.localizedDescription isEqualToString:numericError.localizedDescription]);
    };
    for(bool point:{false,true})for(double x:{-1e308,-1.5,-0.5,-0.0,0.5,1.5,7.5,2147483646.0,1e308})for(int skip:{0,1,7,1023})for(double width:{-1.0,0.0,3.5}){
        TLinkNativeFrameSearchRequest r;r.frame.frameId=1;r.frame.maxAgeMs=5000;r.frame.pointCoord=point;r.setRegion(x,0.5,width,0);r.skip=skip;
        r.redMin=r.redMax=5;r.greenMin=r.greenMax=3;r.blueMin=r.blueMax=2;check(r);
    }
    TLinkNativeFrameSearchRequest r;r.frame.frameId=1;r.frame.maxAgeMs=5000;check(r);r.redMin=r.redMax=255;check(r);r.redMin=0;r.redMax=255;
    for(int skip:{-1,1024,INT_MAX}){r.skip=skip;check(r);}r.skip=0;
    r.redMax=256;check(r);r.redMax=255;r.greenMin=20;r.greenMax=19;check(r);r.greenMin=0;r.greenMax=255;
    r.frame.frameId=999;check(r);r.frame.validCoord=false;check(r);r.frame.validCoord=true;r.frame.frameId=1;
    r.frame.maxAgeMs=5001;check(r);r.frame.maxAgeMs=5000;
    r.frame.pointCoord=true;r.setRegion(double(INT_MAX)-1,0,0,0);check(r);
    frame->expiresAtMs=colorClock;check(r);frame->expiresAtMs=colorClock+5000;
    frame->hasBGRA=false;check(r);frame->hasBGRA=true;
    frame->bgra.resize(319);check(r);frame->bgra.resize(320);
    r.frame.pointCoord=false;r.setRegion(0,0,0,0);frame->createdAtMs=colorClock-1001;r.frame.maxAgeMs=0;check(r);r.frame.maxAgeMs=5000;check(r);frame->createdAtMs=colorClock-10;
    {TLinkColorRequest first({}),second({});check(r);}
    {TLinkImageWork first(gImageCompute),second(gImageCompute);check(r);}
    TLinkNativeFrameSearchValue result;NSError *error=nil;eraseOnSnapshot=true;
    assert(searchFrameColor(r,result,&error)&&gFrameStore.count(1)==0&&result.x==0);eraseOnSnapshot=false;gFrameStore[1]=frame;
    auto cancel=make_shared<TLinkNativeCancellation>();auto budget=make_shared<TLinkNativeBudget>(cancel,0,4096);cancelOnSnapshot=cancel;
    {TLinkNativeBudgetScope scope(budget);assert(!searchFrameColor(r,result,&error)&&[error.localizedDescription containsString:@"cancelled_or_timed_out"]);}cancelOnSnapshot.reset();
    {TLinkColorRequest first({}),second({});assert(first.admitted()&&second.admitted());}
    {TLinkImageWork first(gImageCompute),second(gImageCompute);assert(first&&second);}
    assert(captures==beforeCapture);frame->createdAtMs=created;frame->expiresAtMs=expires;freezeColorClock=false;
    puts("Numeric frame search Foundation passed: 216 RAW/numeric ROI/scale/skip cases, hit/miss, parameter/frame/TTL/coordinate precedence, admissions, held reader/cancel cleanup and no recapture.");
}
int main(){@autoreleasepool{
    fputs("Frame color/modern image: actual wire handlers, controlled CV/capture and real Foundation/CoreGraphics\n",stderr);
    auto frame=make_shared<ZXFrameObject>();frame->width=8;frame->height=8;frame->bytesPerRow=40;frame->scale=2;
    frame->createdAtMs=zx_nowMs();frame->expiresAtMs=frame->createdAtMs+5000;frame->hasBGRA=true;frame->hasGray=true;frame->gray=Mat(8,8);frame->bgra.resize(320,0);
    for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;frame->bgra[at]=uint8_t(x);frame->bgra[at+1]=uint8_t(y);frame->bgra[at+2]=uint8_t(x+y);}
    gFrameStore[1]=frame;auto templ=make_shared<ZXImageObject>();templ->gray=Mat(2,2);gImageStore[2]=templ;
    NSError *error=nil;NSString *reply=color(@"1;;pick;;2;;3",&error);assert(!error&&[reply hasPrefix:@"5;;3;;2;;"]);
    reply=color(@"1;;pick;;1;;1;;point;;5000",&error);assert(!error&&[reply hasPrefix:@"4;;2;;2;;"]);
    reply=color(@"1;;pick_many;;2,3|1,1",&error);assert(!error&&[reply hasPrefix:@"2,3,5,3,2|1,1,2,1,1;;"]);
    reply=color(@"1;;search_single;;0;;0;;0;;0;;5;;5;;3;;3;;2;;2;;0",&error);assert(!error&&[reply hasPrefix:@"2;;3;;5;;3;;2;;"]);
    reply=color(@"1;;is_colors;;2,,3,,5,,3,,2;;0;;1",&error);assert(!error&&[reply hasPrefix:@"1;;"]);
    // Signed point offset (-1,0) becomes (-2,0), never clamps to zero.
    reply=color(@"1;;find_multi_point;;1;;1;;1;;1;;-1,,0,,2,,2,,0;;0;;1;;0;;point;;5000",&error);
    assert(!error&&[reply hasPrefix:@"2;;2;;"]);
    for(NSString *bad in @[@"1;;pick;;nan;;0",@"1;;pick;;1junk;;0",@"1;;pick;;0;;0;;pixel;;-1",@"1;;pick;;0;;0;;typo",@"1;;pick_many;;1junk,0",@"1;;is_colors;;0,,0,,999,,0,,0;;0;;1",@"1;;search_single;;0;;0;;0;;0;;0;;1;;0;;1;;0;;1;;2147483647"]){error=nil;assert(!color(bad,&error)&&error);}
    NSMutableArray *items=[NSMutableArray array];for(int i=0;i<513;++i)[items addObject:@"0,0"];
    error=nil;assert(!color([@"1;;pick_many;;" stringByAppendingString:[items componentsJoinedByString:@"|"]],&error)&&error);
    frame->bgra.resize(319);error=nil;assert(!color(@"1;;pick;;0;;0",&error)&&error);frame->bgra.resize(320);
    frame->expiresAtMs=zx_nowMs();error=nil;assert(!color(@"1;;pick;;0;;0;;pixel;;5000",&error)&&[error.localizedDescription containsString:@"frame_expired"]);frame->expiresAtMs=zx_nowMs()+5000;
    error=nil;reply=find(@"2;;0;;0;;0;;0;;1;;1;;1;;1;;0",&error);assert(!error&&[reply hasPrefix:@"0;;0;;2;;2;;"]&&captures==1);
    reply=findFrame(@"1;;2;;0;;0;;0;;0;;1;;1;;1;;1;;0",&error);assert(!error&&[reply hasPrefix:@"0;;0;;2;;2;;"]&&captures==1);
    reply=batch(@"1;;img,2,0,0,0,0,1,1,0@@pick_many,2:3|1/1;;pixel;;5000;;0",&error);
    assert(!error&&[reply hasPrefix:@"img:0,0,2,2,"]&&[reply containsString:@"@@pick_many:2,3,5,3,2|1,1,2,1,1,"]);
    for(NSString *bad in @[@"2;;0;;0;;0;;0;;1;;nan;;1;;1;;0",@"2;;0;;0;;0;;0;;1;;.01;;16;;.000001;;0",@"2;;0;;0;;0;;0;;1;;1;;1;;1;;2147483647"]){error=nil;assert(!find(bad,&error)&&error&&captures==1);}
    error=nil;assert(!batch(@"1;;img,2,0,0,0,0,1,0,0",&error)&&error);
    auto cancel=make_shared<TLinkNativeCancellation>();auto parent=make_shared<TLinkNativeBudget>(cancel,0,4096);cancel->cancel();
    {TLinkNativeBudgetScope scope(parent);error=nil;assert(!color(@"1;;pick;;0;;0",&error)&&[error.localizedDescription containsString:@"cancelled_or_timed_out"]);
     error=nil;assert(!batch(@"1;;pick_many,0:0;;pixel;;5000;;1",&error)&&error&&gFrameStore.count(1)==1);}
    assert(TLinkModernImageMemory().stats().total==0);
    numericFramePickCases(frame);
    numericFramePickManyCases(frame);
    numericFrameSearchCases(frame);
    puts("Frame color/modern image Foundation passed: five color modes, signed offsets, strict numbers, padded stride, point scale, TTL, exact replies, batch sharing and pre-cancel cleanup.");
}}
