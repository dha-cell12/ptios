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
static BOOL TLinkautoJSIsFiniteNumber(double value){return isfinite(value);}
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
    if(!licenseAllowed && denial)*denial=@"-1;;license_required task=62\r\n";
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
    puts("Typed touch actual bridge/entry passed: 160 legacy-wire/frame/timestamp cases, task 62/63 gates, gate-time cancellation, pre-expiry, output caps, NS/C++ exceptions, owned UP, no raw dispatch or response-buffer allocation.");
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
    std::puts("macOS actual bridge/context/sink/queue and gesture cancellation integration passed.");
} }
