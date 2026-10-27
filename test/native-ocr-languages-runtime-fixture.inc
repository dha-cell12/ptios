// Actual listing/filter/sort/base64/parser and direct bridge; controlled directory boundary.
static NSArray<NSString *> *ocrLanguageFiles=nil;
static NSString *ocrLanguageRealDirectory=nil;
static unsigned ocrLanguageReads=0,ocrLanguageFault=0;
static TLinkNativeBudgetPtr ocrLanguageBudget;
static std::function<void()> ocrLanguageOnRead;
static uint64_t ocrLanguageEnteredOffset=0;
@interface NativeOCRLanguageFileManagerFixture : NSObject
+ (instancetype)defaultManager;
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
@end
@implementation NativeOCRLanguageFileManagerFixture
+ (instancetype)defaultManager {
    static NativeOCRLanguageFileManagerFixture *manager=nil;
    if(!manager)manager=[NativeOCRLanguageFileManagerFixture new];return manager;
}
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    assert([path isEqualToString:@"/var/mobile/Library/TLinkauto/tessdata"]);
    ++ocrLanguageReads;ocrLanguageBudget=TLinkCurrentNativeBudget();assert(ocrLanguageBudget&&!ocrLanguageBudget->cleanup());
    if(ocrLanguageFault==1)[NSException raise:@"OCRLanguagesFixture" format:@"listing throws"];
    if(ocrLanguageFault==2)throw std::runtime_error("listing throws");
    if(ocrLanguageOnRead)ocrLanguageOnRead();
    if(ocrLanguageRealDirectory)return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ocrLanguageRealDirectory error:error];
    if(!ocrLanguageFiles&&error)*error=[NSError errorWithDomain:@"listing" code:1 userInfo:nil];
    return ocrLanguageFiles;
}
@end
#include "OCRLanguagesHelpersUnderTest.inc"
#define NSFileManager NativeOCRLanguageFileManagerFixture
#include "OCRLanguagesCoreUnderTest.inc"
#pragma push_macro("ENABLE_TESSERACT_OCR")
#undef ENABLE_TESSERACT_OCR
#define ENABLE_TESSERACT_OCR 0
#include "OCRLanguagesParserUnderTest.inc"
#define zx_tessBase64 legacyOCRLanguagesBase64
#define zx_tessError legacyOCRLanguagesError
#include "fixtures/ocr-languages-helpers-legacy-v1.inc"
#define zx_tessCheckLangs legacyOCRLanguagesCheck
#include "fixtures/ocr-languages-core-legacy-v1.inc"
#define handleTesseractOCRTaskFromRawData legacyHandleOCRLanguagesFromRawData
#include "fixtures/ocr-languages-parser-legacy-v1.inc"
#undef handleTesseractOCRTaskFromRawData
#undef zx_tessCheckLangs
#undef zx_tessError
#undef zx_tessBase64
#pragma pop_macro("ENABLE_TESSERACT_OCR")
#undef NSFileManager
// Advance only the admission timestamp, using the production duration/child-budget factory.
// This exercises accepted local overruns without spending three seconds per probe.
static TLinkNativeBudgetPtr ocrLanguagesC01Budget(const uint8_t *bytes,size_t length,TLinkNativeBudgetPtr parentBudget){
    assert(TLinkC01DurationNs(bytes,length)==3000000000ULL);
    const uint64_t now=TLinkNativeNowNs();assert(now>ocrLanguageEnteredOffset);
    return TLinkC01TaskBudget(bytes,length,std::move(parentBudget),now-ocrLanguageEnteredOffset);
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#define TLinkC01TaskBudget ocrLanguagesC01Budget
#include "NativeOCRLanguagesEntry.inc"
#undef TLinkC01TaskBudget
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void ocrLanguagesLegacyTask(UInt8 *bytes,size_t length,CFWriteStreamRef writeStreamRef){
    TLinkNativeBudgetScope scope(ocrLanguagesC01Budget(bytes,length,TLinkCurrentNativeBudget()));
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    const int taskType=TASK_OCR_TESSERACT_REGION;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));
    if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=91\r\n",writeStreamRef);return;}
    if(false){}
