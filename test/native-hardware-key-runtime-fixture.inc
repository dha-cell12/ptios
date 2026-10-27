// Actual HID mapping/client/core/parser and typed bridge/entry. Opaque IOKit calls
// use counted CF strings; no hardware events are injected on the test host.
#import "../pccontrol/HardwareKey.h"
#include <cstring>
using IOHIDEventSystemClientRef=CFTypeRef;
using IOHIDEventRef=CFTypeRef;
struct HardwareFrame {
    uint16_t page,usage;bool down;
    bool operator==(const HardwareFrame &r)const{return page==r.page&&usage==r.usage&&down==r.down;}
};
static std::vector<HardwareFrame> hardwareFrames;
static HardwareFrame hardwarePending{};
static std::set<CFTypeRef> hardwareLiveClients,hardwareLiveEvents;
static unsigned hardwareSerial=0,hardwareFault=0;
static TLinkNativeBudgetPtr hardwareObservedBudget;
static std::function<void(const HardwareFrame &)> hardwareOnDispatch;
static uint64_t hardwareClock(){return 7;}
static IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator){
    if(hardwareFault==1)return nullptr;
    const std::string name="key-client-"+std::to_string(++hardwareSerial);
    CFStringRef value=CFStringCreateWithCString(allocator,name.c_str(),kCFStringEncodingUTF8);
    assert(value&&hardwareLiveClients.insert(value).second);return value;
}
static IOHIDEventRef IOHIDEventCreateKeyboardEvent(CFAllocatorRef allocator,uint64_t timestamp,uint16_t page,uint16_t usage,Boolean down,int options){
    assert(timestamp==7&&options==0);if(hardwareFault==2)return nullptr;
    hardwarePending={page,usage,bool(down)};
    const std::string name="key-event-"+std::to_string(++hardwareSerial);
    CFStringRef value=CFStringCreateWithCString(allocator,name.c_str(),kCFStringEncodingUTF8);
    assert(value&&hardwareLiveEvents.insert(value).second);return value;
}
static void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client,IOHIDEventRef event){
    assert(hardwareLiveClients.count(client)==1&&hardwareLiveEvents.count(event)==1);
    hardwareObservedBudget=TLinkCurrentNativeBudget();
    if(hardwareFault==3)[NSException raise:@"KeyFixture" format:@"before dispatch"];
    if(hardwareFault==4)throw std::runtime_error("before dispatch");
    hardwareFrames.push_back(hardwarePending);
    auto callback=hardwareOnDispatch;if(callback)callback(hardwarePending);
    if(hardwareFault==5)[NSException raise:@"KeyFixture" format:@"after dispatch"];
    if(hardwareFault==6)throw std::runtime_error("after dispatch");
}
static void hardwareRelease(CFTypeRef value){
    const size_t removed=hardwareLiveClients.erase(value)+hardwareLiveEvents.erase(value);assert(removed==1);CFRelease(value);
}
#define mach_absolute_time hardwareClock
#define CFRelease hardwareRelease
#include "HardwareKeyCoreUnderTest.inc"
#define hardwareKeyClient legacyHardwareKeyClient
#define getUsageForKeyType legacyGetUsageForKeyType
#define sendHardwareKeyEventFromRawData legacySendHardwareKeyEventFromRawData
#include "fixtures/hardware-key-core-legacy-v1.inc"
#undef sendHardwareKeyEventFromRawData
#undef getUsageForKeyType
#undef hardwareKeyClient
#undef CFRelease
#undef mach_absolute_time
static void hardwareDropClients(){
    assert(hardwareLiveEvents.empty());
    if(hardwareKeyClient){hardwareRelease(hardwareKeyClient);hardwareKeyClient=nullptr;}
    if(legacyHardwareKeyClient){hardwareRelease(legacyHardwareKeyClient);legacyHardwareKeyClient=nullptr;}
    assert(hardwareLiveClients.empty());
}
static void hardwareKeyLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_HARDWARE_KEY;auto budget=TLinkCurrentNativeBudget();assert(budget&&budget->capturesResponse());
    UInt8 *eventData=bytes+2;
    const bool cleanup=budget->cleanup()&&std::strncmp(reinterpret_cast<const char *>(eventData),"0;;",3)==0;
    if(!cleanup){
        ++licenseCalls;lastLicenseTask=TASK_HARDWARE_KEY;licenseBudget=budget;
        if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=30\r\n",writeStreamRef);return;}
    }
    if(false){}
