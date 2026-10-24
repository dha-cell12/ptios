#include "../shared/TLinkNativeTouchRequest.h"
#include "../shared/TLinkNativeColorRequest.h"
#include "../shared/TLinkNativeColorRange.h"
#include "../shared/TLinkNativeColorPoints.h"
#include "../shared/TLinkNativeFramePick.h"
#include "../shared/TLinkNativeFrameSearch.h"
#include "../shared/TLinkNativeFrameColors.h"
#include "../shared/TLinkNativeFrameMulti.h"
#include "../shared/TLinkModernImagePolicy.h"
#include "../shared/TLinkColorPolicy.h"
#include "../shared/TLinkC01Ingress.h"
// Actual bridge, context, response writer and gestures; hardware/task/UI doubles only.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../pccontrol/TLinkTaskContext.h"
#import "../pccontrol/SocketServer.h"
#import "../pccontrol/jsruntime/TLinkJSNativeRequest.h"
#import "../pccontrol/jsruntime/TLinkJSNativeResponse.h"
#include "../shared/TLinkNativeDispatch.h"
#include "../shared/TLinkRawPlayback.h"
#include <cassert>
#include <climits>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <stdexcept>
#include <vector>
static NSString *mode;
static int calls, releases;
static std::string lastPayload;
static TLinkTaskExecutionContext *observed;
NSDictionary *TLinkExecuteNativeTouch(const TLinkNativeTouchRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeTouchBatch(const std::vector<TLinkNativeTouchRequest> &,TLinkTaskExecutionContext *);
static bool zx_handleNativeBatch(UInt8 *,NSError **);
enum {TASK_NATIVE_BATCH=65,TASK_COLOR_PICKER=23,TASK_COLOR_SEARCHER=28,TASK_COLOR_IN_FRAME=69};
NSDictionary *TLinkExecuteNativeColorPick(const TLinkNativeColorPickRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeColorRange(const TLinkNativeColorRangeRequest &,TLinkTaskExecutionContext *);
static void colorRangeLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeColorPoints(const TLinkNativeColorPointsRequest &,TLinkTaskExecutionContext *);
static void colorPointsLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFramePick(const TLinkNativeFramePickRequest &,TLinkTaskExecutionContext *);
NSDictionary *TLinkExecuteNativeFramePickMany(const TLinkNativeFramePickManyRequest &,TLinkTaskExecutionContext *);
static void frameManyLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameSearch(const TLinkNativeFrameSearchRequest &,TLinkTaskExecutionContext *);
static void frameSearchLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameColors(const TLinkNativeFrameColorsRequest &,TLinkTaskExecutionContext *);
static void frameColorsLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
NSDictionary *TLinkExecuteNativeFrameMulti(const TLinkNativeFrameMultiRequest &,TLinkTaskExecutionContext *);
static void frameMultiLegacyTask(UInt8 *,size_t,CFWriteStreamRef);
static void processTaskWithContext(UInt8 *bytes, size_t length, CFWriteStreamRef stream, TLinkTaskExecutionContext *context) {
    ++calls; observed = context;
    lastPayload.assign(reinterpret_cast<char *>(bytes), length);
    assert(bytes[length] == 0 && [context nativeBudget] == TLinkCurrentNativeBudget());
    if (lastPayload.compare(0, 2, "67") == 0 || lastPayload.compare(0, 5, "483;;") == 0 || lastPayload.compare(0, 5, "300;;") == 0) {
        assert([context nativeBudget]->cleanup()); ++releases;
        notifyClient((UInt8 *)"0\r\n", stream); return;
    }
    if ([mode isEqualToString:@"cancelHardwareDown"] && lastPayload == "301;;1") {
        [context.cancellationToken cancel]; notifyClient((UInt8 *)"0\r\n", stream); return;
    }
    if([mode isEqualToString:@"batchRuntime"]&&lastPayload.compare(0,2,"65")==0){
        NSError *error=nil;zx_handleNativeBatch(bytes+2,&error);
        notifyClient((UInt8 *)[(error.localizedDescription?:@"0\r\n") UTF8String],stream);return;
    }
    if([mode isEqualToString:@"frameEncodingOracle"]&&lastPayload.compare(0,2,"69")==0){
        // These probes only use invalid coord tokens; legacy transport decides encoding admission.
        notifyClient((UInt8 *)"1;;invalid_frame_color_parameters\r\n",stream);return;
    }
    if([mode isEqualToString:@"colorPointsRuntime"]&&lastPayload.compare(0,2,"28")==0){colorPointsLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"colorRangeRuntime"]&&lastPayload.compare(0,2,"28")==0){colorRangeLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameManyRuntime"]&&lastPayload.compare(0,2,"69")==0){frameManyLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameSearchRuntime"]&&lastPayload.compare(0,2,"69")==0){frameSearchLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameColorsRuntime"]&&lastPayload.compare(0,2,"69")==0){frameColorsLegacyTask(bytes,length,stream);return;}
    if([mode isEqualToString:@"frameMultiRuntime"]&&lastPayload.compare(0,2,"69")==0){frameMultiLegacyTask(bytes,length,stream);return;}
    if ([mode isEqualToString:@"chunks"]) {
        notifyClient((UInt8 *)"0;;", stream);
        notifyClient((UInt8 *)"12345", stream);
        notifyClient((UInt8 *)"67890", stream); return;
    }
    if ([mode isEqualToString:@"wait"]) {
        assert(!TLinkNativeWaitNs(10000000000ULL));
        notifyClient((UInt8 *)"0\r\n", stream); return;
    }
    if ([mode isEqualToString:@"cancelAllocation"]) {
        [context.cancellationToken cancel]; notifyClient((UInt8 *)"0;;41\r\n", stream); return;
    }
    if ([mode isEqualToString:@"expireAllocation"]) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        notifyClient((UInt8 *)"0;;41\r\n", stream); return;
    }
    if ([mode isEqualToString:@"exception"]) [NSException raise:@"NativeTest" format:@"task throws"];
    notifyClient((UInt8 *)"0;;xin chào\r\n", stream);
}
#include "NativeHelpersUnderTest.inc"
@interface TLinkInProcessNativeBridge : NSObject
- (TLinkJSNativeResponse *)legacyFrameColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyColorRange:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyLiveColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameSearch:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)legacyFrameMany:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context;
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
@end
@implementation TLinkInProcessNativeBridge
#include "NativeBridgeUnderTest.inc"
- (TLinkJSNativeResponse *)legacyFrameMulti:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-multi-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyLiveColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-live-colors-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyColorRange:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-color-range-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameColors:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-colors-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameSearch:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-search-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)legacyFrameMany:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context {
#include "NativeRequestPreludeUnderTest.inc"
    if(false){}
#include "fixtures/native-frame-pick-many-legacy-v1.inc"
    return nil;
}
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error {
#include "NativeRequestPreludeUnderTest.inc"
    if (false) {}
#include "NativePressUnderTest.inc"
#include "NativeTouchBridgeUnderTest.inc"
#include "NativeColorBridgeUnderTest.inc"
#include "NativeColorRangeBridge.inc"
#include "NativeColorPointsBridge.inc"
#include "NativeFramePickBridge.inc"
#include "NativeFrameManyBridge.inc"
#include "NativeFrameSearchBridge.inc"
#include "NativeFrameColorsBridge.inc"
#include "NativeFrameMultiBridge.inc"
#include "NativeBatchBridgeUnderTest.inc"
    else if ([method isEqualToString:TLinkJSNativeMethodHardwareKey]) {
        NSString *payload = [NSString stringWithFormat:@"30%d;;%d", [args[0] intValue], [args[1] intValue]];
        return [TLinkJSNativeResponse responseWithValue:[self executeRawPayload:payload context:context]];
    }
    return nil;
}
@end
@interface Screen : NSObject
+ (CGFloat)getScreenWidth;
+ (CGFloat)getScreenHeight;
@end
@implementation Screen
+ (CGFloat)getScreenWidth { return 500; }
+ (CGFloat)getScreenHeight { return 1000; }
@end
enum { TOUCH_UP = 0, TOUCH_DOWN = 1, TOUCH_MOVE = 2,
       TASK_PERFORM_TOUCH = 10, TASK_NATIVE_TAP = 62, TASK_NATIVE_SWIPE = 63, TASK_NATIVE_GESTURE = 64 };