#define handleTesseractOCRTaskFromRawData legacyHandleOCRLanguagesFromRawData
#include "fixtures/ocr-languages-handler-legacy-v1.inc"
#undef handleTesseractOCRTaskFromRawData
}
static void typedOCRLanguagesCases(TLinkInProcessNativeBridge *bridge){
    mode=@"ocrLanguagesRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        if(![context nativeBudget])[context setNativeBudget:TLinkTaskBudget(context)];
        ocrLanguageFiles=@[@"vie.traineddata",@"eng.traineddata",@"README"];ocrLanguageRealDirectory=nil;
        ocrLanguageReads=ocrLanguageFault=0;ocrLanguageBudget.reset();ocrLanguageOnRead={};ocrLanguageEnteredOffset=0;
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodOcrLanguages arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *files,NSArray *args,NSUInteger cap)->NSUInteger{
        TLinkTaskExecutionContext *context=parent(30,cap);reset(context);ocrLanguageFiles=files;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyOCRLanguages:request(args) context:context];const int gateDelta=licenseCalls-gates;const unsigned reads=ocrLanguageReads;
        context=parent(30,cap);reset(context);ocrLanguageFiles=files;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(licenseCalls==gates+gateDelta&&lastLicenseTask==91&&ocrLanguageReads==reads&&calls==rawCalls);
        assert(ocrLanguageBudget&&!ocrLanguageBudget->capturesResponse()&&ocrLanguageBudget->response().capacity()==0&&!ocrLanguageBudget->cleanup());
        assert(ocrLanguageBudget->deadline()==licenseBudget->deadline()&&ocrLanguageBudget->deadline()<[context nativeBudget]->deadline());
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    for(unsigned n=0;n<160;++n){
        NSMutableArray *files=[NSMutableArray array];
        for(unsigned i=0;i<n%17;++i)[files addObject:[NSString stringWithFormat:@"lang%02u.%@",(i*13+n)%23,i%4?@"traineddata":@"TRAINEDDATA"]];
        parity(files,n%2?@[]:@[[NSNull null],@"ignored",@17],4096);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter.traineddata",(unichar)0];
    NSArray *edges=@[@"vie.traineddata",@"eng.traineddata",@"eng.traineddata",@"Ü测试.traineddata",@"a,b.traineddata",@"a;;b.traineddata",@"line\n.traineddata",nul,@"dir.traineddata",@"wrong.TRAINEDDATA",@"foo.traineddata.bak",@".traineddata",@""];
    const NSUInteger bytes=parity(edges,@[],4096);parity(edges,@[],bytes);parity(edges,@[],bytes-1);parity(nil,@[],4096);parity(@[],@[],4096);
    auto context=parent(30);reset(context);const uint64_t parentDeadline=[context nativeBudget]->deadline();const uint64_t before=TLinkNativeNowNs();
    NSDictionary *ordinary=invoke(@[],context).value;const uint64_t after=TLinkNativeNowNs();
    assert([ordinary[@"ok"] boolValue]&&[ordinary[@"value"] isEqualToString:@"eng,vie"]);
    assert(licenseBudget->deadline()>=before+3000000000ULL&&licenseBudget->deadline()<=after+3000000000ULL&&[context nativeBudget]->deadline()==parentDeadline);
    // Directory errors stay empty success; actual extension-only policy also includes directories.
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-native-ocr-languages-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSError *fileError=nil;assert([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:false attributes:nil error:&fileError]&&!fileError);
    for(NSString *name in @[@"eng.traineddata",@"vie.traineddata",@"README",@"wrong.TRAINEDDATA"]){
        bool created=[[NSFileManager defaultManager] createFileAtPath:[directory stringByAppendingPathComponent:name] contents:[NSData data] attributes:nil];assert(created);
    }
    bool created=[[NSFileManager defaultManager] createDirectoryAtPath:[directory stringByAppendingPathComponent:@"folder.traineddata"] withIntermediateDirectories:false attributes:nil error:&fileError];assert(created&&!fileError);
    context=parent(30);reset(context);ocrLanguageRealDirectory=directory;NSDictionary *real=invoke(@[],context).value;assert([real[@"value"] isEqualToString:@"eng,folder,vie"]);
    bool removed=[[NSFileManager defaultManager] removeItemAtPath:directory error:&fileError];assert(removed&&!fileError);
    context=parent(30);reset(context);ocrLanguageRealDirectory=directory;NSDictionary *missing=invoke(@[],context).value;
    assert([missing[@"ok"] boolValue]&&[missing[@"languages"] count]==0&&[missing[@"value"] isEqualToString:@""]);ocrLanguageRealDirectory=nil;
    // Compare RAW/direct gate, clock and NSException behavior. Escaping C++ faults
    // additionally receive the same guard used by the other typed entries.
    for(unsigned scenario=0;scenario<12;++scenario){
        NSDictionary *expected=nil;
        for(bool native:{false,true}){
            if(scenario==11&&!native)continue;
            context=parent(scenario==6||scenario==8?0.1:30);reset(context);const int gates=licenseCalls,rawCalls=calls;
            switch(scenario){
                case 0:licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};break;
                case 1:[context.cancellationToken cancel];break;
                case 2:[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];break;
                case 3:ocrLanguageEnteredOffset=3001000000ULL;break;
                case 4:ocrLanguageEnteredOffset=2900000000ULL;licenseDelayMs=150;break;
                case 5:stopInLicense=true;break;
                case 6:licenseDelayMs=150;break;
                case 7:{TLinkCancellationToken *token=context.cancellationToken;ocrLanguageOnRead=[token]{[token cancel];};break;}
                case 8:ocrLanguageOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(150));};break;
                case 9:ocrLanguageEnteredOffset=2900000000ULL;ocrLanguageOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(150));};break;
                case 10:ocrLanguageFault=1;break;
                case 11:ocrLanguageFault=2;break;
            }
            const uint64_t deadline=[context nativeBudget]->deadline();
            TLinkJSNativeResponse *response=native?invoke(@[],context):[bridge legacyOCRLanguages:request(@[]) context:context];
            assert(response.ok);if(!native)expected=response.value;else if(expected)assert([expected isEqual:response.value]);
            if(native)assert(calls==rawCalls);assert(!TLinkCurrentNativeBudget()&&[context nativeBudget]->deadline()==deadline);
            const bool preflight=scenario==1||scenario==2||scenario==3;
            assert(licenseCalls==gates+(preflight?0:1)&&ocrLanguageReads==((preflight||scenario==0)?0U:1U));
            switch(scenario){
                case 0:failure(response.value,@"license_required task=91");break;
                case 1:case 5:case 7:failure(response.value,@"AbortError");break;
                case 2:case 6:case 8:failure(response.value,@"TimeoutError");break;
                case 3:failure(response.value,@"native_cancelled_or_timed_out");break;
                case 4:case 9:assert([response.value[@"ok"] boolValue]&&ocrLanguageBudget->stopped()&&![context nativeBudget]->stopped());break;
                case 10:case 11:failure(response.value,@"native_exception");break;
            }
        }
    }
    // The unchanged RAW parser still recognizes trimmed/case-folded commands with OCR disabled.
    context=parent();reset(context);
    for(NSString *raw in @[@"check_langs",@" CHECK_LANGS \r\n",@"Check_Langs",@"",@"check_langs;;",@"other"]){
        TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);NSError *oldError=nil,*error=nil;
        NSString *old=legacyHandleOCRLanguagesFromRawData((UInt8 *)raw.UTF8String,&oldError);
        NSString *actual=handleTesseractOCRTaskFromRawData((UInt8 *)raw.UTF8String,&error);
        assert((old==actual)||[old isEqual:actual]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);
    }
    NSDictionary *held=nil;context=parent();reset(context);@autoreleasepool{held=invoke(@[],context).value;context=nil;ocrLanguageFiles=nil;}
    assert([held[@"languages"] isEqual:(@[@"eng",@"vie"])]&&[held[@"value"] isEqualToString:@"eng,vie"]);
    ocrLanguageFiles=nil;ocrLanguageBudget.reset();ocrLanguageOnRead={};ocrLanguageEnteredOffset=0;ocrLanguageFault=0;licenseDelayMs=0;stopInLicense=false;licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed OCR languages passed: actual filter/sort/base64 and disabled-engine parser, frozen JS/RAW parity, real temporary directory, extension/duplicate/empty/error rules, exact output, task-91 authority, C01 accepted overruns, caller stop/fault and pool lifetime. No OCR engine or real tessdata directory accessed.");
}
