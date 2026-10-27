// Actual UIDevice/model formatting, RAW parser and numeric entry; controlled device/uname boundaries.
#include <sys/utsname.h>
#include <limits>
static NSArray *deviceInfoFields=nil;
static std::string deviceInfoMachine="FixtureModel1,2";
static int deviceInfoState=0,deviceInfoFaultStage=-1;
static float deviceInfoLevel=0;
static bool deviceInfoMissing=false,deviceInfoMonitoring=false;
static unsigned deviceInfoFault=0;
static std::vector<int> deviceInfoOrder;
static TLinkNativeBudgetPtr deviceInfoBudget;
static std::function<void(int)> deviceInfoOnRead;
static void deviceInfoObserve(int stage){
    deviceInfoOrder.push_back(stage);deviceInfoBudget=TLinkCurrentNativeBudget();assert(deviceInfoBudget&&!deviceInfoBudget->cleanup());
    if(stage==deviceInfoFaultStage&&deviceInfoFault==1)[NSException raise:@"DeviceInfoFixture" format:@"provider throws"];
    if(stage==deviceInfoFaultStage&&deviceInfoFault==2)throw std::runtime_error("device provider throws");
    if(deviceInfoOnRead)deviceInfoOnRead(stage);
}
@interface NativeDeviceInfoFixture : NSObject
+ (instancetype)currentDevice;
- (NSString *)name;
- (NSString *)systemName;
- (NSString *)systemVersion;
- (id)identifierForVendor;
- (void)setBatteryMonitoringEnabled:(BOOL)enabled;
- (int)batteryState;
- (float)batteryLevel;
@end
@implementation NativeDeviceInfoFixture
+ (instancetype)currentDevice {
    deviceInfoObserve(0);if(deviceInfoMissing)return nil;static NativeDeviceInfoFixture *device=nil;
    if(!device)device=[NativeDeviceInfoFixture new];return device;
}
- (NSString *)name {deviceInfoObserve(1);id value=deviceInfoFields[0];return value==[NSNull null]?nil:value;}
- (NSString *)systemName {deviceInfoObserve(2);id value=deviceInfoFields[1];return value==[NSNull null]?nil:value;}
- (NSString *)systemVersion {deviceInfoObserve(3);id value=deviceInfoFields[2];return value==[NSNull null]?nil:value;}
- (id)identifierForVendor {deviceInfoObserve(5);id value=deviceInfoFields[3];return value==[NSNull null]?nil:value;}
- (void)setBatteryMonitoringEnabled:(BOOL)enabled {assert(enabled);deviceInfoObserve(6);deviceInfoMonitoring=true;deviceInfoObserve(9);}
- (int)batteryState {deviceInfoObserve(7);return deviceInfoState;}
- (float)batteryLevel {deviceInfoObserve(8);return deviceInfoLevel;}
@end
static int deviceInfoUname(struct utsname *info){
    deviceInfoObserve(4);assert(info&&deviceInfoMachine.size()<sizeof(info->machine));memset(info,0,sizeof(*info));
    memcpy(info->machine,deviceInfoMachine.data(),deviceInfoMachine.size());return 0;
}
#define UIDevice NativeDeviceInfoFixture
#define uname deviceInfoUname
#include "DeviceInfoCoreUnderTest.inc"
#define modelName legacyDeviceInfoModelName
#define getDeviceInfoFromRawData legacyGetDeviceInfoFromRawData
#include "fixtures/device-info-core-legacy-v1.inc"
#undef getDeviceInfoFromRawData
#undef modelName
#undef uname
#undef UIDevice
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeDeviceInfoEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void deviceInfoLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_GET_DEVICE_INFO;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=25\r\n",writeStreamRef);return;}
    if(false){}