static std::vector<TLinkTouchPoint> injected;
static TLinkCancellationToken *touchToken;
static int cancelAt;
static int throwAt=0;static bool throwCpp=false;
static bool fakeTiming = false;
static uint64_t fakeNow = 0, frameWork = 0, oversleep = 0;
static unsigned fakeWaits = 0;
static std::vector<uint64_t> frameTimes;
static bool performTouchFrame(const TLinkTouchPoint *points, int count) {
    assert(TLinkValidateTouchFrame(points, count));
    if (fakeTiming) {frameTimes.push_back(fakeNow);fakeNow += frameWork;}
    for (int i = 0; i < count; ++i) injected.push_back(points[i]);
    if (throwAt>0 && int(injected.size())==throwAt) {
        if(throwCpp)throw std::runtime_error("touch test");
        [NSException raise:@"TouchTest" format:@"injection throws"];
    }
    if (cancelAt > 0 && int(injected.size()) >= cancelAt) [touchToken cancel];
    return true;
}
static bool performTouchFromRawData(const UInt8 *bytes, size_t length) {
    TLinkTouchPoint points[kTLinkTouchMaxCount]; int count = 0;
    assert(TLinkParseTouchPayload(bytes, length, points, &count));return performTouchFrame(points, count);
}
static uint64_t touchClockNow(){return fakeTiming ? fakeNow : TLinkNativeNowNs();}
static bool touchWaitNs(uint64_t ns){
    if (!fakeTiming) return TLinkNativeWaitNs(ns);
    ++fakeWaits;fakeNow += ns + oversleep;return !TLinkNativeStopped();
}
// Controlled clock/wait only; compile the actual timeline and gesture bodies.
#define TLinkNativeNowNs touchClockNow
#define TLinkNativeWaitNs touchWaitNs
#include "../shared/TLinkGestureTiming.h"
#include "NativeGesturesUnderTest.inc"
#undef TLinkNativeNowNs
#undef TLinkNativeWaitNs
static bool licenseAllowed=true,stopInLicense=false;
static int licenseCalls=0,lastLicenseTask=0;
static unsigned licenseDelayMs=0;
static TLinkNativeBudgetPtr licenseBudget;
static BOOL TLinkRootfullLicenseTaskAllowed(NSInteger task,NSString **denial){
    ++licenseCalls;lastLicenseTask=int(task);licenseBudget=TLinkCurrentNativeBudget();
    assert(TLinkCurrentNativeBudget() && !TLinkCurrentNativeBudget()->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));
    if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed && denial)*denial=[NSString stringWithFormat:@"-1;;license_required task=%ld\r\n",(long)task];
    return licenseAllowed;
}
static int colorCalls=0,colorFault=0;static bool cancelColor=false;static NSString *colorError=nil;
static TLinkNativeBudgetPtr colorBudget;
static NSDictionary *getRGBAtPosition(int x,int y,NSError **error){
    ++colorCalls;colorBudget=TLinkCurrentNativeBudget();assert(colorBudget&&!colorBudget->capturesResponse());
    if(colorFault==1)[NSException raise:@"ColorFixture" format:@"read throws"];
    if(colorFault==2)throw std::runtime_error("color fixture");
    NSString *code=(x<0||y<0||x>=8192||y>=8192)?@"color_parameters_invalid":colorError;
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return nil;}
    if(cancelColor)[touchToken cancel];
    return @{@"red":@(x%256),@"green":@(y%256),@"blue":@((x+y)%256)};
}
static unsigned colorRangeCalls=0;static int colorRangeFault=0;static bool cancelRange=false;static NSString *colorRangeError=nil;
static TLinkNativeBudgetPtr colorRangeBudget;
static bool colorRangeValues(const TLinkNativeColorRangeRequest &search,TLinkColorResult &value,NSError **error){
    NSString *code=[colorRangeError isEqualToString:@"color_compute_busy"]?colorRangeError:(TLinkNativeColorRangeParameters(search)?colorRangeError:@"color_parameters_invalid");
    TLinkColorRect region;
    if(!code&&!TLinkColorRegion(8,6,search.x,search.y,search.width,search.height,false,region))code=@"color_region_invalid";
    if(!code){
        std::vector<uint8_t> rgba(size_t(region.width)*region.height*4);for(size_t i=0;i<rgba.size();i+=4){rgba[i]=10;rgba[i+1]=20;rgba[i+2]=30;rgba[i+3]=255;}
        const TLinkColorPoint low={0,0,search.redMin,search.greenMin,search.blueMin},high={0,0,search.redMax,search.greenMax,search.blueMax};
        TLinkColorRequest work(TLinkCurrentNativeBudget());const auto status=TLinkColorRangeScan(rgba.data(),region.width,region.height,search.skip,low,high,work,value);
        if(status==TLinkColorScan::Stopped)code=@"color_cancelled_or_timed_out";
        else if(status==TLinkColorScan::NoMatch)value.x=value.y=value.r=value.g=value.b=-1;
        else {value.x+=region.x;value.y+=region.y;}
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}
    return true;
}
static bool searchRGBRange(const TLinkNativeColorRangeRequest &search,TLinkColorResult &value,NSError **error){
    ++colorRangeCalls;colorRangeBudget=TLinkCurrentNativeBudget();assert(colorRangeBudget&&!colorRangeBudget->capturesResponse());
    if(colorRangeFault==1)[NSException raise:@"ColorRangeFixture" format:@"range throws"];
    if(colorRangeFault==2)throw std::runtime_error("color range fixture");
    const bool ok=colorRangeValues(search,value,error);if(cancelRange)[touchToken cancel];return ok;
}
static void colorRangeLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];
    assert(fields.count==12&&[fields[0] isEqualToString:@"1"]);int numbers[11]={};bool valid=true;
    for(unsigned i=0;i<11;++i){const bool parsed=TLinkColorInt([fields[i+1] UTF8String],numbers[i]);valid=valid&&parsed;}
    TLinkNativeColorRangeRequest r;r.x=numbers[0];r.y=numbers[1];r.width=numbers[2];r.height=numbers[3];r.redMin=numbers[4];r.redMax=numbers[5];r.greenMin=numbers[6];r.greenMax=numbers[7];r.blueMin=numbers[8];r.blueMax=numbers[9];r.skip=numbers[10];r.coordinatesValid=valid;
    TLinkColorResult value;NSError *error=nil;
    if(!colorRangeValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%d;;%d;;%d\r\n",value.x,value.y,value.r,value.g,value.b];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned colorPointsCalls=0;static int colorPointsFault=0;static bool cancelColorPoints=false;static NSString *colorPointsError=nil;
static TLinkNativeBudgetPtr colorPointsBudget;
static bool colorPointsValues(const TLinkNativeColorPointsRequest &check,bool &matched,NSError **error){
    NSString *code=[colorPointsError isEqualToString:@"color_compute_busy"]?colorPointsError:(TLinkNativeColorPointsParameters(check)?nil:@"color_parameters_invalid");
    if(!code){if(const char *tableError=TLinkNativeColorPointsTableError(check))code=[NSString stringWithUTF8String:tableError];}
    TLinkColorRect crop;
    if(!code&&!TLinkNativeColorPointsBounds(check.points,8192,8192,crop))code=@"color_point_out_of_bounds";
    if(!code)code=colorPointsError;
    if(!code&&!TLinkNativeColorPointsBounds(check.points,8,6,crop))code=@"color_point_out_of_bounds";
    if(!code){
        std::vector<uint8_t> rgba(size_t(crop.width)*crop.height*4);for(size_t i=0;i<rgba.size();i+=4){rgba[i]=10;rgba[i+1]=20;rgba[i+2]=30;rgba[i+3]=255;}
        TLinkColorRequest work(TLinkCurrentNativeBudget());if(!TLinkNativeColorPointsCompare(rgba.data(),crop.width,crop,check.points,check.mode,check.tolerance,work,matched))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n",code]}];return false;}
    return true;
}
static bool testRGBPoints(const TLinkNativeColorPointsRequest &check,bool &matched,NSError **error){
    ++colorPointsCalls;colorPointsBudget=TLinkCurrentNativeBudget();assert(colorPointsBudget&&!colorPointsBudget->capturesResponse());
    if(colorPointsFault==1)[NSException raise:@"ColorPointsFixture" format:@"compare throws"];
    if(colorPointsFault==2)throw std::runtime_error("color points fixture");
    const bool ok=colorPointsValues(check,matched,error);if(cancelColorPoints)[touchToken cancel];return ok;
}
static void colorPointsLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];NSArray *fields=[payload componentsSeparatedByString:@";;"];
    assert(fields.count==4&&[fields[0] isEqualToString:@"2"]);TLinkNativeColorPointsRequest r;r.mode=[fields[2] intValue];r.toleranceUnits=[fields[3] length];r.toleranceValid=TLinkColorDouble([fields[3] UTF8String],r.tolerance);
    NSString *table=fields[1];r.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.tableValid=r.tableValid&&valid;r.points.push_back(point);
    }
    bool matched=false;NSError *error=nil;if(!colorPointsValues(r,matched,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d\r\n",matched?1:0];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameReads=0;static int frameReadFault=0;static bool cancelFrameRead=false;static NSString *frameReadError=nil;
static TLinkNativeBudgetPtr frameBudget;static TLinkNativeFramePickRequest observedFramePick;
static bool readFramePixel(const TLinkNativeFramePickRequest &pick,TLinkNativeFramePickValue &value,NSError **error){
    ++frameReads;observedFramePick=pick;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame fixture");
    NSString *code=TLinkFramePickParameters(pick)?frameReadError:@"invalid_frame_color_parameters";
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    if(cancelFrameRead)[touchToken cancel];
    value.red=1;value.green=2;value.blue=3;value.ageMs=7;value.totalMs=1.23456;return true;
}
static unsigned frameManyReads=0;static TLinkNativeFramePickManyRequest observedFrameMany;
static bool frameManyValues(const TLinkNativeFramePickManyRequest &pick,TLinkNativeFramePickManyValue &value,NSError **error){
    NSString *code=TLinkFramePickParameters(pick.frame)?frameReadError:@"invalid_frame_color_parameters";
    if(!code&&(pick.pointCount>512||pick.tableUnits>32768))code=@"point_table_limit";
    if(!code){for(const auto &point:pick.points){
        TLinkNativeFrameColor pixel;
        if(!TLinkFrameColorCoordinate(point.x,2,pick.frame.pointCoord,pixel.x)||!TLinkFrameColorCoordinate(point.y,2,pick.frame.pointCoord,pixel.y)){code=@"invalid_pick_many_point";break;}
        if(pixel.x<0||pixel.y<0||pixel.x>=8192||pixel.y>=8192){code=@"point_out_of_bounds";break;}
        pixel.red=pixel.x%256;pixel.green=pixel.y%256;pixel.blue=3;value.colors.push_back(pixel);
    }}
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool readFramePixels(const TLinkNativeFramePickManyRequest &pick,TLinkNativeFramePickManyValue &value,NSError **error){
    ++frameManyReads;observedFrameMany=pick;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameManyFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame many fixture");
    const bool ok=frameManyValues(pick,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameManyLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==5&&[fields[1] isEqualToString:@"pick_many"]);
    TLinkNativeFramePickManyRequest pick;pick.frame.frameId=[fields[0] intValue];pick.frame.maxAgeMs=[fields[4] intValue];
    NSString *coord=[fields[3] lowercaseString];pick.frame.pointCoord=[coord isEqualToString:@"point"];pick.frame.validCoord=pick.frame.pointCoord||[coord isEqualToString:@"pixel"];
    for(NSString *item in [fields[2] componentsSeparatedByString:@"|"]){NSArray *xy=[item componentsSeparatedByString:@","];assert(xy.count==2);pick.append([xy[0] doubleValue],[xy[1] doubleValue]);}
    TLinkNativeFramePickManyValue value;NSError *error=nil;
    if(!frameManyValues(pick,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSMutableArray *rows=[NSMutableArray array];for(const auto &pixel:value.colors)[rows addObject:[NSString stringWithFormat:@"%d,%d,%d,%d,%d",pixel.x,pixel.y,pixel.red,pixel.green,pixel.blue]];
    NSString *raw=[NSString stringWithFormat:@"0;;%@;;%llu;;%.3f;;%.3f\r\n",[rows componentsJoinedByString:@"|"],(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
    notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameSearchReads=0;
static bool frameSearchValues(const TLinkNativeFrameSearchRequest &search,TLinkNativeFrameSearchValue &value,NSError **error){
    NSString *code=TLinkFrameSearchParameters(search)?frameReadError:@"invalid_frame_color_parameters";
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});const auto status=TLinkFrameSearchScan(bgra.data(),8,8,40,2,search,work,value);
        if(status==TLinkFrameSearchStatus::CoordinateInvalid)code=@"frame_coordinate_invalid";
        if(status==TLinkFrameSearchStatus::Stopped)code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool searchFrameColor(const TLinkNativeFrameSearchRequest &search,TLinkNativeFrameSearchValue &value,NSError **error){
    ++frameSearchReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameSearchFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame search fixture");
    const bool ok=frameSearchValues(search,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameSearchLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==15&&[fields[1] isEqualToString:@"search_single"]);
    TLinkNativeFrameSearchRequest r;r.frame.frameId=[fields[0] intValue];r.frame.maxAgeMs=[fields[14] intValue];
    NSString *coord=[fields[13] lowercaseString];r.frame.pointCoord=[coord isEqualToString:@"point"];r.frame.validCoord=r.frame.pointCoord||[coord isEqualToString:@"pixel"];
    r.x=[fields[2] doubleValue];r.y=[fields[3] doubleValue];r.width=[fields[4] doubleValue];r.height=[fields[5] doubleValue];
    r.redMin=[fields[6] intValue];r.redMax=[fields[7] intValue];r.greenMin=[fields[8] intValue];r.greenMax=[fields[9] intValue];r.blueMin=[fields[10] intValue];r.blueMax=[fields[11] intValue];r.skip=[fields[12] intValue];
    TLinkNativeFrameSearchValue value;NSError *error=nil;
    if(!frameSearchValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%d;;%d;;%d;;%llu;;%.3f;;%.3f\r\n",value.x,value.y,value.red,value.green,value.blue,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];
    notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameColorsReads=0;
static bool frameColorsValues(const TLinkNativeFrameColorsRequest &check,TLinkNativeFrameColorsValue &value,NSError **error){
    NSString *code=TLinkFrameColorsParameters(check)?frameReadError:@"invalid_frame_color_parameters";
    if(!code){if(const char *tableError=TLinkFrameColorsTableError(check))code=[NSString stringWithUTF8String:tableError];}
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});if(!TLinkFrameColorsEvaluate(bgra.data(),8,8,40,2,check.points,check.frame.pointCoord,check.mode,check.tolerance,work,value.matched))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool testFrameColors(const TLinkNativeFrameColorsRequest &check,TLinkNativeFrameColorsValue &value,NSError **error){
    ++frameColorsReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameColorsFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame colors fixture");
    const bool ok=frameColorsValues(check,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameColorsLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==7&&[fields[1] isEqualToString:@"is_colors"]);
    TLinkNativeFrameColorsRequest r;r.frame.frameId=[fields[0] intValue];r.frame.maxAgeMs=[fields[6] intValue];r.mode=[fields[3] intValue];
    r.toleranceValid=TLinkColorDouble([fields[4] UTF8String],r.tolerance);r.toleranceUnits=[fields[4] length];
    NSString *coord=[fields[5] lowercaseString];r.frame.pointCoord=[coord isEqualToString:@"point"];r.frame.validCoord=r.frame.pointCoord||[coord isEqualToString:@"pixel"];
    NSString *table=fields[2];r.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.tableValid=r.tableValid&&valid;r.points.push_back(point);
    }
    TLinkNativeFrameColorsValue value;NSError *error=nil;
    if(!frameColorsValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%llu;;%.3f;;%.3f\r\n",value.matched?1:0,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];notifyClient((UInt8 *)raw.UTF8String,stream);
}
static unsigned frameMultiReads=0;
static bool frameMultiValues(const TLinkNativeFrameMultiRequest &search,TLinkNativeFrameMultiValue &value,NSError **error){
    NSString *code=TLinkFrameMultiParameters(search)?frameReadError:@"invalid_frame_color_parameters";TLinkColorRect region;
    if(!code&&!TLinkFrameMultiRegion(8,8,2,search,region))code=@"frame_coordinate_invalid";
    if(!code){if(const char *tableError=TLinkFrameColorsTableError(search.colors))code=[NSString stringWithUTF8String:tableError];}
    auto points=search.colors.points;
    if(!code&&!TLinkFrameMultiOffsets(points,2,search.colors.frame.pointCoord))code=@"frame_coordinate_invalid";
    if(!code){
        std::vector<uint8_t> bgra(40*8,0xee);for(int y=0;y<8;++y)for(int x=0;x<8;++x){size_t at=size_t(y)*40+size_t(x)*4;bgra[at]=uint8_t(x);bgra[at+1]=uint8_t(y);bgra[at+2]=uint8_t(x+y);}
        TLinkColorRequest work({});if(!TLinkFrameMultiScan(bgra.data(),8,8,40,region,points,search.colors.mode,search.colors.tolerance,search.skip,work,value))code=@"color_cancelled_or_timed_out";
    }
    if(code){if(error)*error=[NSError errorWithDomain:@"fixture" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"1;;%@\r\n",code]}];return false;}
    value.ageMs=7;value.totalMs=1.23456;return true;
}
static bool findFrameColors(const TLinkNativeFrameMultiRequest &search,TLinkNativeFrameMultiValue &value,NSError **error){
    ++frameMultiReads;frameBudget=TLinkCurrentNativeBudget();assert(frameBudget&&!frameBudget->capturesResponse());
    if(frameReadFault==1)[NSException raise:@"FrameMultiFixture" format:@"read throws"];
    if(frameReadFault==2)throw std::runtime_error("frame multi fixture");
    const bool ok=frameMultiValues(search,value,error);if(cancelFrameRead)[touchToken cancel];return ok;
}
static void frameMultiLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef stream){
    NSString *payload=[[NSString alloc] initWithBytes:bytes+2 length:length-2 encoding:NSUTF8StringEncoding];
    NSArray *fields=[payload componentsSeparatedByString:@";;"];assert(fields.count==12&&[fields[1] isEqualToString:@"find_multi_point"]);
    TLinkNativeFrameMultiRequest r;r.colors.frame.frameId=[fields[0] intValue];r.colors.frame.maxAgeMs=[fields[11] intValue];r.colors.mode=[fields[7] intValue];r.skip=[fields[9] intValue];
    r.x=[fields[2] doubleValue];r.y=[fields[3] doubleValue];r.width=[fields[4] doubleValue];r.height=[fields[5] doubleValue];
    r.colors.toleranceValid=TLinkColorDouble([fields[8] UTF8String],r.colors.tolerance);r.colors.toleranceUnits=[fields[8] length];
    NSString *coord=[fields[10] lowercaseString];r.colors.frame.pointCoord=[coord isEqualToString:@"point"];r.colors.frame.validCoord=r.colors.frame.pointCoord||[coord isEqualToString:@"pixel"];
    NSString *table=fields[6];r.colors.tableUnits=table.length;NSArray *rows=[table componentsSeparatedByString:@"|"];r.colors.pointCount=rows.count;
    for(NSString *row in rows){NSArray *parts=[row componentsSeparatedByString:@",,"];assert(parts.count==5);TLinkColorPoint point={};
        const bool valid=TLinkColorInt([parts[0] UTF8String],point.dx)&&TLinkColorInt([parts[1] UTF8String],point.dy)&&TLinkColorInt([parts[2] UTF8String],point.r)&&TLinkColorInt([parts[3] UTF8String],point.g)&&TLinkColorInt([parts[4] UTF8String],point.b)&&TLinkColorRGB(point.r)&&TLinkColorRGB(point.g)&&TLinkColorRGB(point.b);
        r.colors.tableValid=r.colors.tableValid&&valid;r.colors.points.push_back(point);
    }
    TLinkNativeFrameMultiValue value;NSError *error=nil;
    if(!frameMultiValues(r,value,&error)){notifyClient((UInt8 *)error.localizedDescription.UTF8String,stream);return;}
    NSString *raw=[NSString stringWithFormat:@"0;;%d;;%d;;%llu;;%.3f;;%.3f\r\n",value.x,value.y,(unsigned long long)value.ageMs,value.totalMs,value.totalMs];notifyClient((UInt8 *)raw.UTF8String,stream);
}
// Match Image.h: OpenCV leaves these macros undefined in production Task.xm.
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeTouchEntryUnderTest.inc"
#include "NativeColorEntryUnderTest.inc"
#include "NativeColorRangeEntry.inc"
#include "NativeColorPointsEntry.inc"
#include "NativeFramePickEntry.inc"
#include "NativeFrameManyEntry.inc"
#include "NativeFrameSearchEntry.inc"
#include "NativeFrameColorsEntry.inc"
#include "NativeFrameMultiEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static TLinkTaskExecutionContext *parent(double timeout = 1, NSUInteger cap = 1024 * 1024) {
    auto context = [TLinkTaskExecutionContext new];
    context.cancellationToken = [TLinkCancellationToken new];
    context.defaultTimeoutSeconds = timeout; context.defaultMaxOutputBytes = cap;
    context.ownerSessionId = @"session"; context.ownerRunId = @"run"; context.ownerRuntime = @"test";
    return context;
}
static void failure(NSDictionary *result, NSString *code, unsigned callerLine = __builtin_LINE()) {
    NSArray *parts=result[@"parts"];
    const bool matches=![result[@"ok"] boolValue]&&parts.count>1&&[parts[1] isEqualToString:code];
    if(!matches)std::fprintf(stderr,"native bridge failure at line %u: expected %s, received %s\n",callerLine,code.UTF8String ?: "(nil)",[[result description] UTF8String] ?: "(nil)");
    assert(matches);
}
static void checkGesture(bool (*handler)(UInt8 *, NSError **), NSString *payload, int fingerCount, int cancelAfter) {
    injected.clear(); touchToken = [TLinkCancellationToken new]; cancelAt = cancelAfter;
    auto context = parent(); context.cancellationToken = touchToken;
    auto call = TLinkNativeCallContext(context, NO, NO);
    TLinkNativeBudgetScope scope([call nativeBudget]);
    NSError *error = nil;
    assert(!handler((UInt8 *)payload.UTF8String, &error) && error);
    assert([error.localizedDescription containsString:@"AbortError"]);
    assert(injected.size() >= size_t(fingerCount * 2));
    for (int i = 0; i < fingerCount; ++i) {
        assert(injected[size_t(i)].type == TOUCH_DOWN);
        assert(injected[injected.size() - size_t(i) - 1].type == TOUCH_UP);
    }
    const auto count = injected.size();
    assert(!handler((UInt8 *)payload.UTF8String, &error) && injected.size() == count);
}
static void timingCases() {
    fakeTiming = true;
    const auto run = [](bool (*handler)(UInt8 *, NSError **), const char *payload, uint64_t work = 7000000) {
        injected.clear();frameTimes.clear();touchToken = nil;cancelAt = 0;
        fakeNow = 1000000;frameWork = work;oversleep = 2000000;fakeWaits = 0;
        TLinkNativeBudgetScope scope([TLinkNativeCallContext(parent(), NO, NO) nativeBudget]);
        NSError *error = nil;assert(handler((UInt8 *)payload, &error) && !error);
    };
    run(zx_handleNativeTap, "20;;30;;100;;19");
    assert(frameTimes.size() == 2 && frameTimes[0] == 1000000 && frameTimes[1] == 103000000);
    run(zx_handleNativeSwipe, "20;;30;;80;;90;;100;;19;;10");
    assert(frameTimes.size() == 11 && frameTimes[0] == 1000000);
    for (unsigned i = 1; i <= 10; ++i) assert(frameTimes[i] == 3000000 + uint64_t(i) * 10000000);
    assert(injected.back().type == TOUCH_UP && injected.back().x == 80 && injected.back().y == 90);
    run(zx_handleNativeGesture, "19;;90;;20,30|40,50|60,70|80,90");
    assert(frameTimes.size() == 5 && frameTimes[0] == 1000000 && frameTimes[1] == 33000000 && frameTimes[2] == 63000000 &&
        frameTimes[3] == 93000000 && frameTimes[4] == 100000000);
    run(zx_handleNativeGesture, "zoom;;250;;500;;20;;80;;90;;3;;4");
    assert(frameTimes.size() == 5 && frameTimes[1] == 33000000 && frameTimes[2] == 63000000 && frameTimes[3] == 93000000 && frameTimes[4] == 100000000);
    assert(injected.size() == 15); // all three fingers in DOWN, three MOVEs and UP
    run(zx_handleNativeSwipe, "20;;30;;80;;90;;100;;19;;10", 40000000);
    assert(fakeWaits == 0 && frameTimes.size() == 11);
    for (unsigned i = 0; i <= 10; ++i) assert(frameTimes[i] == 1000000 + uint64_t(i) * 40000000);
    // Last-point cancellation must still return failure and issue owned UP.
    checkGesture(zx_handleNativeGesture, @"19;;0;;20,30|40,50", 1, 2);
    checkGesture(zx_handleNativeGesture, @"zoom;;250;;500;;20;;80;;50;;2;;2", 2, 4);
    fakeTiming = false;touchToken = nil;cancelAt = 0;injected.clear();
    // Concrete old fixed-point boundaries, including finite clamping.
    zx_performSingleTouch(TOUCH_DOWN, 19, -1, 0.95);
    assert(injected.back().index == 19 && injected.back().x == 0 && injected.back().y == 1);
    zx_performSingleTouch(TOUCH_UP, 19, 1e30, 9999.89);
    assert(injected.back().x == 9999 && injected.back().y == 9999);
    puts("Actual gesture timing passed: typed frames, consumed DOWN/work/oversleep, scheduled final point, ordered overdue frames, exact endpoint and final-frame cancellation cleanup.");
}
static void typedTouchCases(TLinkInProcessNativeBridge *bridge) {
    const int wireCalls=calls;
    const auto resetTouch=[](TLinkTaskExecutionContext *context){
        injected.clear();frameTimes.clear();fakeNow=1000000;frameWork=7000000;oversleep=2000000;fakeWaits=0;
        touchToken=context.cancellationToken;cancelAt=0;throwAt=0;licenseAllowed=true;stopInLicense=false;
    };
    const auto invoke=[bridge](NSString *method,NSArray *args,TLinkTaskExecutionContext *context)->NSDictionary *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:method arguments:args];
        auto response=[bridge executeRequest:request context:context error:nil];
        assert(response.ok && !TLinkCurrentNativeBudget());return response.value;
    };
    fakeTiming=true;
    // Compare actual new bridge branches with the old NSString encoder plus
    // actual RAW adapter/executor, including rounding and floatValue boundaries.
    for(unsigned trial=0;trial<160;++trial){
        const double x=trial<8?std::vector<double>{-1e308,-0.005,0.945,0.95,1.005,9999.89,1e30,1e308}[trial]:double(trial)*123.4567-500;
        const double y=double(trial)*0.00495+0.945;
        const bool swipe=trial%3==1,longPress=trial%3==2;
        NSString *method=swipe?TLinkJSNativeMethodSwipe:(longPress?TLinkJSNativeMethodLongPress:TLinkJSNativeMethodTap);
        const double duration=double(trial%17)+0.5;
        NSArray *args=swipe?@[@(x),@(y),@75.125,@87.955,@(duration)]:(longPress?@[@(x),@(y),@(duration)]:@[@(x),@(y)]);
        auto context=parent();resetTouch(context);
        NSDictionary *result=invoke(method,args,context);
        const auto expectedPoints=injected;const auto expectedTimes=frameTimes;
        assert(lastLicenseTask==(swipe?63:62) && licenseBudget->response().empty() && licenseBudget->response().capacity()==0);
        resetTouch(context);NSError *error=nil;
        NSString *wire=swipe?[NSString stringWithFormat:@"%.2f;;%.2f;;%.2f;;%.2f;;%.0f",x,y,75.125,87.955,duration]:
            (longPress?[NSString stringWithFormat:@"%.2f;;%.2f;;%.0f",x,y,duration]:[NSString stringWithFormat:@"%.2f;;%.2f",x,y]);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);
         if(swipe)zx_handleNativeSwipe((UInt8 *)wire.UTF8String,&error);else zx_handleNativeTap((UInt8 *)wire.UTF8String,&error);}
        NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw] && [result[@"ok"] boolValue]==(error==nil));
        assert(expectedPoints.size()==injected.size() && expectedTimes==frameTimes);
        for(size_t j=0;j<injected.size();++j)assert(injected[j].type==expectedPoints[j].type&&injected[j].index==expectedPoints[j].index&&
            injected[j].x==expectedPoints[j].x&&injected[j].y==expectedPoints[j].y);
    }
    const auto zoomState=[](){return std::vector<uint64_t>{
        sTLinkZoomAttemptCount.load(),sTLinkZoomSuccessCount.load(),sTLinkZoomValidationRejectedCount.load(),
        sTLinkZoomDispatchExceptionCount.load(),sTLinkZoomCleanupCount.load(),sTLinkZoomCancelledCount.load(),sTLinkZoomFrameCount.load(),
        uint64_t(sTLinkZoomLastResult.load()),uint64_t(sTLinkZoomLastDirection.load()),uint64_t(sTLinkZoomLastFingerCount.load()),
        uint64_t(sTLinkZoomLastSteps.load()),uint64_t(sTLinkZoomLastDurationMs.load())};};
    const auto parity=[&](NSString *method,NSArray *args,NSString *wire){
        auto context=parent(30);resetTouch(context);const int gatesBefore=licenseCalls;
        const auto before=zoomState();NSDictionary *result=invoke(method,args,context);const auto after=zoomState();
        const auto expectedPoints=injected;const auto expectedTimes=frameTimes;
        if(wire.length+2>8192){failure(result,@"input_too_large");assert(injected.empty()&&licenseCalls==gatesBefore);return;}
        assert(lastLicenseTask==64 && licenseCalls==gatesBefore+1 && licenseBudget->response().capacity()==0);
        resetTouch(context);NSError *error=nil;const auto rawBefore=zoomState();
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);zx_handleNativeGesture((UInt8 *)wire.UTF8String,&error);}
        const auto rawAfter=zoomState();NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw]&&[result[@"ok"] boolValue]==(error==nil));
        assert([result[@"parts"] isEqualToArray:[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert(expectedPoints.size()==injected.size()&&expectedTimes==frameTimes);
        for(size_t j=0;j<injected.size();++j)assert(injected[j].type==expectedPoints[j].type&&injected[j].index==expectedPoints[j].index&&injected[j].x==expectedPoints[j].x&&injected[j].y==expectedPoints[j].y);
        for(size_t j=0;j<after.size();++j)assert(j<7?after[j]-before[j]==rawAfter[j]-rawBefore[j]:after[j]==rawAfter[j]);
    };
    const auto gesture=[&](NSArray *points,NSDictionary *options){
        NSString *encoded=TLinkautoJSEncodeGesturePoints(points);assert(encoded);
        const int finger=TLinkautoJSIntOption(options,@"finger",0);
        int duration=TLinkautoJSIntOption(options,@"duration",TLinkautoJSIntOption(options,@"durationMs",300));
        if(duration<0)duration=0;if(duration>60000)duration=60000;
        NSString *wire=[NSString stringWithFormat:@"%d;;%d;;%@",finger,duration,encoded];
        parity(TLinkJSNativeMethodGesture,@[points,options],wire);
    };
    for(unsigned trial=0;trial<80;++trial){
        NSMutableArray *points=[NSMutableArray array];
        for(unsigned j=0;j<2+trial%9;++j){double x=double(trial)*1.005+double(j)*0.945,y=double(j)*10.005-1;
            [points addObject:j%2?@{@"x":@(x),@"y":@(y)}:@[@(x),@(y)]];}
        gesture(points,@{@"durationMs":@(trial%31),@"finger":@(trial%2?19:0)});
    }
    gesture(@[@{@"y":@20},@[@40.945,@50.005]],@{});
    gesture(@[@[@1e308,@20],@[@30,@40]],@{@"duration":@0});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"finger":@20,@"duration":@0});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"duration":@-10});
    gesture(@[@[@20,@30],@[@40,@50]],@{@"duration":@60001});
    NSMutableArray *many=[NSMutableArray array];for(unsigned j=0;j<512;++j)[many addObject:@[@1234.56,@5678.90]];
    many[0]=@[@0,@0];many[1]=@[@12.56,@5678.90];
    assert(TLinkautoJSEncodeGesturePoints(many).length+9==8192);gesture(many,@{@"finger":@19,@"duration":@0});
    many[1]=@[@123.56,@5678.90];assert(TLinkautoJSEncodeGesturePoints(many).length+9==8193);gesture(many,@{@"finger":@19,@"duration":@0});
    const auto zoom=[&](double x,double y,double first,double last,NSDictionary *options){
        int duration=TLinkautoJSIntOption(options,@"durationMs",300),fingers=TLinkautoJSIntOption(options,@"fingerCount",2),steps=TLinkautoJSIntOption(options,@"steps",20),finger=TLinkautoJSIntOption(options,@"baseFinger",0);
        double angle=TLinkautoJSDoubleOption(options,@"angleDegrees",0.0);
        NSString *wire=[NSString stringWithFormat:@"zoom;;%.2f;;%.2f;;%.2f;;%.2f;;%d;;%d;;%d;;%.2f;;%d",x,y,first,last,duration,fingers,steps,angle,finger];
        parity(TLinkJSNativeMethodZoom,@[@(x),@(y),@(first),@(last),options],wire);
    };
    for(unsigned trial=0;trial<40;++trial)zoom(250.005,500.945,20.125,80.955,@{@"durationMs":@(50+trial*10),@"steps":@(2+trial%9),@"fingerCount":@(2+trial%2),@"angleDegrees":@(double(trial)*7.125-140),@"baseFinger":@(trial%2?17:18)});
    zoom(250,500,20,80,@{});zoom(250,500,80,20,@{@"fingerCount":@3,@"steps":@120,@"durationMs":@5000});
    for(NSDictionary *bad in @[@{@"durationMs":@49},@{@"durationMs":@5001},@{@"fingerCount":@1},@{@"fingerCount":@4},@{@"steps":@1},@{@"steps":@121},@{@"angleDegrees":@361},@{@"angleDegrees":@(NAN)},@{@"angleDegrees":@(INFINITY)},@{@"baseFinger":@-1},@{@"baseFinger":@(INT_MAX)},@{@"baseFinger":@19}])zoom(250,500,20,80,bad);
    zoom(250,500,0,80,@{});zoom(250,500,20,20,@{});zoom(0,500,20,80,@{});
    auto context=parent();resetTouch(context);licenseAllowed=false;

    NSDictionary *result=invoke(TLinkJSNativeMethodTap,@[@20,@30],context);
    assert(![result[@"ok"] boolValue] && [result[@"raw"] isEqualToString:@"-1;;license_required task=62\r\n"] && injected.empty());
    context=parent();resetTouch(context);stopInLicense=true;
    failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"AbortError");assert(injected.empty());
    context=parent();resetTouch(context);[context.cancellationToken cancel];const int gates=licenseCalls;
    failure(invoke(TLinkJSNativeMethodSwipe,@[@20,@30,@80,@90,@500],context),@"AbortError");assert(injected.empty()&&licenseCalls==gates);
    context=parent();resetTouch(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,1024)];
    failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"TimeoutError");assert(injected.empty()&&licenseCalls==gates);
    context=parent();resetTouch(context);cancelAt=1;
    failure(invoke(TLinkJSNativeMethodLongPress,@[@20,@30,@60000],context),@"AbortError");
    assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    for(bool cpp:{false,true}){
        context=parent();resetTouch(context);throwAt=1;throwCpp=cpp;
        failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"native_exception");
        assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    }
    for(NSString *method:@[TLinkJSNativeMethodGesture,TLinkJSNativeMethodZoom]){
        NSArray *args=[method isEqualToString:TLinkJSNativeMethodZoom]?@[@250,@500,@20,@80,@{@"durationMs":@50,@"steps":@2,@"fingerCount":@3}]:@[@[@[@20,@30],@[@40,@50]],@{@"duration":@0,@"finger":@19}];
        context=parent();resetTouch(context);licenseAllowed=false;NSDictionary *denied=invoke(method,args,context);
        assert(![denied[@"ok"] boolValue]&&lastLicenseTask==64&&injected.empty());
        context=parent();resetTouch(context);stopInLicense=true;failure(invoke(method,args,context),@"AbortError");assert(injected.empty());
        context=parent();resetTouch(context);cancelAt=[method isEqualToString:TLinkJSNativeMethodZoom]?3:1;
        failure(invoke(method,args,context),@"AbortError");
        const size_t fingers=[method isEqualToString:TLinkJSNativeMethodZoom]?3:1;
        assert(injected.size()==fingers*2);for(size_t j=0;j<fingers;++j)assert(injected[injected.size()-1-j].type==TOUCH_UP);
        for(bool cpp:{false,true}){context=parent();resetTouch(context);throwAt=int(fingers*2);throwCpp=cpp;
            NSDictionary *thrown=invoke(method,args,context);assert(![thrown[@"ok"] boolValue]);
            if(!cpp&&fingers==3)assert([thrown[@"raw"] containsString:@"zoom_dispatch_exception"]);else failure(thrown,@"native_exception");
            assert(injected.size()==fingers*3);for(size_t j=0;j<fingers;++j)assert(injected[injected.size()-1-j].type==TOUCH_UP);
        }
    }
    context=parent();resetTouch(context);const int noGate=licenseCalls;
    auto malformed=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodGesture arguments:@[@[@[@1]],@{}]];
    assert(![bridge executeRequest:malformed context:context error:nil].ok&&injected.empty()&&licenseCalls==noGate);
    context=parent(1,3);resetTouch(context);assert([invoke(TLinkJSNativeMethodTap,@[@20,@30],context)[@"ok"] boolValue]);
    context=parent(1,2);resetTouch(context);failure(invoke(TLinkJSNativeMethodTap,@[@20,@30],context),@"response_too_large");
    assert(injected.size()==2&&injected.back().type==TOUCH_UP);
    context=parent();resetTouch(context);TLinkNativeTouchRequest invalid;invalid.finger=20;
    result=TLinkExecuteNativeTouch(invalid,context);assert(![result[@"ok"] boolValue]&&injected.empty());
    invalid.kind=static_cast<TLinkNativeTouchKind>(9);const int previous=licenseCalls;
    failure(TLinkExecuteNativeTouch(invalid,context),@"invalid_touch_request");assert(injected.empty()&&licenseCalls==previous);
    fakeTiming=false;context=parent(0.01);resetTouch(context);
    failure(invoke(TLinkJSNativeMethodLongPress,@[@20,@30,@60000],context),@"TimeoutError");
    assert(injected.size()==2 && injected.back().type==TOUCH_UP);
    assert(calls==wireCalls && !TLinkCurrentNativeBudget());licenseBudget.reset();touchToken=nil;cancelAt=0;
    puts("Typed touch actual bridge/entry passed: 160 legacy-wire/frame/timestamp cases, typed gesture/zoom wire/frame/timestamp/diagnostic parity, 8192/8193-byte ingress, task 62/63/64 gates, gate-time cancellation, pre-expiry, output caps, NS/C++ exceptions, owned UP, no raw dispatch or response-buffer allocation.");
}
// Frozen pre-C02b3 object encoder plus the production RAW task-65 executor.
static NSString *legacyBatchWire(NSArray *commands){
    NSMutableArray *wire=[NSMutableArray array];
    for(NSDictionary *cmd in commands){
        NSString *type=[cmd[@"type"] lowercaseString];
        if([type isEqualToString:@"tap"])[wire addObject:[NSString stringWithFormat:@"62%.2f;;%.2f;;%.0f",
            [cmd[@"x"] doubleValue],[cmd[@"y"] doubleValue],cmd[@"duration"]?[cmd[@"duration"] doubleValue]:50.0]];
        else if([type isEqualToString:@"swipe"])[wire addObject:[NSString stringWithFormat:@"63%.2f;;%.2f;;%.2f;;%.2f;;%.0f",
            [cmd[@"x1"] doubleValue],[cmd[@"y1"] doubleValue],[cmd[@"x2"] doubleValue],[cmd[@"y2"] doubleValue],cmd[@"duration"]?[cmd[@"duration"] doubleValue]:300.0]];
        else {
            int duration=cmd[@"duration"]?[cmd[@"duration"] intValue]:(cmd[@"durationMs"]?[cmd[@"durationMs"] intValue]:300);
            duration=MAX(0,MIN(60000,duration));
            [wire addObject:[NSString stringWithFormat:@"64%d;;%d;;%@",cmd[@"finger"]?[cmd[@"finger"] intValue]:0,duration,TLinkautoJSEncodeGesturePoints(cmd[@"points"])]];
        }
    }
    return [wire componentsJoinedByString:@"||"];
}
static void typedBatchCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){
        injected.clear();frameTimes.clear();fakeNow=1000000;frameWork=7000000;oversleep=2000000;fakeWaits=0;
        touchToken=context.cancellationToken;cancelAt=0;throwAt=0;licenseAllowed=true;stopInLicense=false;
    };
    const auto invoke=[bridge](NSArray *commands,TLinkTaskExecutionContext *context){
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodBatch arguments:@[commands]];
        auto response=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return response;
    };
    const auto parity=[&](NSArray *commands,NSUInteger exactBytes=0){
        auto context=parent(30);reset(context);const int rawBefore=calls,gates=licenseCalls;
        auto response=invoke(commands,context);assert(response.ok&&calls==rawBefore);
        NSDictionary *result=response.value;NSString *wire=legacyBatchWire(commands);
        if(exactBytes)assert(wire.length+2==exactBytes);
        if(wire.length+2>8192){failure(result,@"input_too_large");assert(licenseCalls==gates&&injected.empty());return;}
        assert(licenseCalls==gates+1&&lastLicenseTask==65&&licenseBudget->response().capacity()==0);
        const auto points=injected;const auto times=frameTimes;
        reset(context);NSError *error=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,NO,NO) nativeBudget]);zx_handleNativeBatch((UInt8 *)wire.UTF8String,&error);}
        NSString *raw=error.localizedDescription?:@"0\r\n";
        assert([result[@"raw"] isEqualToString:raw]&&[result[@"ok"] boolValue]==(error==nil));
        assert([result[@"parts"] isEqualToArray:[[raw stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert(points.size()==injected.size()&&times==frameTimes);
        for(size_t i=0;i<points.size();++i)assert(points[i].type==injected[i].type&&points[i].index==injected[i].index&&points[i].x==injected[i].x&&points[i].y==injected[i].y);
    };
    fakeTiming=true;
    NSDictionary *tap=@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":@0};
    NSDictionary *swipe=@{@"type":@"swipe",@"x1":@40,@"y1":@50,@"x2":@80,@"y2":@90,@"duration":@16};
    NSDictionary *gesture=@{@"type":@"gesture",@"points":@[@[@20,@30],@[@40,@50]],@"durationMs":@0,@"finger":@19};
    NSArray *normal=@[tap,swipe,gesture,tap];
    for(unsigned trial=0;trial<120;++trial){
        const double x=trial%13?double(trial)*0.945:-1e308;
        parity(@[@{@"type":@"TAP",@"x":@(x),@"y":@(-0.0),@"duration":@(trial?double(trial%17)+0.5:-0.0)},swipe,
            @{@"type":@"gesture",@"points":@[@{},@[@40.945,@50.005]],@"duration":@(int(trial)-60),@"finger":@(trial%21)},tap]);
    }
    parity(@[]);parity(@[@{@"type":@"tap"},@{@"type":@"swipe"}]);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<256;++i)[many addObject:tap];parity(many);
    // Two bounded gesture plans total exactly 8192/8193 legacy characters.
    NSMutableArray *first=[NSMutableArray array],*second=[NSMutableArray array];
    for(unsigned i=0;i<512;++i)[first addObject:@[@0,@0]];
    for(unsigned i=0;i<300;++i)[second addObject:@[@0,@0]];
    for(unsigned extra=0;extra<2;++extra){second[0]=@[@(extra?1e55:1e54),@0];
        parity(@[@{@"type":@"gesture",@"duration":@0,@"points":first},@{@"type":@"gesture",@"duration":@0,@"points":second}],8192+extra);}
    auto context=parent();reset(context);const int gates=licenseCalls,wireCalls=calls;
    // Validate every JS shape before size rejection or the first side effect.
    [many addObject:tap];assert(!invoke(many,context).ok&&injected.empty()&&licenseCalls==gates);
    for(NSArray *bad:@[@[tap,@{@"type":@"unknown"}],@[tap,@{@"type":@"tap",@"x":@(NAN)}],
        @[tap,@{@"type":@"swipe",@"y2":@(INFINITY)}],@[tap,@{@"type":@"gesture",@"points":@[@[]]}],
        @[@{@"type":@"gesture",@"points":first},@{@"type":@"gesture",@"points":first},@{@"type":@"unknown"}]]){
        auto response=invoke(bad,context);assert(!response.ok&&injected.empty()&&licenseCalls==gates&&calls==wireCalls);
    }
    context=parent();reset(context);licenseAllowed=false;
    NSDictionary *result=invoke(normal,context).value;
    assert([result[@"raw"] isEqualToString:@"-1;;license_required task=65\r\n"]&&injected.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(normal,context).value,@"AbortError");assert(injected.empty());
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(normal,context).value,@"AbortError");assert(injected.empty()&&licenseCalls==noGate);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,1024)];
    failure(invoke(normal,context).value,@"TimeoutError");assert(injected.empty()&&licenseCalls==noGate);
    // Cancellation/throws on the second command never start the third, and UP
    // for the active command precedes return. Also cancel between commands.
    for(int boundary:{2,3}){context=parent();reset(context);cancelAt=boundary;
        failure(invoke(normal,context).value,@"AbortError");assert(injected.size()==size_t(boundary==2?2:4)&&injected.back().type==TOUCH_UP);}
    for(bool cpp:{false,true}){context=parent();reset(context);throwAt=3;throwCpp=cpp;
        failure(invoke(normal,context).value,@"native_exception");assert(injected.size()==4&&injected.back().type==TOUCH_UP);}
    context=parent(1,3);reset(context);assert([invoke(normal,context).value[@"ok"] boolValue]);
    context=parent(1,2);reset(context);failure(invoke(normal,context).value,@"response_too_large");assert(injected.back().type==TOUCH_UP);
    context=parent();reset(context);std::vector<TLinkNativeTouchRequest> invalid(257);
    const int beforeInvalid=licenseCalls;failure(TLinkExecuteNativeTouchBatch(invalid,context),@"invalid_touch_request");
    invalid.resize(1);invalid[0].kind=TLinkNativeTouchKind::Zoom;failure(TLinkExecuteNativeTouchBatch(invalid,context),@"invalid_touch_request");assert(licenseCalls==beforeInvalid&&injected.empty());
    fakeTiming=false;context=parent(0.05);reset(context);
    failure(invoke(@[tap,@{@"type":@"swipe",@"duration":@60000},tap],context).value,@"TimeoutError");
    assert(injected.size()==4&&injected.back().type==TOUCH_UP);fakeTiming=true;
    // RAW/mixed, string/negative/extreme duration and embedded-NUL compatibility.
    mode=@"batchRuntime";
    for(id duration:@[@-1,@60001,@(1e100),@"16"]){context=parent();reset(context);const int before=calls;
        NSArray *commands=@[@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":duration}];
        NSString *expected=[@"65" stringByAppendingString:legacyBatchWire(commands)];
        TLinkJSNativeResponse *result=invoke(commands,context);
        assert(result.ok);assert(calls==before+1);
        assert(lastPayload==expected.UTF8String);}
    context=parent();reset(context);const int beforeRaw=calls;
    auto fallback=invoke(@[tap,@"62",tap],context);assert(fallback.ok&&![fallback.value[@"ok"] boolValue]&&calls==beforeRaw+1&&injected.size()==2);
    context=parent();reset(context);unichar zero=0;NSString *nul=[@"62" stringByAppendingString:[NSString stringWithCharacters:&zero length:1]];
    const int beforeNul=calls;failure(invoke(@[tap,nul],context).value,@"invalid_payload");assert(injected.empty()&&calls==beforeNul);
    context=parent();reset(context);const int beforeDelimiter=calls;
    assert(!invoke(@[tap,@"62||62"],context).ok&&calls==beforeDelimiter&&injected.empty());
    mode=@"echo";fakeTiming=false;cancelAt=0;throwAt=0;touchToken=nil;licenseBudget.reset();
    puts("Typed batch actual bridge/entry passed: legacy task-65 frame/timestamp/reply parity, 256 commands, exact 8192/8193 ingress, full JS prevalidation, one license gate, first failure, cancellation/exception UP, output cap and RAW compatibility.");
}
static void typedColorCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorFault=0;cancelColor=false;colorError=nil;
    };
    const auto invoke=[bridge](double x,double y,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodPickColor arguments:@[@(x),@(y)]];
        TLinkJSNativeResponse *result=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const int rawBefore=calls;
    for(unsigned i=0;i<200;++i){
        const double x=i<12?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2.5,8191.49,8191.5,8192,2147483648.0,1e308}[i]:double(i)*47.125-8.5;
        const double y=double(i)*0.5;auto context=parent(30);reset(context);const int gates=licenseCalls;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *response=invoke(x,y,context);assert(response.ok);
        NSDictionary *result=response.value;assert(licenseCalls==gates+1&&lastLicenseTask==23&&colorBudget->response().capacity()==0);
        const uint64_t after=TLinkNativeNowNs();
        assert(colorBudget==licenseBudget&&colorBudget->deadline()>=before+3000000000ULL&&colorBudget->deadline()<=after+3000000000ULL);
        NSString *wire=[NSString stringWithFormat:@"%.0f;;%.0f",x,y];NSArray *parts=[wire componentsSeparatedByString:@";;"];int px=0,py=0;
        if(!TLinkColorInt([parts[0] UTF8String],px)||!TLinkColorInt([parts[1] UTF8String],py)||px<0||py<0||px>=8192||py>=8192){
            assert([result[@"raw"] isEqualToString:@"-1;;color_parameters_invalid\r\n"]);continue;
        }
        NSString *expected=[NSString stringWithFormat:@"0;;%d;;%d;;%d\r\n",px%256,py%256,(px+py)%256];
        assert([result[@"ok"] boolValue]&&[result[@"raw"] isEqualToString:expected]);
        assert([result[@"parts"] isEqualToArray:[[expected stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert([result[@"red"] intValue]==px%256&&[result[@"green"] intValue]==py%256&&[result[@"blue"] intValue]==(px+py)%256);
    }
    auto context=parent();reset(context);const int noRead=colorCalls;
    licenseAllowed=false;NSDictionary *denied=invoke(0,0,context).value;
    assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=23\r\n"]&&colorCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(0,0,context).value,@"AbortError");assert(colorCalls==noRead);
    // A local C01 expiry keeps the caller live and retains the RAW task error.
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);
    [context setNativeBudget:caller];const uint64_t callerDeadline=caller->deadline();
    NSDictionary *expired=invoke(0,0,context).value;
    assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorCalls==noRead);
    assert(!caller->stopped()&&caller->deadline()==callerDeadline&&caller->response().capacity()==0);

    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(0,0,context).value,@"AbortError");assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(0,0,context).value,@"TimeoutError");assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent();reset(context);assert(!invoke(NAN,0,context).ok&&!invoke(0,INFINITY,context).ok);assert(colorCalls==noRead&&licenseCalls==noGate);
    context=parent(0.25);reset(context);assert([invoke(0,0,context).value[@"ok"] boolValue]);assert(colorBudget->remainingSeconds(3)<0.3);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_memory_budget",@"color_cancelled_or_timed_out"]){
        context=parent();reset(context);colorError=code;NSDictionary *error=invoke(0,0,context).value;
        NSString *expected=[NSString stringWithFormat:@"-1;;%@\r\n",code];
        assert([error[@"raw"] isEqualToString:expected]&&![error[@"ok"] boolValue]);
    }
    context=parent();reset(context);cancelColor=true;failure(invoke(0,0,context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorFault=fault;failure(invoke(0,0,context).value,@"native_exception");}
    context=parent(1,12);reset(context);assert([invoke(0,0,context).value[@"ok"] boolValue]);
    context=parent(1,11);reset(context);failure(invoke(0,0,context).value,@"response_too_large");
    assert(calls==rawBefore&&!TLinkCurrentNativeBudget());colorBudget.reset();licenseBudget.reset();touchToken=nil;
    puts("Typed color actual bridge/entry passed: 200 legacy decimal/reply/parts/RGB cases, task-23 authority, C01/parent deadline scope, invalid preflight, stop/fault/output bounds and no raw dispatch or response vector.");
}
static void typedColorRangeCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorRangeFault=0;colorRangeError=nil;cancelRange=false;};
    const auto request=[](NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFindColor arguments:@[options]];};
    const auto invoke=[bridge,request](NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,reset,request,invoke](NSDictionary *options,NSString *backendError){
        mode=@"colorRangeRuntime";auto oldContext=parent(30);reset(oldContext);colorRangeError=backendError;const int beforeOld=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyColorRange:request(options) context:oldContext];const int dispatched=calls-beforeOld;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);colorRangeError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=colorRangeCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"live range parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&colorRangeCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==28&&colorRangeBudget==licenseBudget&&!colorRangeBudget->capturesResponse()&&colorRangeBudget->response().capacity()==0);
            assert(colorRangeBudget->deadline()>=started+3000000000ULL&&colorRangeBudget->deadline()<=ended+3000000000ULL);}
    };
    for(unsigned i=0;i<200;++i){
        const double x=i<12?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.49,7.5,8191.5,double(INT_MAX),1e308}[i]:double(int(i%23)-4)*0.5;
        const double width=std::vector<double>{double(INT_MIN),-1.5,-0.0,0.5,2.5,double(INT_MAX),1e308}[i%7];
        compare(@{@"x":@(x),@"y":@(double(i%8)*0.5),@"width":@(width),@"height":@(double(int(i%5)-2)*0.5),@"redMin":@(i%3?0:11),@"skip":@(i%5?int(i%4):INT_MAX)},nil);
    }
    NSDictionary *hit=@{},*miss=@{@"redMin":@11};compare(hit,nil);compare(miss,nil);
    for(NSDictionary *options:@[@{@"x":@(NAN)},@{@"y":@(INFINITY)},@{@"width":@(-INFINITY)},@{@"height":@(NAN)},@{@"x":@8192},@{@"x":@8},@{@"skip":@-1},@{@"skip":@(INT_MAX)},@{@"redMin":@-1},@{@"redMax":@256},@{@"greenMin":@20,@"greenMax":@19},@{@"blueMin":@31},@{@"x":@"1.5",@"width":@"2.5"},@{@"x":[NSNull null],@"redMin":[NSNull null]},@{@"x":@(-0.0),@"width":@(INT_MIN),@"height":@(INT_MAX)}])compare(options,nil);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_source_pixel_limit",@"color_memory_budget",@"color_allocation_failed",@"color_crop_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out"])compare(hit,code);
    compare(@{@"x":@-1},@"color_compute_busy");
    const int wireCalls=calls;auto context=parent();reset(context);const unsigned noRead=colorRangeCalls;licenseAllowed=false;
    NSDictionary *denied=invoke(hit,context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=28\r\n"]&&colorRangeCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(hit,context).value,@"AbortError");assert(colorRangeCalls==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(hit,context).value,@"AbortError");assert(licenseCalls==gates&&colorRangeCalls==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(hit,context).value,@"TimeoutError");assert(licenseCalls==gates&&colorRangeCalls==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];const uint64_t deadline=caller->deadline();
    NSDictionary *expired=invoke(hit,context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorRangeCalls==noRead&&!caller->stopped()&&caller->deadline()==deadline);
    context=parent(0.25);reset(context);assert([invoke(hit,context).value[@"ok"] boolValue]&&colorRangeBudget->remainingSeconds(3)<0.3);
    context=parent();reset(context);cancelRange=true;failure(invoke(hit,context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorRangeFault=fault;failure(invoke(hit,context).value,@"native_exception");}
    for(NSDictionary *options:@[hit,miss]){
        context=parent();reset(context);NSDictionary *success=invoke(options,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(options,context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(options,context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());colorRangeBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed live range actual bridge/entry passed: 200 frozen JS/RAW ROI/RGB/skip cases, finite/default/overflow rules, one task-28 gate, C01/caller isolation, faults/cancel/output bounds and no typed RAW dispatch/response vector.");
}
static void typedLiveColorsCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;colorPointsFault=0;colorPointsError=nil;cancelColorPoints=false;};
    const auto request=[](NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodIsColors arguments:@[points,options]];};
    const auto invoke=[bridge,request](NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"colorPointsRuntime";auto oldContext=parent(30);reset(oldContext);colorPointsError=backendError;const int beforeOld=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyLiveColors:request(points,options) context:oldContext];const int dispatched=calls-beforeOld;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);colorPointsError=backendError;const int before=calls,gates=licenseCalls;const unsigned reads=colorPointsCalls;
        const uint64_t started=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(points,options,context);const uint64_t ended=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"live points parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==before&&licenseCalls==gates+dispatched&&colorPointsCalls==reads+dispatched);
        if(dispatched){assert(lastLicenseTask==28&&colorPointsBudget==licenseBudget&&!colorPointsBudget->capturesResponse()&&colorPointsBudget->response().capacity()==0);
            assert(colorPointsBudget->deadline()>=started+3000000000ULL&&colorPointsBudget->deadline()<=ended+3000000000ULL);}
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<11?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,7.5,8191.5,double(INT_MAX),1e308}[i]:double(int(i%23)-4)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(@[@{@"x":@(x),@"y":@1.5,@"r":@10,@"g":@20,@"b":@30},@{@"red":@10,@"green":@20,@"blue":@30}],@{@"mode":@(modeValue),@"value":@(threshold)},nil);
    }
    NSArray *hit=@[@{@"red":@10,@"green":@20,@"blue":@30}],*miss=@[@{}],*badTable=@[@{},@{@"red":@999}];
    compare(hit,@{},nil);compare(miss,@{},nil);compare(badTable,@{},nil);
    compare(@[@{@"red":@11,@"r":@10,@"green":@20,@"blue":@30}],@{},nil);compare(@[@{@"red":[NSNull null],@"r":@10,@"g":@20,@"b":@30}],@{},nil);
    compare(@[@{@"x":@"1.5",@"y":@"2.5",@"r":@"10",@"g":@20,@"b":@30}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(bad,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(many,@{},nil);[many addObject:@{}];compare(many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(many,@{},nil);[many addObject:@[]];compare(many,@{},nil);
    for(unsigned extra=0;extra<2;++extra){
        [many removeAllObjects];for(unsigned i=0;i<512;++i)[many addObject:@{@"x":@(i<3?2e307:(i==3?(extra?2e89:2e88):0))}];
        NSString *wire=[NSString stringWithFormat:@"282;;%@;;1;;0.0000",TLinkautoJSEncodePointColorTable(many)];assert(wire.length==8192+extra);compare(many,@{},nil);
    }
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"value":[NSNull null],@"tolerance":@1}])compare(hit,options,nil);
    compare(badTable,@{@"mode":@2},nil);compare(@[@{},@{@"x":@8}],@{},nil);compare(@[@{@"x":@8192}],@{},nil);
    compare(@[@{@"x":@-1},@{@"red":@999}],@{},nil);
    for(NSString *code:@[@"color_compute_busy",@"color_capture_failed",@"color_source_pixel_limit",@"color_memory_budget",@"color_allocation_failed",@"color_crop_failed",@"color_context_failed",@"color_operation_failed",@"color_cancelled_or_timed_out"])compare(hit,@{},code);
    compare(badTable,@{},@"color_compute_busy");compare(@[@{@"x":@8192}],@{},@"color_capture_failed");compare(@[@{@"x":@8}],@{},@"color_capture_failed");
    const int wireCalls=calls;auto context=parent();reset(context);licenseAllowed=false;const unsigned noRead=colorPointsCalls;
    NSDictionary *denied=invoke(hit,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=28\r\n"]&&colorPointsCalls==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(hit,@{},context).value,@"AbortError");assert(colorPointsCalls==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int gates=licenseCalls;failure(invoke(hit,@{},context).value,@"AbortError");assert(licenseCalls==gates&&colorPointsCalls==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];failure(invoke(hit,@{},context).value,@"TimeoutError");assert(licenseCalls==gates&&colorPointsCalls==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];const uint64_t deadline=caller->deadline();
    NSDictionary *expired=invoke(hit,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&colorPointsCalls==noRead&&!caller->stopped()&&caller->deadline()==deadline);
    context=parent(0.25);reset(context);assert([invoke(hit,@{},context).value[@"ok"] boolValue]&&colorPointsBudget->remainingSeconds(3)<0.3);
    context=parent();reset(context);cancelColorPoints=true;failure(invoke(hit,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);colorPointsFault=fault;failure(invoke(hit,@{},context).value,@"native_exception");}
    for(NSArray *list:@[hit,miss]){context=parent();reset(context);NSDictionary *success=invoke(list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(list,@{},context).value[@"ok"] boolValue]);context=parent(1,bytes-1);reset(context);failure(invoke(list,@{},context).value,@"response_too_large");}
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());colorPointsBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed live points actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/defaults/full table and pre/post-capture bounds, 512/513 and exact ingress, scalar modes, one task-28 gate, C01/caller/fault/output bounds and no typed RAW dispatch/response vector.");
}
static void typedFramePickCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto invoke=[bridge](int id,double x,double y,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        auto request=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFramePickColor arguments:@[@(id),@(x),@(y),options]];
        TLinkJSNativeResponse *response=[bridge executeRequest:request context:context error:nil];assert(!TLinkCurrentNativeBudget());return response;
    };
    const int wireCalls=calls;
    for(unsigned trial=0;trial<100;++trial){
        double x=trial<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2147483647.0,1e308}[trial]:double(trial)*47.125;
        const double y=double(trial)*0.5;auto context=parent(30);reset(context);const int gates=licenseCalls;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *response=invoke(1,x,y,@{@"coord":trial%2?@"PoInT":@"pixel",@"maxAgeMs":@5000},context);
        assert(response.ok&&licenseCalls==gates+1&&lastLicenseTask==69&&frameBudget==licenseBudget&&frameBudget->response().capacity()==0);
        const uint64_t after=TLinkNativeNowNs();assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);
        NSString *wire=[NSString stringWithFormat:@"%.0f;;%.0f",x,y];NSArray *numbers=[wire componentsSeparatedByString:@";;"];
        assert(observedFramePick.x==[numbers[0] doubleValue]&&observedFramePick.y==[numbers[1] doubleValue]&&observedFramePick.pointCoord==bool(trial%2)&&observedFramePick.maxAgeMs==5000);
        NSDictionary *result=response.value;
        if(!TLinkFramePickParameters(observedFramePick)){failure(result,@"invalid_frame_color_parameters");continue;}
        NSString *expected=@"0;;1;;2;;3;;7;;1.235;;1.235\r\n";
        assert([result[@"raw"] isEqualToString:expected]&&[result[@"ok"] boolValue]);
        assert([result[@"parts"] isEqualToArray:[[expected stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@";;"]]);
        assert([result[@"red"] intValue]==1&&[result[@"green"] intValue]==2&&[result[@"blue"] intValue]==3&&[result[@"ageMs"] intValue]==7&&[result[@"totalMs"] doubleValue]==1.235);
    }
    auto context=parent();reset(context);const unsigned noRead=frameReads;const int noGate=licenseCalls;
    assert(!invoke(0,0,0,@{},context).ok&&!invoke(1,NAN,0,@{},context).ok&&!invoke(1,0,INFINITY,@{},context).ok);
    for(NSString *bad:@[@"pixel;;x",@"pixel\r",@"pixel\n"])assert(!invoke(1,0,0,@{@"coord":bad},context).ok);
    assert(frameReads==noRead&&licenseCalls==noGate);
    unichar nul=0;NSString *nulToken=[NSString stringWithCharacters:&nul length:1];
    NSString *nulCoord=[@"pi" stringByAppendingString:nulToken];
    unichar high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};
    NSString *invalidHigh=[NSString stringWithCharacters:&high length:1],*invalidLow=[NSString stringWithCharacters:&low length:1];
    NSString *paired=[NSString stringWithCharacters:pair length:2];
    NSArray *encodingProbes=@[nulToken,nulCoord,[nulToken stringByAppendingString:@"pixel"],
        [@"pi" stringByAppendingString:[nulToken stringByAppendingString:@"xel"]],invalidHigh,invalidLow,
        [@"pi" stringByAppendingString:invalidHigh],paired,@"",@"điểm",
        [nulToken stringByPaddingToLength:8169 withString:@"x" startingAtIndex:0],
        [nulToken stringByPaddingToLength:8170 withString:@"x" startingAtIndex:0]];
    int oracleDispatches=0;
    for(NSString *coord:encodingProbes){
        // Use the actual legacy formatter/transport as the oracle for Foundation string conversion.
        mode=@"frameEncodingOracle";const int beforeOracle=calls;
        NSString *wire=[NSString stringWithFormat:@"691;;pick;;0;;0;;%@;;1000",coord];
        NSDictionary *legacy=[bridge executeRawPayload:wire context:parent()];
        const int dispatched=calls-beforeOracle;assert(dispatched==0||dispatched==1);oracleDispatches+=dispatched;
        mode=@"echo";context=parent();reset(context);
        const int beforeGate=licenseCalls,beforeTyped=calls;const unsigned beforeRead=frameReads;
        NSDictionary *result=invoke(1,0,0,@{@"coord":coord},context).value;
        failure(result,legacy[@"parts"][1]);assert([result isEqualToDictionary:legacy]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameReads==beforeRead+dispatched);
    }
    for(unsigned extra=0;extra<2;++extra){context=parent();reset(context);const int beforeGate=licenseCalls;
        NSString *coord=[@"x" stringByPaddingToLength:8169+extra withString:@"x" startingAtIndex:0];
        NSString *wire=[NSString stringWithFormat:@"691;;pick;;0;;0;;%@;;1000",coord];assert(wire.length==8192+extra);
        NSDictionary *result=invoke(1,0,0,@{@"coord":coord},context).value;
        failure(result,extra?@"input_too_large":@"invalid_frame_color_parameters");assert(licenseCalls==beforeGate+(extra?0:1));
    }
    for(NSDictionary *options:@[@{@"coord":@"typo"},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001}]){context=parent();reset(context);failure(invoke(1,0,0,options,context).value,@"invalid_frame_color_parameters");}
    context=parent();reset(context);licenseAllowed=false;const unsigned beforeDenial=frameReads;
    NSDictionary *denied=invoke(1,0,0,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameReads==beforeDenial);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,0,0,@{},context).value,@"AbortError");assert(frameReads==beforeDenial);
    context=parent();reset(context);[context.cancellationToken cancel];const int stoppedGate=licenseCalls;
    failure(invoke(1,0,0,@{},context).value,@"AbortError");assert(licenseCalls==stoppedGate&&frameReads==beforeDenial);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,0,0,@{},context).value,@"TimeoutError");assert(licenseCalls==stoppedGate&&frameReads==beforeDenial);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,0,0,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameReads==beforeDenial);
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"]){
        context=parent();reset(context);frameReadError=code;failure(invoke(1,0,0,@{},context).value,code);
    }
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,0,0,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,0,0,@{},context).value,@"native_exception");}
    const NSUInteger successBytes=[@"0;;1;;2;;3;;7;;1.235;;1.235\r\n" length];
    context=parent(1,successBytes);reset(context);assert([invoke(1,0,0,@{},context).value[@"ok"] boolValue]);
    context=parent(1,successBytes-1);reset(context);failure(invoke(1,0,0,@{},context).value,@"response_too_large");
    assert(calls==wireCalls+oracleDispatches&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;
    puts("Typed frame pick actual bridge/entry passed: scalar/RGB/age/time/parts parity, exact 8192/8193 input, 12 legacy NUL/UTF/size admission cases, one task-69 gate, C01/caller deadlines, faults/output and no raw dispatch.");
}
static void typedFramePickManyCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](NSArray *points,NSDictionary *options){return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFramePickColors arguments:@[@1,points,options]];};
    const auto invoke=[bridge,request](NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameManyRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameMany:request(points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameManyReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(points,options,context);const uint64_t after=TLinkNativeNowNs();
        assert(typed.ok==legacy.ok);
        if(typed.ok){
            if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame many parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);
            assert([typed.value isEqual:legacy.value]);
        }else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameManyReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<120;++i){
        double x=i<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,1.5,2147483647.0,1e308}[i]:double(i)*17.125;
        compare(@[@[@(x),@(double(i)*0.5)],@{@"x":@1,@"y":@2},@{}],@{@"coord":i%2?@"PoInT":@"pixel",@"maxAgeMs":@5000},nil);
    }
    compare(@[@[@"2.5",@"3.5",@999],@{}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@[@(NAN),@0]],@[@[@0,@(INFINITY)]]])compare(bad,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@[@0,@0]];
    compare(many,@{},nil);[many addObject:@[@0,@0]];compare(many,@{},nil);compare(many,@{},@"frame_expired");compare(many,@{},@"frame_not_found");
    [many addObject:@[]];compare(many,@{},nil); // full JS validation survives a lazy count failure
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@[@(1e308),@0]];
    compare(many,@{},nil);[many addObject:@[]];compare(many,@{},nil); // late shape error before oversized ingress
    NSArray *points=@[@[@0,@0]];
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],
        [NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(points,@{@"coord":coord},nil);
    for(unsigned extra=0;extra<2;++extra){
        NSString *coord=[@"x" stringByPaddingToLength:8165+extra withString:@"x" startingAtIndex:0];
        NSString *wire=[NSString stringWithFormat:@"691;;pick_many;;0,0;;%@;;1000",coord];assert(wire.length==8192+extra);compare(points,@{@"coord":coord},nil);
        coord=[nulString stringByPaddingToLength:8165+extra withString:@"x" startingAtIndex:0];compare(points,@{@"coord":coord},nil);
    }
    for(NSDictionary *options:@[@{@"coord":@"typo"},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(points,options,nil);
    const int wireCalls=calls;
    auto context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameManyReads;
    NSDictionary *denied=invoke(points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameManyReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(points,@{},context).value,@"AbortError");assert(frameManyReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameManyReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameManyReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameManyReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(points,@{},context).value,@"native_exception");}
    context=parent();reset(context);NSDictionary *success=invoke(points,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    context=parent(1,bytes);reset(context);assert([invoke(points,@{},context).value[@"ok"] boolValue]);
    context=parent(1,bytes-1);reset(context);failure(invoke(points,@{},context).value,@"response_too_large");
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame pick-many actual bridge/entry passed: 120 frozen JS/RAW parity cases, mixed point shapes, 512/513 and full prevalidation, exact 8192/8193 and Unicode/NUL admission, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameSearchCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameFindColor arguments:@[@(id),options]];};
    const auto invoke=[bridge,request](int id,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSDictionary *options,NSString *backendError){
        mode=@"frameSearchRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameSearch:request(id,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameSearchReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,options,context);const uint64_t after=TLinkNativeNowNs();
        assert(typed.ok==legacy.ok);
        if(typed.ok){
            if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame search parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);
            assert([typed.value isEqual:legacy.value]);
        }else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameSearchReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        double x=i<8?std::vector<double>{-1e308,-1.5,-0.5,-0.0,0.5,7.5,2147483646.0,1e308}[i]:double(int(i%13)-3)*0.5;
        compare(1,@{@"x":@(x),@"y":@(double(i%7)*0.5),@"width":@(int(i%9)-2),@"height":@0,@"coord":i%2?@"PoInT":@"pixel",@"skip":@(i%4),@"redMin":@5,@"redMax":@5,@"greenMin":@3,@"greenMax":@3,@"blueMin":@2,@"blueMax":@2,@"maxAgeMs":@5000},nil);
    }
    compare(1,@{},nil);compare(1,@{@"rMin":@5,@"rMax":@5,@"gMin":@3,@"gMax":@3,@"bMin":@2,@"bMax":@2},nil);
    compare(1,@{@"rMin":@5,@"redMin":@0,@"redMax":@14,@"skip":@1023},nil);
    for(NSDictionary *options:@[@{@"redMin":@-1},@{@"redMax":@256},@{@"greenMin":@20,@"greenMax":@19},@{@"blueMin":@256},@{@"skip":@-1},@{@"skip":@1024},@{@"skip":@(INT_MAX)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0},@{@"x":@(NAN)},@{@"width":@(INFINITY)}])compare(1,options,nil);
    compare(0,@{},nil);compare(-1,@{},nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],
        [NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,@{@"coord":coord},nil);
    NSString *emptyWire=@"691;;search_single;;0;;0;;0;;0;;0;;255;;0;;255;;0;;255;;0;;;;1000";
    const NSUInteger maxCoord=8192-emptyWire.length;
    for(unsigned extra=0;extra<2;++extra){
        NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,@{@"coord":coord},nil);
        coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,@{@"coord":coord},nil);
    }
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,@{@"x":@(double(INT_MAX)-1),@"coord":@"point"},code);
    const int wireCalls=calls;auto context=parent();reset(context);
    NSDictionary *miss=invoke(1,@{@"redMin":@255},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&[miss[@"x"] intValue]==-1&&[miss[@"y"] intValue]==-1&&[miss[@"red"] intValue]==-1&&[miss[@"green"] intValue]==-1&&[miss[@"blue"] intValue]==-1);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameSearchReads;
    NSDictionary *denied=invoke(1,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameSearchReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,@{},context).value,@"AbortError");assert(frameSearchReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameSearchReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameSearchReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;
    auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameSearchReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,@{},context).value,@"native_exception");}
    for(NSDictionary *options:@[@{},@{@"redMin":@255}]){
        context=parent();reset(context);NSDictionary *success=invoke(1,options,context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,options,context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,options,context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame search actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/RGB/ROI/skip, hit/miss metadata, exact ingress/Unicode/NUL, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameColorsCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameIsColors arguments:@[@(id),points,options]];};
    const auto invoke=[bridge,request](int id,NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameColorsRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameColors:request(id,points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameColorsReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,points,options,context);const uint64_t after=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame colors parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameColorsReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<9?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),1e308}[i]:double(int(i%17)-3)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(1,@[@{@"x":@(x),@"y":@1.5,@"r":@4,@"g":@2,@"b":@2},@{}],@{@"coord":i%3?@"pixel":@"PoInT",@"mode":@(modeValue),@"value":@(threshold),@"maxAgeMs":@5000},nil);
    }
    NSArray *points=@[@{}],*missPoints=@[@{@"red":@255}],*badTable=@[@{@"red":@255},@{@"red":@999}];
    compare(1,points,@{},nil);compare(1,missPoints,@{},nil);compare(1,badTable,@{},nil);
    compare(1,@[@{@"red":@1,@"r":@0}],@{},nil);compare(1,@[@{@"red":[NSNull null],@"r":@0}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(1,bad,@{},nil);
    compare(0,points,@{},nil);compare(-1,points,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(1,many,@{},nil);[many addObject:@{}];compare(1,many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(1,many,@{},nil);[many addObject:@[]];compare(1,many,@{},nil);
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(1,points,options,nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],[NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,points,@{@"coord":coord},nil);
    for(double threshold:{0.0,-0.0,-0.00004,0.99995,255.00004,1e308,double(NAN),double(-NAN),double(INFINITY),double(-INFINITY)}){
        NSString *scalar=[NSString stringWithFormat:@"%.4f",threshold];
        NSString *emptyWire=[NSString stringWithFormat:@"691;;is_colors;;0,,0,,0,,0,,0;;1;;%@;;;;1000",scalar];const NSUInteger maxCoord=8192-emptyWire.length;
        for(unsigned extra=0;extra<2;++extra){
            NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
            coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
        }
    }
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,badTable,@{},code);
    const int wireCalls=calls;auto context=parent();reset(context);NSDictionary *miss=invoke(1,missPoints,@{},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&![miss[@"value"] boolValue]);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameColorsReads;
    NSDictionary *denied=invoke(1,points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameColorsReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,points,@{},context).value,@"AbortError");assert(frameColorsReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameColorsReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameColorsReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameColorsReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,points,@{},context).value,@"native_exception");}
    for(NSArray *list:@[points,missPoints]){
        context=parent();reset(context);NSDictionary *success=invoke(1,list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,list,@{},context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,list,@{},context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame colors actual bridge/entry passed: 160 frozen JS/RAW cases, aliases/defaults/full table preflight, 512/513 and exact ingress/Unicode/NUL, scalar rounding/nonfinite modes, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
static void typedFrameMultiCases(TLinkInProcessNativeBridge *bridge){
    const auto reset=[](TLinkTaskExecutionContext *context){touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;frameReadFault=0;frameReadError=nil;cancelFrameRead=false;};
    const auto request=[](int id,NSArray *points,NSDictionary *options)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodFrameFindMultiColor arguments:@[@(id),points,options]];};
    const auto invoke=[bridge,request](int id,NSArray *points,NSDictionary *options,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(id,points,options) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto compare=[bridge,request,invoke,reset](int id,NSArray *points,NSDictionary *options,NSString *backendError){
        mode=@"frameMultiRuntime";auto legacyContext=parent(30);reset(legacyContext);frameReadError=backendError;const int beforeLegacy=calls;
        TLinkJSNativeResponse *legacy=[bridge legacyFrameMulti:request(id,points,options) context:legacyContext];const int dispatched=calls-beforeLegacy;assert(dispatched==0||dispatched==1);
        auto context=parent(30);reset(context);frameReadError=backendError;const int beforeTyped=calls,beforeGate=licenseCalls;const unsigned beforeRead=frameMultiReads;
        const uint64_t before=TLinkNativeNowNs();TLinkJSNativeResponse *typed=invoke(id,points,options,context);const uint64_t after=TLinkNativeNowNs();assert(typed.ok==legacy.ok);
        if(typed.ok){if(![typed.value isEqual:legacy.value])std::fprintf(stderr,"frame multi parity: legacy %s, typed %s\n",[[legacy.value description] UTF8String],[[typed.value description] UTF8String]);assert([typed.value isEqual:legacy.value]);}
        else assert([typed.errorMessage isEqualToString:legacy.errorMessage]&&[typed.errorCode isEqual:legacy.errorCode]);
        assert(calls==beforeTyped&&licenseCalls==beforeGate+dispatched&&frameMultiReads==beforeRead+dispatched);
        if(dispatched){assert(lastLicenseTask==69&&frameBudget==licenseBudget&&!frameBudget->capturesResponse()&&frameBudget->response().capacity()==0);
            assert(frameBudget->deadline()>=before+3000000000ULL&&frameBudget->deadline()<=after+3000000000ULL);}
        assert(!TLinkCurrentNativeBudget());
    };
    for(unsigned i=0;i<160;++i){
        const double x=i<9?std::vector<double>{-1e308,double(INT_MIN),-1.5,-0.5,-0.0,0.5,1.5,double(INT_MAX),1e308}[i]:double(int(i%17)-3)*0.5;
        const int modeValue=int(i%2);const double threshold=modeValue?std::vector<double>{0,0.99995,255.00004,255.00006}[i%4]:std::vector<double>{0.99995,0.8,1.00006,-0.00004}[i%4];
        compare(1,@[@{@"x":@(x),@"y":@1.5,@"r":@4,@"g":@2,@"b":@2},@{}],@{@"coord":i%3?@"pixel":@"PoInT",@"mode":@(modeValue),@"value":@(threshold),@"maxAgeMs":@5000,@"x":@(double(int(i%9)-2)*0.5),@"y":@(-0.0),@"width":@(i%5),@"height":@0,@"skip":@(i%4)},nil);
    }
    NSArray *points=@[@{}],*missPoints=@[@{@"red":@255}],*badTable=@[@{@"red":@255},@{@"red":@999}];
    compare(1,points,@{},nil);compare(1,missPoints,@{},nil);compare(1,badTable,@{},nil);
    compare(1,@[@{@"red":@1,@"r":@0}],@{},nil);compare(1,@[@{@"red":[NSNull null],@"r":@0}],@{},nil);
    for(NSArray *bad:@[@[],@[@[]],@[@1],@[@{@"x":@(NAN)}],@[@{@"y":@(INFINITY)}]])compare(1,bad,@{},nil);
    compare(0,points,@{},nil);compare(-1,points,@{},nil);
    NSMutableArray *many=[NSMutableArray array];for(unsigned i=0;i<512;++i)[many addObject:@{}];compare(1,many,@{},nil);[many addObject:@{}];compare(1,many,@{},nil);
    [many removeAllObjects];for(unsigned i=0;i<40;++i)[many addObject:@{@"x":@(1e308)}];compare(1,many,@{},nil);[many addObject:@[]];compare(1,many,@{},nil);
    for(NSDictionary *options:@[@{@"mode":@2},@{@"mode":@0,@"value":@(-0.00004)},@{@"mode":@1,@"value":@255.00004},@{@"mode":@0,@"tolerance":@1},@{@"mode":@0,@"value":@0.75,@"tolerance":@1},@{@"value":@(NAN)},@{@"value":@(-NAN)},@{@"value":@(INFINITY)},@{@"value":@(-INFINITY)},@{@"value":@(1e308)},@{@"maxAgeMs":@-1},@{@"maxAgeMs":@5001},@{@"maxAgeMs":@0}])compare(1,points,options,nil);
    unichar nul=0,high=0xd800,low=0xdc00;unichar pair[]={0xd83d,0xde00};NSString *nulString=[NSString stringWithCharacters:&nul length:1];
    for(NSString *coord:@[nulString,[@"pi" stringByAppendingString:nulString],[NSString stringWithCharacters:&high length:1],[NSString stringWithCharacters:&low length:1],[NSString stringWithCharacters:pair length:2],@"điểm",@"",@"pixel;;x",@"pixel\r",@"pixel\n"])compare(1,points,@{@"coord":coord},nil);
    for(double threshold:{0.0,-0.0,-0.00004,0.99995,255.00004,1e308,double(NAN),double(-NAN),double(INFINITY),double(-INFINITY)}){
        NSString *scalar=[NSString stringWithFormat:@"%.4f",threshold];
        NSString *emptyWire=[NSString stringWithFormat:@"691;;find_multi_point;;0;;0;;0;;0;;0,,0,,0,,0,,0;;1;;%@;;0;;;;1000",scalar];const NSUInteger maxCoord=8192-emptyWire.length;
        for(unsigned extra=0;extra<2;++extra){
            NSString *coord=[@"x" stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
            coord=[nulString stringByPaddingToLength:maxCoord+extra withString:@"x" startingAtIndex:0];compare(1,points,@{@"coord":coord,@"value":@(threshold)},nil);
        }
    }
    for(NSDictionary *options:@[@{@"x":@(NAN)},@{@"height":@(INFINITY)},@{@"skip":@-1},@{@"skip":@1024},@{@"skip":@1023},@{@"coord":@"point",@"width":@(double(INT_MAX)-1)},@{@"x":@(-100),@"y":@100},@{@"x":@2,@"y":@2,@"width":@1,@"height":@1}])compare(1,points,options,nil);
    compare(1,@[@{@"x":@-1,@"red":@2,@"green":@2}],@{@"coord":@"point",@"x":@1,@"y":@1,@"width":@1,@"height":@1,@"mode":@0,@"value":@1},nil);
    compare(1,@[@{@"x":@(INT_MAX)},@{@"red":@999}],@{@"coord":@"point"},nil);
    compare(1,badTable,@{@"coord":@"point",@"width":@(double(INT_MAX)-1)},nil);
    for(NSString *code:@[@"frame_not_found",@"frame_missing_bgra",@"frame_geometry_invalid",@"frame_expired",@"color_compute_busy",@"image_compute_busy"])compare(1,badTable,@{},code);
    const int wireCalls=calls;auto context=parent();reset(context);NSDictionary *miss=invoke(1,missPoints,@{},context).value;
    assert([miss[@"ok"] boolValue]&&![miss[@"matched"] boolValue]&&[miss[@"x"] intValue]==-1&&[miss[@"y"] intValue]==-1&&!miss[@"value"]);
    context=parent();reset(context);licenseAllowed=false;const unsigned noRead=frameMultiReads;
    NSDictionary *denied=invoke(1,points,@{},context).value;assert([denied[@"raw"] isEqualToString:@"-1;;license_required task=69\r\n"]&&frameMultiReads==noRead);
    context=parent();reset(context);stopInLicense=true;failure(invoke(1,points,@{},context).value,@"AbortError");assert(frameMultiReads==noRead);
    context=parent();reset(context);[context.cancellationToken cancel];const int noGate=licenseCalls;
    failure(invoke(1,points,@{},context).value,@"AbortError");assert(licenseCalls==noGate&&frameMultiReads==noRead);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,TLinkNativeNowNs()-1,4096)];
    failure(invoke(1,points,@{},context).value,@"TimeoutError");assert(licenseCalls==noGate&&frameMultiReads==noRead);
    context=parent(30);reset(context);licenseDelayMs=3100;auto caller=std::make_shared<TLinkNativeBudget>([context.cancellationToken nativeCancellation],TLinkNativeDeadline(30),4096);[context setNativeBudget:caller];
    NSDictionary *expired=invoke(1,points,@{},context).value;assert([expired[@"raw"] isEqualToString:@"1;;native_cancelled_or_timed_out\r\n"]&&!caller->stopped()&&frameMultiReads==noRead);
    context=parent();reset(context);cancelFrameRead=true;failure(invoke(1,points,@{},context).value,@"AbortError");
    for(int fault:{1,2}){context=parent();reset(context);frameReadFault=fault;failure(invoke(1,points,@{},context).value,@"native_exception");}
    for(NSArray *list:@[points,missPoints]){
        context=parent();reset(context);NSDictionary *success=invoke(1,list,@{},context).value;const NSUInteger bytes=[success[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        context=parent(1,bytes);reset(context);assert([invoke(1,list,@{},context).value[@"ok"] boolValue]);
        context=parent(1,bytes-1);reset(context);failure(invoke(1,list,@{},context).value,@"response_too_large");
    }
    assert(calls==wireCalls&&!TLinkCurrentNativeBudget());frameBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frame multi actual bridge/entry passed: 160 frozen JS/RAW ROI/offset/skip cases, aliases/defaults/full table preflight, 512/513 and exact ingress/Unicode/NUL, ROI/table/offset precedence, scalar modes, one task-69 gate, C01/caller deadlines, faults/output and no typed RAW dispatch.");
}
int main() { @autoreleasepool {
    auto bridge = [TLinkInProcessNativeBridge new]; mode = @"echo";
    auto context = parent();
    auto result = [bridge executeRawPayload:@"18xin chào" context:context];
    assert([result[@"ok"] boolValue] && [result[@"parts"][1] isEqualToString:@"xin chào"]);
    assert(observed.cancellationToken == context.cancellationToken && [observed.ownerRunId isEqualToString:@"run"]);
    assert(lastPayload == "18xin chào" && !TLinkCurrentNativeBudget());
    const int initial = calls;
    failure([bridge executeRawPayload:[@"18" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0] context:context], @"input_too_large");
    unichar nul[] = {'1', '8', 0, 'a'};
    failure([bridge executeRawPayload:[NSString stringWithCharacters:nul length:4] context:context], @"invalid_payload");
    assert(calls == initial);
    assert([[bridge executeRawPayload:[@"18" stringByPaddingToLength:8192 withString:@"界" startingAtIndex:0] context:context][@"ok"] boolValue]);
    assert(lastPayload.size() == 2 + 8190 * 3);
    assert([[bridge executeRawPayload:@"18" context:nil][@"ok"] boolValue]);
    mode = @"chunks";
    assert([[bridge executeRawPayload:@"18" context:parent(1, 13)][@"raw"] isEqualToString:@"0;;1234567890"]);
    failure([bridge executeRawPayload:@"18" context:parent(1, 12)], @"response_too_large");
    mode = @"exception";
    failure([bridge executeRawPayload:@"18" context:parent()], @"native_exception");
    assert(!TLinkCurrentNativeBudget());
    mode = @"wait";
    failure([bridge executeRawPayload:@"18" context:parent(0.01)], @"TimeoutError");
    context = parent(); [context.cancellationToken cancel];
    const int beforeCancel = calls;
    failure([bridge executeRawPayload:@"18" context:context], @"AbortError");
    assert(calls == beforeCancel);
    // Cleanup can run after cancellation/deadline; it retains the owner tuple.
    assert([[bridge executeRawPayload:@"6741;;session;;run;;test" context:context][@"ok"] boolValue]);
    for (NSString *payload in @[@"66", @"481;;0;;0;;5;;5", @"482;;/image.png"]) {
        mode = @"cancelAllocation"; const int previous = releases;
        failure([bridge executeRawPayload:payload context:parent()], @"AbortError");
        assert(releases == previous + 1 && lastPayload.find(";;session;;run;;test") != std::string::npos);
        mode = @"expireAllocation";
        failure([bridge executeRawPayload:payload context:parent(0.05)], @"TimeoutError");
        assert(releases == previous + 2);
    }
    const int beforeSmall = calls;
    failure([bridge executeRawPayload:@"66" context:parent(1, 32)], @"response_too_large");
    assert(calls == beforeSmall);
    // Typed shell's explicit deadline survives the nested wire call; parent budget wins.
    context = parent(200);
    auto typed = TLinkNativeCallContext(context, NO, NO, 120);
    auto nested = TLinkNativeCallContext(typed, NO, YES);
    assert([typed nativeBudget]->remainingSeconds(200) > 119);
    assert([nested nativeBudget]->deadline() == [typed nativeBudget]->deadline());
    auto shorter = TLinkNativeCallContext(typed, NO, NO, 300);
    assert([shorter nativeBudget]->deadline() == [typed nativeBudget]->deadline());
    auto rawContext = parent(0, 0);
    [rawContext setNativeBudget:TLinkTaskBudget(rawContext)];
    assert(TLinkTaskBudget(rawContext) == [rawContext nativeBudget]);
    assert([rawContext nativeBudget]->deadline() == 0);
    auto fromRaw = TLinkNativeCallContext(rawContext, NO, YES);
    assert(fromRaw.defaultTimeoutSeconds == 30 && [fromRaw nativeBudget]->deadline() != 0);
    // The actual queue wrapper restores scopes and skips work expired while queued.
    auto queue = dispatch_queue_create("native.budget.test", DISPATCH_QUEUE_SERIAL);
    auto budget = [typed nativeBudget];
    { TLinkNativeBudgetScope scope(budget);
      TLinkNativeDispatchSync(queue, ^{ assert(TLinkCurrentNativeBudget() == budget); }); }
    dispatch_sync(queue, ^{ assert(!TLinkCurrentNativeBudget()); });
    auto blocked = dispatch_semaphore_create(0), gate = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{ dispatch_semaphore_signal(blocked); dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER); });
    dispatch_semaphore_wait(blocked, DISPATCH_TIME_FOREVER);
    auto expired = std::make_shared<TLinkNativeBudget>(nullptr, TLinkNativeDeadline(0.005), 1024);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    dispatch_semaphore_signal(gate);
    { TLinkNativeBudgetScope scope(expired); TLinkNativeDispatchSync(queue, ^{ assert(false && "expired queued operation ran"); }); }
    // Actual press body and request budget prelude: UP even if DOWN returns an abort.
    mode = @"cancelHardwareDown";
    auto press = [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodPressHardwareKey arguments:@[@1]];
    const int beforePress = releases;
    auto pressed = [bridge executeRequest:press context:parent() error:nil];
    failure(pressed.value, @"AbortError");
    assert(releases == beforePress + 1 && lastPayload == "300;;1");
    mode = @"echo";
    pressed = [bridge executeRequest:press context:parent(0.05) error:nil];
    failure(pressed.value, @"TimeoutError");
    assert(releases == beforePress + 2 && lastPayload == "300;;1");
    // Normal completion executes the production result-merging helper as well.
    pressed = [bridge executeRequest:press context:parent() error:nil];
    assert(pressed.ok && [pressed.value[@"ok"] boolValue]);
    assert([pressed.value[@"down"][@"ok"] boolValue]);
    assert(releases == beforePress + 3 && lastPayload == "300;;1");
    checkGesture(zx_handleNativeTap, @"20;;30;;60000;;19", 1, 1);
    checkGesture(zx_handleNativeSwipe, @"20;;30;;80;;90;;5000;;19;;120", 1, 2);
    checkGesture(zx_handleNativeGesture, @"19;;500;;20,30|40,50|60,70", 1, 2);
    checkGesture(zx_handleNativeGesture, @"zoom;;250;;500;;20;;80;;5000;;2;;120", 2, 2);
    checkGesture(zx_handleNativeBatch, @"1011190020000300", 1, 1); // abort after final raw DOWN still releases
    injected.clear(); touchToken = nil; cancelAt = 0;
    { TLinkNativeBudgetScope scope([TLinkNativeCallContext(parent(1), NO, NO) nativeBudget]);
      NSError *error = nil;
      assert(zx_handleNativeTap((UInt8 *)"20;;30;;0;;0", &error) && injected.size() == 2);
      assert(zx_clampTouchCoord(1e30) == 99999); }
    timingCases();
    typedTouchCases(bridge);
    typedBatchCases(bridge);
    typedColorCases(bridge);
    typedColorRangeCases(bridge);
    typedLiveColorsCases(bridge);
    typedFramePickCases(bridge);
    typedFramePickManyCases(bridge);
    typedFrameSearchCases(bridge);
    typedFrameColorsCases(bridge);
    typedFrameMultiCases(bridge);
    std::puts("macOS actual bridge/context/sink/queue and gesture cancellation integration passed.");
} }
