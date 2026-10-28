// Actual clipboard primitives/RAW parser and direct entry; controlled pasteboard/notification boundary.
static NSArray *clipboardReadValues=nil;
static NSString *clipboardWritten=nil;
static bool clipboardMissing=false;
static unsigned clipboardReads=0,clipboardWrites=0,clipboardFault=0;
static NSString *clipboardFaultStage=nil;
static TLinkNativeBudgetPtr clipboardBudget;
static std::vector<std::string> clipboardOrder;
static std::function<void(NSString *)> clipboardOnRead;
static std::function<void()> clipboardOnDescription;
static unsigned clipboardDescriptions=0;
static void clipboardObserve(NSString *stage){
    clipboardOrder.push_back(stage.UTF8String);clipboardBudget=TLinkCurrentNativeBudget();assert(clipboardBudget&&!clipboardBudget->cleanup());
    if([stage isEqual:clipboardFaultStage]&&clipboardFault==1)[NSException raise:@"ClipboardFixture" format:@"pasteboard throws"];
    if([stage isEqual:clipboardFaultStage]&&clipboardFault==2)throw std::runtime_error("pasteboard throws");
    if(clipboardOnRead)clipboardOnRead(stage);
}
@interface NativeClipboardPasteboardFixture : NSObject
+ (instancetype)generalPasteboard;
@property(nonatomic,copy) NSString *string;
@property(nonatomic,copy) NSArray *items;
@end
@implementation NativeClipboardPasteboardFixture
+ (instancetype)generalPasteboard {
    clipboardObserve(@"manager");if(clipboardMissing)return nil;
    static NativeClipboardPasteboardFixture *pasteboard=nil;if(!pasteboard)pasteboard=[NativeClipboardPasteboardFixture new];return pasteboard;
}
- (NSString *)string {
    clipboardObserve(@"get");const NSUInteger index=std::min(NSUInteger(clipboardReads++),clipboardReadValues.count-1);
    id value=clipboardReadValues[index];return value==[NSNull null]?nil:value;
}
- (void)setString:(NSString *)value {clipboardObserve(@"set");++clipboardWrites;clipboardWritten=[value copy];clipboardObserve(@"committed");}
@end
@interface NativeClipboardNotificationsFixture : NSObject
+ (instancetype)defaultCenter;
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)info deliverImmediately:(BOOL)immediately;
@end
static NSDictionary *clipboardNotification=nil;
static std::function<void(NSString *)> clipboardNotificationObserver;
@implementation NativeClipboardNotificationsFixture
+ (instancetype)defaultCenter {static NativeClipboardNotificationsFixture *center=nil;if(!center)center=[NativeClipboardNotificationsFixture new];return center;}
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)info deliverImmediately:(BOOL)immediately {
    assert([name isEqualToString:@"com.tlinkauto.tlinkauto.keyboardcontrol"]&&!object&&immediately);
    if(clipboardNotificationObserver)clipboardNotificationObserver(@"before");clipboardNotification=[info copy];
    if(clipboardNotificationObserver)clipboardNotificationObserver(@"committed");
}
@end
@interface NativeClipboardContentFixture : NSObject
@property(nonatomic,copy) NSString *value;
@end
@implementation NativeClipboardContentFixture
- (NSString *)description {++clipboardDescriptions;if(clipboardOnDescription)clipboardOnDescription();return self.value;}
@end
NSString *TLinkReadClipboardText(void);
void TLinkWriteClipboardText(NSString *text);
#define UIPasteboard NativeClipboardPasteboardFixture
#define NSDistributedNotificationCenter NativeClipboardNotificationsFixture
#include "ClipboardTextCoreUnderTest.inc"
#define kTLinkautoMaxClipboardImageBytes legacyClipboardMaxImageBytes
#define TLinkautoKeyboardError legacyClipboardKeyboardError
#define TLinkautoPasteboardImageType legacyClipboardImageType
#define inputTextFromRawData legacyClipboardInputTextFromRawData
#include "fixtures/clipboard-text-core-legacy-v1.inc"
#undef inputTextFromRawData
#undef TLinkautoPasteboardImageType
#undef TLinkautoKeyboardError
#undef kTLinkautoMaxClipboardImageBytes
#undef NSDistributedNotificationCenter
#undef UIPasteboard
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeClipboardTextEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void clipboardTextLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=TASK_TEXT_INPUT;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=24\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#define inputTextFromRawData legacyClipboardInputTextFromRawData
#include "fixtures/clipboard-text-handler-legacy-v1.inc"
#undef inputTextFromRawData
}
static void typedClipboardTextCases(TLinkInProcessNativeBridge *bridge){
    mode=@"clipboardTextRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,NSArray *reads){
        clipboardReadValues=reads;clipboardMissing=false;clipboardWritten=nil;clipboardReads=clipboardWrites=clipboardFault=clipboardDescriptions=0;
        clipboardFaultStage=nil;clipboardBudget.reset();clipboardOrder.clear();clipboardOnRead={};clipboardOnDescription={};clipboardNotification=nil;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodKeyboard arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSArray *reads,NSUInteger cap,bool missing=false)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(30,cap);reset(context,reads);clipboardMissing=missing;const int oldGates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyClipboardText:request(args) context:context];const auto order=clipboardOrder;
        NSString *written=clipboardWritten;const unsigned readCount=clipboardReads,writeCount=clipboardWrites,descriptions=clipboardDescriptions;const int gateDelta=licenseCalls-oldGates;
        context=parent(30,cap);reset(context,reads);clipboardMissing=missing;const int gates=licenseCalls,rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(clipboardOrder==order&&clipboardReads==readCount&&clipboardWrites==writeCount&&clipboardDescriptions==descriptions&&licenseCalls==gates+gateDelta&&calls==rawCalls);
        assert((written==clipboardWritten)||[written isEqual:clipboardWritten]);
        if(!order.empty())assert(lastLicenseTask==24&&!clipboardBudget->capturesResponse()&&clipboardBudget->response().capacity()==0);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSArray *ordinary=@[@"clipboard text"];
    for(unsigned n=0;n<160;++n){NSString *text=[NSString stringWithFormat:@"clip %u 测试",n];parity(n%2?@[@6]:@[@7,text],@[text],4096);}
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];
    NSArray *edges=@[@"",@"Ứng dụng 测试 😀",@"a;;b;;c",@";;",@"a\r\n",@"\n\r",nul,[NSNull null]];
    for(id value in edges){
        const NSUInteger bytes=parity(@[@6],@[value],4096);parity(@[@6],@[value],bytes);if(bytes>1)parity(@[@6],@[value],bytes-1);
        parity(@[@7,value],ordinary,4096);parity(@[@6,value],ordinary,4096);
    }
    parity(@[@6],@[@"first",@"second"],4096);parity(@[@6],@[@"first",[NSNull null]],4096);
    parity(@[@6],ordinary,4096,true);parity(@[@7,@""],ordinary,4096,true);parity(@[@7],ordinary,4096);parity(@[@7,[NSNull null]],ordinary,4096);
    for(id kind in @[@6,@7,@"6",@"7",@6.8,@7.2])parity(@[kind,@"a;;ignored"],ordinary,4096);
    NativeClipboardContentFixture *object=[NativeClipboardContentFixture new];object.value=@"object;;ignored";
    for(id content in @[@17,@{ @"value":@1 },@[@"one",@"two"],object])for(int kind:{6,7})parity(@[@(kind),content],ordinary,4096);
    for(int kind:{6,7})for(NSString *unit in @[@"x",@"界",@"😀"]){
        NSString *exact=[@"" stringByPaddingToLength:8187 withString:unit startingAtIndex:0];parity(@[@(kind),exact],ordinary,32768);
        parity(@[@(kind),[exact stringByAppendingString:@"x"]],ordinary,32768);
    }
    const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)for(int kind:{6,7})parity(@[@(kind),invalid],ordinary,4096);
    // Entire ignored suffix/content is admitted before truncation or GET.
    for(int kind:{6,7}){
        parity(@[@(kind),[@"a;;" stringByPaddingToLength:8188 withString:@"x" startingAtIndex:0]],ordinary,4096);
        auto context=parent();reset(context,ordinary);const int gates=licenseCalls;
        failure(TLinkExecuteNativeClipboardText(5,@"x",context),@"invalid_payload");assert(licenseCalls==gates&&clipboardOrder.empty());
        context=parent();reset(context,ordinary);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(@[@(kind),@"new"],context).value,@"license_required task=24");assert(clipboardOrder.empty());
        context=parent();reset(context,ordinary);[context.cancellationToken cancel];failure(invoke(@[@(kind),@"new"],context).value,@"AbortError");assert(clipboardOrder.empty());
        context=parent();reset(context,ordinary);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[@(kind),@"new"],context).value,@"TimeoutError");assert(clipboardOrder.empty());
        context=parent();reset(context,ordinary);stopInLicense=true;failure(invoke(@[@(kind),@"new"],context).value,@"AbortError");assert(clipboardOrder.empty());
        context=parent(0.1);reset(context,ordinary);licenseDelayMs=150;failure(invoke(@[@(kind),@"new"],context).value,@"TimeoutError");assert(clipboardOrder.empty());
        for(NSString *stage in (kind==6?@[@"manager",@"get"]:@[@"manager",@"set",@"committed"])){
            context=parent();reset(context,ordinary);TLinkCancellationToken *token=context.cancellationToken;clipboardOnRead=[token,stage](NSString *point){if([point isEqual:stage])[token cancel];};
            failure(invoke(@[@(kind),@"new"],context).value,@"AbortError");assert(clipboardWrites==(kind==7?1U:0U));
            for(unsigned fault:{1U,2U}){context=parent();reset(context,ordinary);clipboardFault=fault;clipboardFaultStage=stage;
                failure(invoke(@[@(kind),@"new"],context).value,@"native_exception");assert(clipboardWrites==([stage isEqualToString:@"committed"]?1U:0U));}
        }
        context=parent(0.1);reset(context,ordinary);clipboardOnRead=[](NSString *stage){if([stage isEqualToString:@"manager"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
        failure(invoke(@[@(kind),@"new"],context).value,@"TimeoutError");assert(clipboardWrites==(kind==7?1U:0U));
        context=parent(1,1);reset(context,ordinary);failure(invoke(@[@(kind),@"new"],context).value,@"response_too_large");assert(clipboardWrites==(kind==7?1U:0U));
    }
    for(bool native:{false,true}){
        auto context=parent();reset(context,ordinary);NSMutableString *source=[@"original;;ignored" mutableCopy];
        clipboardOnRead=[source](NSString *stage){if([stage isEqualToString:@"manager"])[source setString:@"mutated"];};
        TLinkJSNativeResponse *result=native?invoke(@[@7,source],context):[bridge legacyClipboardText:request(@[@7,source]) context:context];
        assert([result.value[@"ok"] boolValue]&&[clipboardWritten isEqualToString:@"original"]&&[source isEqualToString:@"mutated"]);
        context=parent();reset(context,ordinary);TLinkCancellationToken *token=context.cancellationToken;clipboardOnDescription=[token]{[token cancel];};
        const int gates=licenseCalls;result=native?invoke(@[@7,object],context):[bridge legacyClipboardText:request(@[@7,object]) context:context];
        failure(result.value,@"AbortError");assert(clipboardDescriptions==1&&licenseCalls==gates&&clipboardOrder.empty());
    }
    // Clipboard image kind retains RAW validation; notification kinds have their own direct fixture.
    for(NSArray *args in @[@[@8],@[@8,@"wrong;;path"]]){
        auto context=parent();reset(context,ordinary);TLinkJSNativeResponse *expected=[bridge legacyClipboardText:request(args) context:context];NSDictionary *notification=clipboardNotification;
        context=parent();reset(context,ordinary);const int rawCalls=calls;TLinkJSNativeResponse *actual=invoke(args,context);
        assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]&&calls==rawCalls+1);assert((notification==clipboardNotification)||[notification isEqual:clipboardNotification]);
    }
    // The shared RAW backend remains byte-compatible after primitive extraction.
    for(NSString *raw in @[@"6",@"6;;ignored",@"7",@"7;;",@"7;;a;;b",@"07;;text",@"bad",@"0;;a;;b",@"8",@"8;;wrong;;path"]){
        auto context=parent();reset(context,ordinary);TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil,*error=nil;
        NSString *expected=legacyClipboardInputTextFromRawData((UInt8 *)raw.UTF8String,&oldError);NSString *written=clipboardWritten;NSDictionary *notification=clipboardNotification;const auto order=clipboardOrder;
        reset(context,ordinary);NSString *actual=inputTextFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((expected==actual)||[expected isEqual:actual]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
        assert((written==clipboardWritten)||[written isEqual:clipboardWritten]);assert((notification==clipboardNotification)||[notification isEqual:clipboardNotification]);assert(clipboardOrder==order);
    }
    auto context=parent();reset(context,ordinary);NSDictionary *held=nil;@autoreleasepool{held=invoke(@[@6],context).value;context=nil;clipboardReadValues=nil;}
    assert([held[@"text"] isEqualToString:@"clipboard text"]);
    clipboardReadValues=nil;clipboardWritten=nil;clipboardBudget.reset();clipboardFaultStage=nil;clipboardOrder.clear();clipboardOnRead={};clipboardOnDescription={};clipboardNotification=nil;licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed clipboard text passed: actual primitives/parser, frozen JS/RAW reply/order/effect parity, getter rereads, delimiters/Unicode/NUL, missing/empty content, exact ingress/output, task-24 gates, committed stop/fault behavior, other keyboard RAW fallback and result lifetime. No real pasteboard changed.");
}
