// Actual alert parser/CF owner/bridge; controlled notification UI with real owned CF tokens.
#include <CoreFoundation/CFUserNotification.h>
#include <algorithm>
static bool alertCreateFails=false;
static SInt32 alertCreateError=0,alertReceiveError=0;
static unsigned alertCreates=0,alertReceives=0,alertReleases=0,alertLogs=0,alertFault=0;
static NSString *alertFaultStage=nil;
static NSDictionary *alertAttributes=nil;
static CFTimeInterval alertWait=0;
static std::vector<CFTypeRef> alertOwned;
static std::vector<std::string> alertOrder;
static TLinkNativeBudgetPtr alertBudget;
static std::function<void(NSString *)> alertOnStage;
static void alertObserve(NSString *stage){
    alertOrder.push_back(stage.UTF8String);alertBudget=TLinkCurrentNativeBudget();assert(alertBudget&&!alertBudget->cleanup());
    if([stage isEqual:alertFaultStage]&&alertFault==1)[NSException raise:@"AlertFixture" format:@"provider throws"];
    if([stage isEqual:alertFaultStage]&&alertFault==2)throw std::runtime_error("alert provider throws");
    if(alertOnStage)alertOnStage(stage);
}
static CFUserNotificationRef alertCreate(CFAllocatorRef allocator,CFTimeInterval timeout,CFOptionFlags flags,SInt32 *error,CFDictionaryRef attributes){
    assert(!allocator&&timeout==0&&flags==kCFUserNotificationPlainAlertLevel&&error&&attributes);
    ++alertCreates;alertAttributes=[(__bridge NSDictionary *)attributes copy];alertObserve(@"create");*error=alertCreateError;
    if(alertCreateFails)return nullptr;
    CFStringRef token=CFStringCreateWithCString(kCFAllocatorDefault,"native-alert-fixture",kCFStringEncodingUTF8);assert(token);alertOwned.push_back(token);
    return (CFUserNotificationRef)token;
}
static SInt32 alertReceive(CFUserNotificationRef notification,CFTimeInterval timeout,CFOptionFlags *response){
    assert(response&&std::find(alertOwned.begin(),alertOwned.end(),notification)!=alertOwned.end());
    ++alertReceives;alertWait=timeout;alertObserve(@"receive");*response=0;return alertReceiveError;
}
static void alertRelease(CFTypeRef value){
    auto it=std::find(alertOwned.begin(),alertOwned.end(),value);assert(it!=alertOwned.end());
    alertOwned.erase(it);++alertReleases;alertOrder.push_back("release");CFRelease(value);
}
static void alertLog(NSString *format,...){(void)format;++alertLogs;alertObserve(@"log");}
void showAlertBox(NSString *,NSString *,int);
#define CFUserNotificationCreate alertCreate
#define CFUserNotificationReceiveResponse alertReceive
#define CFRelease alertRelease
#define NSLog alertLog
#include "AlertCoreUnderTest.inc"
void legacyShowAlertBox(NSString *,NSString *,int);
#define showAlertBox legacyShowAlertBox
#define showAlertBoxFromRawData legacyShowAlertBoxFromRawData
#include "fixtures/alert-core-legacy-v1.inc"
#undef showAlertBoxFromRawData
#undef showAlertBox
#undef NSLog
#undef CFRelease
#undef CFUserNotificationReceiveResponse
#undef CFUserNotificationCreate
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeAlertEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void alertLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_SHOW_ALERT_BOX;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=12\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define showAlertBoxFromRawData legacyShowAlertBoxFromRawData
#include "fixtures/alert-handler-legacy-v1.inc"
#undef showAlertBoxFromRawData
}
static void typedAlertCases(TLinkInProcessNativeBridge *bridge){
    mode=@"alertRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        assert(alertOwned.empty());alertCreateFails=false;alertCreateError=alertReceiveError=0;
        alertCreates=alertReceives=alertReleases=alertLogs=alertFault=0;alertFaultStage=nil;alertAttributes=nil;alertWait=0;alertOrder.clear();alertBudget.reset();alertOnStage={};
        clipboardOnDescription={};clipboardDescriptions=0;toastOnValue={};touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodAlert arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget()&&alertOwned.empty());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSUInteger cap,SInt32 creation=0,SInt32 receive=0){
        auto context=parent(30,cap);reset(context);alertCreateError=creation;alertReceiveError=receive;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyAlert:request(args) context:context];NSDictionary *attributes=alertAttributes;const auto order=alertOrder;
        const CFTimeInterval wait=alertWait;const unsigned creates=alertCreates,receives=alertReceives,releases=alertReleases,logs=alertLogs;const int gateDelta=licenseCalls-gates;assert(alertOwned.empty());
        context=parent(30,cap);reset(context);alertCreateError=creation;alertReceiveError=receive;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta&&alertOrder==order&&alertWait==wait&&alertCreates==creates&&alertReceives==receives&&alertReleases==releases&&alertLogs==logs);
        assert((attributes==alertAttributes)||[attributes isEqual:alertAttributes]);
        if(creates)assert(lastLicenseTask==12&&!alertBudget->capturesResponse()&&alertBudget->response().capacity()==0&&alertCreates==alertReleases);
    };
    for(unsigned n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"Title %u",n],[NSString stringWithFormat:@"Message %u 测试",n],@(int(n%9)-3)],4096);
    parity(@[],4096);parity(@[@"title"],4096);
    for(id value in @[@"",@"Ứng dụng 😀",@"line\r\n",@"a;",@";3",@";",@"a;;b",@"a;;b;;-2",@"a;;b;;bad",@";;3",[NSNull null],@17]){parity(@[value,@"body"],4096);parity(@[@"title",value],4096);}
    for(id duration in @[@(-1),@0,@1,@3.8,@INT_MAX,@"2.5",@"bad"])parity(@[@"title",@"body",duration],4096);
    for(bool legacy:{false,true}){
        auto context=parent();reset(context);unsigned exceptions=0;const int gates=licenseCalls;
        @try{if(legacy)[bridge legacyAlert:request(@[@"title",@"body",[NSNull null]]) context:context];else invoke(@[@"title",@"body",[NSNull null]],context);}
        @catch(NSException *exception){(void)exception;++exceptions;}
        assert(exceptions==1&&licenseCalls==gates&&!alertCreates&&!TLinkCurrentNativeBudget());
    }
    for(NSArray *args in @[@[@"a;;b",@"-1"],@[@"a;;b;;5",@"ignored"],@[@"a",@"b;;-3"],@[@"a",@"b;;0"]]){parity(args,4096);parity(args,3);parity(args,2);}
    for(NSString *title in @[@"",@"a;",@"a;;",@"a;;b;"])for(NSString *body in @[@";",@";3",@";;-2",@"b;"])parity(@[title,body,@3],4096);
    for(SInt32 creation:{SInt32(0),SInt32(7)})for(SInt32 receive:{SInt32(0),SInt32(-1)})parity(@[@"errors",@"body"],4096,creation,receive);
    for(NSString *unit in @[@"x",@"界"])for(bool header:{false,true}){
        NSString *exact=[@"" stringByPaddingToLength:8185 withString:unit startingAtIndex:0];
        parity(header?@[exact,@"",@3]:@[@"",exact,@3],4096);NSString *over=[exact stringByAppendingString:@"x"];
        parity(header?@[over,@"",@3]:@[@"",over,@3],4096);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];parity(@[nul,@"body"],4096);parity(@[@"title",nul],4096);
    const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(@[@"title",invalid],4096);
    NativeClipboardContentFixture *object=[NativeClipboardContentFixture new];object.value=@"description";parity(@[object,@17],4096);
    auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@"title",@"body"],context).value,@"license_required task=12");assert(!alertCreates);
    context=parent();reset(context);[context.cancellationToken cancel];failure(invoke(@[],context).value,@"AbortError");assert(!alertCreates);
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[],context).value,@"TimeoutError");assert(!alertCreates);
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[],context).value,@"AbortError");assert(!alertCreates);
    context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(@[],context).value,@"TimeoutError");assert(!alertCreates);
    for(NSString *stage in @[@"create",@"receive"]){
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;alertOnStage=[token,stage](NSString *point){if([point isEqual:stage])[token cancel];};
        failure(invoke(@[],context).value,@"AbortError");assert(alertCreates==1&&alertReceives==1&&alertReleases==1);
    }
    context=parent(0.1);reset(context);alertOnStage=[](NSString *stage){if([stage isEqualToString:@"receive"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
    failure(invoke(@[],context).value,@"TimeoutError");assert(alertCreates==1&&alertReleases==1);
    context=parent(1,2);reset(context);failure(invoke(@[],context).value,@"response_too_large");assert(alertCreates==1&&alertReleases==1);
    for(NSString *stage in @[@"create",@"receive",@"log"])for(unsigned fault:{1U,2U}){
        context=parent();reset(context);alertFault=fault;alertFaultStage=stage;if([stage isEqualToString:@"log"])alertReceiveError=1;
        failure(invoke(@[],context).value,@"native_exception");assert(alertOwned.empty()&&alertReleases==([stage isEqualToString:@"create"]?0U:1U));
    }
    for(SInt32 creation:{SInt32(0),SInt32(1)}){context=parent();reset(context);alertCreateFails=true;alertCreateError=creation;
        assert([invoke(@[],context).value[@"ok"] boolValue]&&alertCreates==1&&!alertReceives&&!alertReleases&&!alertLogs);}
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;clipboardOnDescription=[token]{[token cancel];};int gates=licenseCalls;
    failure(invoke(@[object,@"body"],context).value,@"AbortError");assert(clipboardDescriptions==1&&licenseCalls==gates&&!alertCreates);
    NativeToastValueFixture *duration=[NativeToastValueFixture new];duration.text=@"3";context=parent();reset(context);token=context.cancellationToken;toastOnValue=[token]{[token cancel];};gates=licenseCalls;
    failure(invoke(@[@"title",@"body",duration],context).value,@"AbortError");assert(licenseCalls==gates&&!alertCreates);
    context=parent();reset(context);NSMutableString *title=[@"snapshot" mutableCopy];alertOnStage=[title](NSString *stage){if([stage isEqualToString:@"create"])[title setString:@"mutated"];};
    NSDictionary *held=nil,*heldAttributes=nil;@autoreleasepool{held=invoke(@[title,@"body"],context).value;heldAttributes=alertAttributes;context=nil;}
    assert([held[@"ok"] boolValue]&&[heldAttributes[(__bridge NSString *)kCFUserNotificationAlertHeaderKey] isEqualToString:@"snapshot"]&&[title isEqualToString:@"mutated"]);
    // Complete RAW parser parity keeps malformed, zero and negative-duration behavior.
    for(NSString *raw in @[@"",@"a;;b",@"a;;b;;0",@"a;;b;;-2",@"a;;b;;1.5;;ignored",@"Ứng;;dụng;;3"]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);legacyShowAlertBoxFromRawData((UInt8 *)raw.UTF8String,&oldError);}
        NSDictionary *attributes=alertAttributes;const auto order=alertOrder;reset(context);
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);showAlertBoxFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert(order==alertOrder);assert((attributes==alertAttributes)||[attributes isEqual:alertAttributes]);assert(alertOwned.empty());
    }
    for(unsigned n=0;n<1000;++n){context=parent();reset(context);NSDictionary *result=invoke(@[@"cycle",@"body",@1],context).value;assert([result[@"ok"] boolValue]&&alertCreates==1&&alertReleases==1);}
    alertAttributes=nil;alertBudget.reset();alertFaultStage=nil;alertOnStage={};alertOrder.clear();clipboardOnDescription={};toastOnValue={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(alertOwned.empty()&&!TLinkCurrentNativeBudget());
    puts("Typed alert passed: actual CF owner/parser with frozen JS/RAW field/reply parity, defaults/legacy delimiter shifts, ingress/output/task-12 authority, opaque stop/fault effects, failed creation and 1000 balanced real CF lifecycles. No real alert displayed.");
}
