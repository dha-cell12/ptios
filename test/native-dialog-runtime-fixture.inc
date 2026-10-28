// Actual dialog parser/core/state/bridge; controlled synchronous CF display boundary.
static NSString *lastDialogValue=@"",*legacyLastDialogValue=@"";
static unsigned dialogDisplays=0,dialogFault=0;
static SInt32 dialogReturnCode=0;
static CFOptionFlags dialogResponse=0;
static bool dialogWritesResponse=true;
static NSArray *dialogFields=nil;
static TLinkNativeBudgetPtr dialogBudget;
static std::function<void()> dialogOnDisplay;
static SInt32 dialogDisplay(CFTimeInterval timeout,CFOptionFlags flags,CFURLRef icon,CFURLRef sound,CFURLRef localization,
    CFStringRef title,CFStringRef message,CFStringRef ok,CFStringRef cancel,CFStringRef other,CFOptionFlags *response){
    assert(timeout==0&&flags==kCFUserNotificationNoteAlertLevel&&!icon&&!sound&&!localization&&!other&&response&&*response==0);
    ++dialogDisplays;dialogBudget=TLinkCurrentNativeBudget();assert(dialogBudget&&!dialogBudget->cleanup());
    dialogFields=@[[(__bridge NSString *)title copy],[(__bridge NSString *)message copy],[(__bridge NSString *)ok copy],[(__bridge NSString *)cancel copy]];
    if(dialogFault==1)[NSException raise:@"DialogFixture" format:@"display throws"];
    if(dialogFault==2)throw std::runtime_error("dialog display throws");
    if(dialogOnDisplay)dialogOnDisplay();
    if(dialogWritesResponse)*response=dialogResponse;
    return dialogReturnCode;
}
NSString* TLinkShowDialog(NSString *,NSString *,NSString *,NSString *);
#define CFUserNotificationDisplayAlert dialogDisplay
#include "DialogCoreUnderTest.inc"
#define lastDialogValue legacyLastDialogValue
#define dialogFromRawData legacyDialogFromRawData
#define clearDialogValues legacyClearDialogValues
#include "LegacyDialogCore.inc"
#undef clearDialogValues
#undef dialogFromRawData
#undef lastDialogValue
#undef CFUserNotificationDisplayAlert
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeDialogEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void dialogLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define dialogFromRawData legacyDialogFromRawData
#define clearDialogValues legacyClearDialogValues
#include "fixtures/dialog-handler-legacy-v1.inc"
#undef clearDialogValues
#undef dialogFromRawData
}
static void typedDialogCases(TLinkInProcessNativeBridge *bridge){
    mode=@"dialogRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        lastDialogValue=legacyLastDialogValue=@"seed";dialogDisplays=dialogFault=0;dialogReturnCode=0;dialogResponse=0;dialogWritesResponse=true;
        dialogFields=nil;dialogBudget.reset();dialogOnDisplay={};clipboardOnDescription={};clipboardDescriptions=0;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](bool clear,NSArray *args)->TLinkJSNativeRequest *{
        return [[TLinkJSNativeRequest alloc] initWithMethod:clear?TLinkJSNativeMethodClearDialogValues:TLinkJSNativeMethodDialog arguments:args];
    };
    const auto invoke=[bridge,request](bool clear,NSArray *args,TLinkTaskExecutionContext *context)->NSDictionary *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(clear,args) context:context error:nil];assert(result.ok&&!TLinkCurrentNativeBudget());return result.value;
    };
    const auto parity=[bridge,reset,request,invoke](bool clear,NSArray *args,CFOptionFlags response,NSUInteger cap,SInt32 code=0,bool write=true){
        auto context=parent(30,cap);reset(context);dialogResponse=response;dialogReturnCode=code;dialogWritesResponse=write;int gates=licenseCalls;
        NSDictionary *expected=[bridge legacyDialog:request(clear,args) context:context].value;
        NSString *state=legacyLastDialogValue;NSArray *fields=dialogFields;const unsigned displays=dialogDisplays;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context);dialogResponse=response;dialogReturnCode=code;dialogWritesResponse=write;gates=licenseCalls;const int rawCalls=calls;
        NSDictionary *actual=invoke(clear,args,context);assert([actual isEqual:expected]&&[lastDialogValue isEqual:state]);
        assert((fields==dialogFields)||[fields isEqual:dialogFields]);assert(dialogDisplays==displays&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        if(gateDelta)assert(lastLicenseTask==(clear?43:42));
        if(displays)assert(dialogBudget&&!dialogBudget->capturesResponse()&&dialogBudget->response().capacity()==0);
    };
    for(unsigned n=0;n<160;++n)parity(false,@[[NSString stringWithFormat:@"Title %u",n],[NSString stringWithFormat:@"Message %u 测试",n],@"Yes",@"No"],n%4,4096);
    for(bool clear:{false,true}){parity(clear,@[],1,4096);parity(clear,@[@"title"],2,4096);parity(clear,@[@"title",@"body",@"ok",@"cancel",@"ignored"],3,4096);}
    for(NSUInteger column=0;column<4;++column)for(id value in @[@"",@"Ứng dụng 😀",@"line\r\n",@"a;",@";",@"a;;b;;c",@17,[NSNull null]]){
        NSMutableArray *args=[@[@"title",@"body",@"ok",@"cancel"] mutableCopy];args[column]=value;parity(false,args,2,4096);
    }
    for(NSString *title in @[@"",@"a;",@"a;;",@"a;;b;"])for(NSString *body in @[@";",@";3",@";;-2",@"b;"])parity(false,@[title,body,@"OK;",@";Cancel"],3,4096);
    for(CFOptionFlags response:{CFOptionFlags(0),CFOptionFlags(1),CFOptionFlags(2),CFOptionFlags(3),CFOptionFlags(UINT32_MAX),CFOptionFlags(1)<<63,CFOptionFlags(-1)}){
        parity(false,@[],response,4096);parity(false,@[],response,4096,-7);parity(false,@[],response,4096,-7,false);
        const NSUInteger bytes=[[NSString stringWithFormat:@"0;;%ld\r\n",(long)response] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        parity(false,@[],response,bytes);parity(false,@[],response,bytes-1);
    }
    parity(true,@[],0,3);parity(true,@[],0,2);
    for(NSUInteger column=0;column<4;++column)for(NSString *unit in @[@"x",@"界"]){
        NSMutableArray *args=[@[@"",@"",@"",@""] mutableCopy];NSString *exact=[@"" stringByPaddingToLength:8184 withString:unit startingAtIndex:0];
        args[column]=exact;parity(false,args,1,4096);args[column]=[exact stringByAppendingString:@"x"];parity(false,args,1,4096);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    for(NSUInteger column=0;column<4;++column){NSMutableArray *args=[@[@"t",@"b",@"o",@"c"] mutableCopy];args[column]=nul;parity(false,args,1,4096);
        if(invalid){args[column]=invalid;parity(false,args,1,4096);}}
    if(invalid)parity(false,@[invalid,[@"" stringByPaddingToLength:8192 withString:@"x" startingAtIndex:0],@"",@""],1,4096);
    NativeClipboardContentFixture *object=[NativeClipboardContentFixture new];object.value=@"description";
    parity(false,@[object,@17,object,@"cancel"],1,4096);parity(true,@[object],1,4096);assert(clipboardDescriptions==0);
    for(bool clear:{false,true}){
        auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(clear,@[],context),clear?@"license_required task=43":@"license_required task=42");assert(!dialogDisplays&&[lastDialogValue isEqualToString:@"seed"]);
        context=parent();reset(context);int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(clear,@[],context),@"AbortError");assert(licenseCalls==gates&&!dialogDisplays&&[lastDialogValue isEqualToString:@"seed"]);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];
        failure(invoke(clear,@[],context),@"TimeoutError");assert(licenseCalls==gates&&!dialogDisplays&&[lastDialogValue isEqualToString:@"seed"]);
        context=parent();reset(context);stopInLicense=true;failure(invoke(clear,@[],context),@"AbortError");assert(!dialogDisplays&&[lastDialogValue isEqualToString:@"seed"]);
        context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(clear,@[],context),@"TimeoutError");assert(!dialogDisplays&&[lastDialogValue isEqualToString:@"seed"]);
        context=parent(1,2);reset(context);failure(invoke(clear,@[],context),@"response_too_large");assert(dialogDisplays==(clear?0U:1U)&&[lastDialogValue isEqualToString:clear?@"":@"0"]);
    }
    auto context=parent();reset(context);dialogResponse=2;TLinkCancellationToken *token=context.cancellationToken;dialogOnDisplay=[token]{[token cancel];};
    failure(invoke(false,@[],context),@"AbortError");assert(dialogDisplays==1&&[lastDialogValue isEqualToString:@"2"]);
    context=parent(0.1);reset(context);dialogResponse=3;dialogOnDisplay=[]{std::this_thread::sleep_for(std::chrono::milliseconds(150));};
    failure(invoke(false,@[],context),@"TimeoutError");assert(dialogDisplays==1&&[lastDialogValue isEqualToString:@"3"]);
    for(unsigned fault:{1U,2U}){context=parent();reset(context);dialogFault=fault;failure(invoke(false,@[],context),@"native_exception");assert(dialogDisplays==1&&[lastDialogValue isEqualToString:@"seed"]);}
    context=parent();reset(context);token=context.cancellationToken;clipboardOnDescription=[token]{[token cancel];};const int gates=licenseCalls;
    failure(invoke(false,@[object],context),@"AbortError");assert(clipboardDescriptions==1&&licenseCalls==gates&&!dialogDisplays);
    context=parent();reset(context);NSMutableString *title=[@"snapshot" mutableCopy];dialogResponse=2;dialogOnDisplay=[title]{[title setString:@"changed"];};
    NSDictionary *held=nil;NSArray *heldFields=nil;@autoreleasepool{held=invoke(false,@[title,@"body",@"ok",@"cancel"],context);heldFields=dialogFields;context=nil;}
    assert([held[@"ok"] boolValue]&&[held[@"response"] intValue]==2&&[heldFields[0] isEqualToString:@"snapshot"]&&[title isEqualToString:@"changed"]);
    // Standalone RAW parser retains missing-field defaults and leaves NSError untouched.
    for(NSString *raw in @[@"",@"a",@"a;;b",@"a;;b;;c",@"a;;b;;c;;d;;ignored",@"a;;;b;;;;d",@"Ứng;;dụng;;OK;;Cancel"]){
        context=parent();reset(context);dialogResponse=3;NSError *sentinel=[NSError errorWithDomain:@"fixture" code:7 userInfo:nil],*oldError=sentinel,*error=sentinel;
        NSString *expected=nil,*actual=nil;{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);expected=legacyDialogFromRawData((UInt8 *)raw.UTF8String,&oldError);}
        NSArray *fields=dialogFields;reset(context);dialogResponse=3;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);actual=dialogFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert([actual isEqual:expected]&&[fields isEqual:dialogFields]&&oldError==sentinel&&error==sentinel);
        legacyClearDialogValues(&oldError);clearDialogValues(&error);assert(oldError==sentinel&&error==sentinel&&lastDialogValue.length==0&&legacyLastDialogValue.length==0);
    }
    for(unsigned n=0;n<1000;++n){context=parent();reset(context);dialogResponse=n%4;assert([invoke(false,@[],context)[@"ok"] boolValue]);assert([invoke(true,@[],context)[@"ok"] boolValue]&&dialogDisplays==1&&lastDialogValue.length==0);}
    dialogFields=nil;lastDialogValue=legacyLastDialogValue=@"";dialogBudget.reset();dialogOnDisplay={};clipboardOnDescription={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed dialog/clear passed: actual parser/CF display core/state and frozen JS/RAW parity, defaults/semicolon overlaps/response metadata, ingress/output/task-42/43 gates, opaque stop/fault effects, snapshots and 1000 repeated lifecycles. No real dialog displayed.");
}