#define getDeviceInfoFromRawData legacyGetDeviceInfoFromRawData
#include "fixtures/device-info-handler-legacy-v1.inc"
#undef getDeviceInfoFromRawData
}
static void typedDeviceInfoCases(TLinkInProcessNativeBridge *bridge){
    mode=@"deviceInfoRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,bool missing=false){
        deviceInfoMissing=missing;deviceInfoMonitoring=false;deviceInfoOrder.clear();deviceInfoBudget.reset();
        deviceInfoFault=0;deviceInfoFaultStage=-1;deviceInfoOnRead={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](int selector,NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:selector==30?TLinkJSNativeMethodInfo:TLinkJSNativeMethodBatteryInfo arguments:args];};
    const auto invoke=[bridge,request](int selector,NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(selector,args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto same=[](NSDictionary *left,NSDictionary *right){
        // NaN is not numerically equal to itself; the wire and other metadata still compare exactly.
        if(left[@"level"]&&right[@"level"]&&std::isnan([left[@"level"] doubleValue])&&std::isnan([right[@"level"] doubleValue])){
            NSMutableDictionary *a=[left mutableCopy],*b=[right mutableCopy];a[@"level"]=@"nan";b[@"level"]=@"nan";assert([a isEqual:b]);
        }else assert([left isEqual:right]);
    };
    const auto parity=[bridge,request,invoke,reset,same](int selector,NSArray *args,bool missing,NSUInteger cap)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context,missing);const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyDeviceInfo:request(selector,args) context:context];const auto order=deviceInfoOrder;const bool monitoring=deviceInfoMonitoring;const int gateDelta=licenseCalls-oldGates;
        context=parent(1,cap);reset(context,missing);const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(selector,args,context);assert(actual.ok&&expected.ok);same(actual.value,expected.value);
        assert(deviceInfoOrder==order&&deviceInfoMonitoring==monitoring&&licenseCalls==gates+gateDelta&&calls==rawCalls&&lastLicenseTask==TASK_GET_DEVICE_INFO);
        if(!order.empty())assert(!deviceInfoBudget->capturesResponse()&&deviceInfoBudget->response().capacity()==0&&!deviceInfoBudget->cleanup());
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:@"12345678-1234-4321-ABCD-123456789ABC"];
    NSArray *ordinary=@[@"Fixture phone",@"iOS",@"17.0",uuid];deviceInfoFields=ordinary;
    for(int n=0;n<160;++n){deviceInfoState=n%5;deviceInfoLevel=float(n%101)/100;parity(n%2?30:31,@[],bool(n%7==0),4096);}
    for(int selector:{30,31})for(bool missing:{false,true}){
        const NSUInteger bytes=parity(selector,@[],missing,4096);parity(selector,@[],missing,bytes);parity(selector,@[],missing,bytes-1);
        parity(selector,@[[NSNull null],@"ignored",@17],missing,4096);
    }
    NSString *nul=[NSString stringWithFormat:@"visible%Cignored",(unichar)0];const unichar invalidUTF16=0xd800;
    NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *edges=[@[[NSNull null],@"",@"Ứng dụng.测试",@"a;;b",@"a\r\n",@"a\u2028",nul,@17] mutableCopy];if(invalid)[edges addObject:invalid];
    for(id value in edges)for(NSUInteger field=0;field<4;++field){NSMutableArray *fields=[ordinary mutableCopy];fields[field]=value;deviceInfoFields=fields;parity(30,@[],false,4096);}
    deviceInfoFields=ordinary;
    for(const std::string &machine:{std::string(""),std::string("Fixture9,9"),std::string("a;;b"),std::string("\xff"),std::string("head\0tail",9)}){deviceInfoMachine=machine;parity(30,@[],false,4096);}
    deviceInfoMachine="FixtureModel1,2";
    for(int state:{0,-1,1,2,3,INT_MIN,INT_MAX})for(float level:{-1.0f,-0.0f,0.0f,0.1234567f,0.9999999f,1.0f,2.0f,std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity(),-std::numeric_limits<float>::infinity()}){
        deviceInfoState=state;deviceInfoLevel=level;const NSUInteger bytes=parity(31,@[],false,4096);parity(31,@[],false,bytes);parity(31,@[],false,bytes-1);
    }
    deviceInfoState=2;deviceInfoLevel=0.75f;
    for(int selector:{30,31}){
        auto context=parent();reset(context);int gates=licenseCalls;licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(selector,@[],context).value,@"license_required task=25");assert(deviceInfoOrder.empty()&&!deviceInfoMonitoring&&licenseCalls==gates+1);
        context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
        failure(invoke(selector,@[],context).value,@"AbortError");assert(deviceInfoOrder.empty()&&licenseCalls==gates);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
        failure(invoke(selector,@[],context).value,@"TimeoutError");assert(deviceInfoOrder.empty()&&licenseCalls==gates);
        context=parent();reset(context);stopInLicense=true;failure(invoke(selector,@[],context).value,@"AbortError");assert(deviceInfoOrder.empty());
        context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(selector,@[],context).value,@"TimeoutError");assert(deviceInfoOrder.empty());
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;deviceInfoOnRead=[token](int stage){if(stage==0)[token cancel];};
        failure(invoke(selector,@[],context).value,@"AbortError");assert(!deviceInfoOrder.empty()&&deviceInfoMonitoring==(selector==31));
        context=parent(0.01);reset(context);deviceInfoOnRead=[](int stage){if(stage==0)std::this_thread::sleep_for(std::chrono::milliseconds(30));};failure(invoke(selector,@[],context).value,@"TimeoutError");
        context=parent(1,2);reset(context);failure(invoke(selector,@[],context).value,@"response_too_large");assert(deviceInfoMonitoring==(selector==31));
    }
    for(unsigned fault:{1U,2U})for(int stage:{0,1,2,3,4,5,6,9,7,8}){
        auto context=parent();reset(context);deviceInfoFault=fault;deviceInfoFaultStage=stage;
        const int selector=stage>=6?31:30;failure(invoke(selector,@[],context).value,@"native_exception");assert(deviceInfoMonitoring==(stage>=7));
    }
    for(NSString *raw in @[@"1",@"2",@"3",@"30",@"31",@"030;;ignored",@"31junk",@"99",@"bad",nul]){
        auto context=parent();reset(context);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil;
        NSString *expected=legacyGetDeviceInfoFromRawData((UInt8 *)raw.UTF8String,&oldError);const auto order=deviceInfoOrder;const bool monitoring=deviceInfoMonitoring;
        reset(context);NSError *error=nil;NSString *actual=getDeviceInfoFromRawData((UInt8 *)raw.UTF8String,&error);
        assert([actual isEqual:expected]&&deviceInfoOrder==order&&deviceInfoMonitoring==monitoring);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
    }
    for(int selector:{0,1,2,3,29,32,99}){auto context=parent();reset(context);const int gates=licenseCalls;failure(TLinkExecuteNativeDeviceInfo(selector,context),@"invalid_payload");assert(deviceInfoOrder.empty()&&licenseCalls==gates);}
    auto context=parent();reset(context);NSError *heldError=nil;@autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);getDeviceInfoForTask(99,&heldError);}assert(heldError.localizedDescription.length>0);
    for(int selector:{30,31}){context=parent();reset(context);deviceInfoFields=ordinary;NSDictionary *held=nil;@autoreleasepool{held=invoke(selector,@[],context).value;context=nil;deviceInfoFields=nil;}assert([held[@"ok"] boolValue]&&[held[@"parts"] count]>1);}
    deviceInfoFields=nil;deviceInfoMachine.clear();deviceInfoOrder.clear();deviceInfoOnRead={};deviceInfoBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed device info/battery passed: actual numeric core/RAW/model with frozen bridge/task parity, provider order, ignored arguments, metadata delimiter/NUL/encoding, signed state/float percent/output, ordinary task-25 authority, monitoring/stop/fault and pool lifetime. UIDevice/device qualification pending.");
}
