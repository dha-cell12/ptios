#include "../shared/TLinkNativeTouchRequest.h"
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
enum {TASK_NATIVE_BATCH=65};
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
- (NSDictionary *)executeRawPayload:(NSString *)payload context:(TLinkTaskExecutionContext *)context;
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
@end
@implementation TLinkInProcessNativeBridge
#include "NativeBridgeUnderTest.inc"
- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request context:(TLinkTaskExecutionContext *)context error:(NSError **)error {
#include "NativeRequestPreludeUnderTest.inc"
    if (false) {}
#include "NativePressUnderTest.inc"
#include "NativeTouchBridgeUnderTest.inc"
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
static TLinkNativeBudgetPtr licenseBudget;
static BOOL TLinkRootfullLicenseTaskAllowed(NSInteger task,NSString **denial){
    ++licenseCalls;lastLicenseTask=int(task);licenseBudget=TLinkCurrentNativeBudget();
    assert(TLinkCurrentNativeBudget() && !TLinkCurrentNativeBudget()->capturesResponse());
    if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed && denial)*denial=[NSString stringWithFormat:@"-1;;license_required task=%ld\r\n",(long)task];
    return licenseAllowed;
}
// Match Image.h: OpenCV leaves these macros undefined in production Task.xm.
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeTouchEntryUnderTest.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static TLinkTaskExecutionContext *parent(double timeout = 1, NSUInteger cap = 1024 * 1024) {
    auto context = [TLinkTaskExecutionContext new];
    context.cancellationToken = [TLinkCancellationToken new];
    context.defaultTimeoutSeconds = timeout; context.defaultMaxOutputBytes = cap;
    context.ownerSessionId = @"session"; context.ownerRunId = @"run"; context.ownerRuntime = @"test";
    return context;
}
static void failure(NSDictionary *result, NSString *code) {
    assert(![result[@"ok"] boolValue] && [result[@"parts"][1] isEqualToString:code]);
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
    auto result=invoke(normal,context).value;
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
        auto result=invoke(@[@{@"type":@"tap",@"x":@20,@"y":@30,@"duration":duration}],context);
        assert(result.ok&&calls==before+1&&lastPayload.find("652620.00;;30.00;;")==0);}
    context=parent();reset(context);const int beforeRaw=calls;
    auto fallback=invoke(@[tap,@"62",tap],context);assert(fallback.ok&&![fallback.value[@"ok"] boolValue]&&calls==beforeRaw+1&&injected.size()==2);
    context=parent();reset(context);unichar zero=0;NSString *nul=[@"62" stringByAppendingString:[NSString stringWithCharacters:&zero length:1]];
    const int beforeNul=calls;failure(invoke(@[tap,nul],context).value,@"invalid_payload");assert(injected.empty()&&calls==beforeNul);
    context=parent();reset(context);const int beforeDelimiter=calls;
    assert(!invoke(@[tap,@"62||62"],context).ok&&calls==beforeDelimiter&&injected.empty());
    mode=@"echo";fakeTiming=false;cancelAt=0;throwAt=0;touchToken=nil;licenseBudget.reset();
    puts("Typed batch actual bridge/entry passed: legacy task-65 frame/timestamp/reply parity, 256 commands, exact 8192/8193 ingress, full JS prevalidation, one license gate, first failure, cancellation/exception UP, output cap and RAW compatibility.");
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
    std::puts("macOS actual bridge/context/sink/queue and gesture cancellation integration passed.");
} }