#define sendHardwareKeyEventFromRawData legacySendHardwareKeyEventFromRawData
#include "fixtures/hardware-key-handler-legacy-v1.inc"
#undef sendHardwareKeyEventFromRawData
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeHardwareKeyEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedHardwareKeyCases(TLinkInProcessNativeBridge *bridge){
    mode=@"hardwareKeyRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        hardwareFrames.clear();hardwareFault=0;hardwareOnDispatch={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodHardwareKey arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](NSArray *args,NSUInteger cap){
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        TLinkJSNativeResponse *expected=[bridge legacyHardwareKey:request(args) context:context];const auto frames=hardwareFrames;
        context=parent(1,cap);reset(context);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]));
        if(!actual.ok){assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);}
        assert(hardwareFrames==frames&&calls==rawCalls&&hardwareLiveEvents.empty());
        const bool valid=args.count>=2&&[args[0] intValue]>=0&&[args[1] intValue]>0;
        const bool cleanup=valid&&[args[0] intValue]==0;
        assert(licenseCalls==gates+(valid&&!cleanup?1:0));
        if(!frames.empty())assert(hardwareObservedBudget&&!hardwareObservedBudget->capturesResponse()&&hardwareObservedBudget->response().capacity()==0&&hardwareObservedBudget->cleanup()==cleanup);
    };
    for(int action:{0,1,2,10,INT_MAX})for(int key=1;key<=4;++key){
        parity(@[@(action),@(key)],1024);parity(@[@(action),@(key)],3);parity(@[@(action),@(key)],2);
    }
    for(NSArray *args in @[@[],@[@1],@[@(-1),@1],@[@1,@0],@[@1,@5],@[@1,@(INT_MAX)],@[@0,@5],@[@1.9,@2.9],@[@(-0.9),@1],@[@" 2x",@"+3"],@[@"bad",@"4"]])parity(args,1024);
    // Both RAW parsers retain Foundation field normalization and ignored suffixes.
    for(NSString *text in @[@"",@"1",@"-1;;1",@"0;;4",@"99;;2",@"bad;;4",@"1;;0",@"1;;2147483647",@"1;;2;;ignored",@" 1;;+3"]){
        hardwareFrames.clear();NSError *oldError=nil;int expected=legacySendHardwareKeyEventFromRawData((UInt8 *)text.UTF8String,&oldError);const auto frames=hardwareFrames;
        hardwareFrames.clear();NSError *error=nil;int actual=sendHardwareKeyEventFromRawData((UInt8 *)text.UTF8String,&error);
        assert(actual==expected&&hardwareFrames==frames&&hardwareLiveEvents.empty());
        assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
    }
    auto context=parent();reset(context);int gates=licenseCalls;
    licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@1,@1],context).value,@"license_required task=30");assert(hardwareFrames.empty()&&licenseCalls==gates+1);
    context=parent();reset(context);licenseAllowed=false;gates=licenseCalls;
    assert([invoke(@[@0,@1],context).value[@"ok"] boolValue]&&hardwareFrames.size()==1&&licenseCalls==gates);
    context=parent();reset(context);licenseAllowed=false;
    failure(invoke(@[@2,@1],context).value,@"license_required task=30");assert(hardwareFrames.empty());
    context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
    failure(invoke(@[@1,@1],context).value,@"AbortError");assert(hardwareFrames.empty()&&licenseCalls==gates);
    assert([invoke(@[@0,@1],context).value[@"ok"] boolValue]&&hardwareFrames.size()==1&&licenseCalls==gates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
    failure(invoke(@[@2,@1],context).value,@"TimeoutError");assert(hardwareFrames.empty());
    assert([invoke(@[@0,@1],context).value[@"ok"] boolValue]&&hardwareFrames.size()==1);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@1,@1],context).value,@"AbortError");assert(hardwareFrames.empty());
    context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(@[@1,@1],context).value,@"TimeoutError");assert(hardwareFrames.empty());
    for(unsigned fault:{1U,2U,3U,4U,5U,6U}){
        hardwareDropClients();context=parent();reset(context);hardwareFault=fault;
        NSDictionary *result=invoke(@[@1,@1],context).value;
        if(fault<=2)assert(![result[@"ok"] boolValue]);else failure(result,@"native_exception");
        assert(hardwareLiveEvents.empty()&&hardwareFrames.size()==(fault>=5?1U:0U));
    }
    // The actual press body must release even after DOWN commits and then aborts.
    TLinkJSNativeRequest *press=[[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodPressHardwareKey arguments:@[@1]];
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;gates=licenseCalls;
    hardwareOnDispatch=[token](const HardwareFrame &frame){if(frame.down)[token cancel];};
    failure([bridge executeRequest:press context:context error:nil].value,@"AbortError");
    assert(hardwareFrames.size()==2&&hardwareFrames[0].down&&!hardwareFrames[1].down&&licenseCalls==gates+1&&hardwareLiveEvents.empty());
    context=parent(0.05);reset(context);
    failure([bridge executeRequest:press context:context error:nil].value,@"TimeoutError");assert(hardwareFrames.size()==2&&!hardwareFrames.back().down);
    for(unsigned fault:{3U,4U,5U,6U}){
        context=parent();reset(context);hardwareFault=fault;
        NSDictionary *result=[bridge executeRequest:press context:context error:nil].value;failure(result,@"native_exception");
        assert(hardwareLiveEvents.empty()&&hardwareFrames.size()==(fault>=5?2U:0U));
    }
    context=parent(1,2);reset(context);gates=licenseCalls;
    failure([bridge executeRequest:press context:context error:nil].value,@"response_too_large");
    assert(hardwareFrames.size()==2&&!hardwareFrames.back().down&&licenseCalls==gates+1);
    context=parent();reset(context);NSDictionary *pressed=[bridge executeRequest:press context:context error:nil].value;
    assert([pressed[@"ok"] boolValue]&&[pressed[@"down"][@"ok"] boolValue]&&hardwareFrames.size()==2&&!hardwareFrames.back().down);
    gates=licenseCalls;const size_t events=hardwareFrames.size();
    failure(TLinkExecuteNativeHardwareKey(-1,1,parent()),@"invalid_payload");failure(TLinkExecuteNativeHardwareKey(1,0,parent()),@"invalid_payload");
    assert(licenseCalls==gates&&hardwareFrames.size()==events&&!TLinkCurrentNativeBudget());
    hardwareDropClients();hardwareFrames.clear();hardwareOnDispatch={};hardwareFault=0;hardwareObservedBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed hardware key passed: frozen wire/HID/reply/parser normalization, action-zero-only cleanup, task-30 gates, cancellation/deadline/output, actual press UP and merge, NS/C++ dispatch unwind, balanced events/clients and no typed RAW dispatch/response vector.");
}
