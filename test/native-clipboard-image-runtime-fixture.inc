// Actual file metadata/read/signature/parser/core; a controlled pasteboard receives the bytes.
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeClipboardImageEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedClipboardImageCases(TLinkInProcessNativeBridge *bridge){
    mode=@"clipboardTextRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        clipboardReadValues=@[@""];clipboardMissing=false;clipboardWritten=nil;clipboardImageItems=nil;clipboardReads=clipboardWrites=clipboardFault=clipboardDescriptions=0;
        clipboardFaultStage=nil;clipboardBudget.reset();clipboardOrder.clear();clipboardOnRead={};clipboardOnDescription={};clipboardNotification=nil;clipboardNotificationObserver={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodKeyboard arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,reset,request,invoke](NSArray *args,NSUInteger cap,bool missing=false)->NSUInteger{
        auto context=parent(30,cap);reset(context);clipboardMissing=missing;int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyClipboardImage:request(args) context:context];NSArray *items=clipboardImageItems;
        const auto order=clipboardOrder;const unsigned writes=clipboardWrites;const int gateDelta=licenseCalls-gates;
        context=parent(30,cap);reset(context);clipboardMissing=missing;gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);assert(actual.ok&&expected.ok&&[actual.value isEqual:expected.value]);
        assert(calls==rawCalls&&licenseCalls==gates+gateDelta&&clipboardOrder==order&&clipboardWrites==writes&&!clipboardNotification);
        assert((items==clipboardImageItems)||[items isEqual:clipboardImageItems]);
        if(!order.empty())assert(lastLicenseTask==24&&!clipboardBudget->capturesResponse()&&clipboardBudget->response().capacity()==0);
        return [actual.value[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    };
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"tlink-clipboard-image-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    NSError *fileError=nil;bool created=[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:false attributes:nil error:&fileError];assert(created&&!fileError);
    const unsigned char png[]={0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a},jpeg[]={0xff,0xd8,0xff,0},gif[]={'G','I','F','8','9','a'},webp[]={'R','I','F','F',0,0,0,0,'W','E','B','P'};
    NSArray *types=@[@"public.png",@"public.jpeg",@"com.compuserve.gif",@"org.webmproject.webp"];
    NSArray *data=@[[NSData dataWithBytes:png length:sizeof(png)],[NSData dataWithBytes:jpeg length:sizeof(jpeg)],[NSData dataWithBytes:gif length:sizeof(gif)],[NSData dataWithBytes:webp length:sizeof(webp)]];
    NSMutableArray *paths=[NSMutableArray array];
    for(NSUInteger i=0;i<data.count;++i){
        NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"Ảnh;;测试-%lu.bin",(unsigned long)i]];
        bool wrote=[data[i] writeToFile:path atomically:true];assert(wrote);[paths addObject:path];
    }
    NSString *valid=[@"file;;" stringByAppendingString:paths[0]];
    for(unsigned n=0;n<160;++n){NSString *content=[@"file;;" stringByAppendingString:paths[n%4]];parity(@[@8,content],4096);}
    for(NSUInteger i=0;i<paths.count;++i){
        NSString *content=[@"file;;" stringByAppendingString:paths[i]];const NSUInteger bytes=parity(@[@8,content],4096);
        assert([clipboardImageItems[0][types[i]] isEqual:data[i]]);parity(@[@8,content],bytes);parity(@[@8,content],bytes-1);parity(@[@8,content],4096,true);
    }
    for(id content in @[[NSNull null],@"",@"file",@"file;;",@"wrong;;",@"FILE;;missing",@";;path",@17])parity(@[@8,content],4096);
    parity(@[@8],4096);for(id kind in @[@8,@"8",@8.2])parity(@[kind,valid],4096);
    NSString *missing=[@"file;;" stringByAppendingString:[directory stringByAppendingPathComponent:@"missing"]];parity(@[@8,missing],4096);
    parity(@[@8,[@"file;;" stringByAppendingString:directory]],4096);
    NSArray *invalidData=@[[NSData data],[NSData dataWithBytes:png length:7],[NSData dataWithBytes:jpeg length:3],[NSData dataWithBytes:gif length:4],[NSData dataWithBytes:webp length:11],[@"unsupported" dataUsingEncoding:NSUTF8StringEncoding]];
    for(NSUInteger i=0;i<invalidData.count;++i){NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"invalid-%lu",(unsigned long)i]];
        bool wrote=[invalidData[i] writeToFile:path atomically:true];assert(wrote);parity(@[@8,[@"file;;" stringByAppendingString:path]],4096);
    }
    // Sparse files exercise the exact metadata preflight boundary; the accepted
    // 16-MiB read remains real. This preflight does not impose a post-read size cap.
    for(unsigned extra:{0U,1U}){@autoreleasepool{
        NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"limit-%u",extra]];
        bool wrote=[data[0] writeToFile:path atomically:true];assert(wrote);NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];assert(handle);
        [handle truncateFileAtOffset:16ULL*1024ULL*1024ULL+extra];[handle closeFile];
        parity(@[@8,[@"file;;" stringByAppendingString:path]],4096);auto context=parent();reset(context);
    }}
    for(NSString *unit in @[@"x",@"界"]){NSString *exact=[@"file;;" stringByPaddingToLength:8187 withString:unit startingAtIndex:0];
        parity(@[@8,exact],4096);parity(@[@8,[exact stringByAppendingString:@"x"]],4096);
    }
    NSString *nul=[NSString stringWithFormat:@"file;;before%Cafter",(unichar)0];parity(@[@8,nul],4096);
    const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];if(invalid)parity(@[@8,invalid],4096);
    NativeClipboardContentFixture *object=[NativeClipboardContentFixture new];object.value=valid;parity(@[@8,object],4096);
    auto context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
    failure(invoke(@[@8,valid],context).value,@"license_required task=24");assert(clipboardOrder.empty()&&!clipboardImageItems);
    context=parent();reset(context);[context.cancellationToken cancel];failure(invoke(@[@8,valid],context).value,@"AbortError");assert(clipboardOrder.empty());
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[@8,valid],context).value,@"TimeoutError");assert(clipboardOrder.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@8,valid],context).value,@"AbortError");assert(clipboardOrder.empty());
    context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(@[@8,valid],context).value,@"TimeoutError");assert(clipboardOrder.empty());
    for(NSString *stage in @[@"manager",@"itemsSet",@"imageCommitted"]){
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;clipboardOnRead=[token,stage](NSString *point){if([point isEqual:stage])[token cancel];};
        failure(invoke(@[@8,valid],context).value,@"AbortError");assert(clipboardWrites==1&&clipboardImageItems);
        for(unsigned fault:{1U,2U}){context=parent();reset(context);clipboardFault=fault;clipboardFaultStage=stage;
            failure(invoke(@[@8,valid],context).value,@"native_exception");assert((clipboardImageItems!=nil)==[stage isEqualToString:@"imageCommitted"]);}
    }
    context=parent(0.1);reset(context);clipboardOnRead=[](NSString *stage){if([stage isEqualToString:@"manager"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};
    failure(invoke(@[@8,valid],context).value,@"TimeoutError");assert(clipboardWrites==1);
    context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;clipboardOnDescription=[token]{[token cancel];};int gates=licenseCalls;
    failure(invoke(@[@8,object],context).value,@"AbortError");assert(clipboardDescriptions==1&&licenseCalls==gates&&clipboardOrder.empty());
    context=parent();reset(context);NSMutableString *source=[valid mutableCopy];clipboardOnRead=[source](NSString *stage){if([stage isEqualToString:@"manager"])[source setString:@"mutated"];};
    NSDictionary *held=nil;NSArray *heldItems=nil;@autoreleasepool{held=invoke(@[@8,source],context).value;heldItems=clipboardImageItems;context=nil;}
    assert([held[@"ok"] boolValue]&&[heldItems[0][@"public.png"] isEqual:data[0]]&&[source isEqualToString:@"mutated"]);
    // Complete RAW branch parity after extraction, including delimiter-joined paths.
    for(NSString *raw in @[@"8",@"8;;wrong;;path",@"8;;file;;",[@"8;;" stringByAppendingString:valid]]){
        context=parent();reset(context);NSError *oldError=nil,*error=nil;NSString *expected=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);expected=legacyClipboardInputTextFromRawData((UInt8 *)raw.UTF8String,&oldError);}
        NSArray *items=clipboardImageItems;const auto order=clipboardOrder;reset(context);NSString *actual=nil;
        {TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);actual=inputTextFromRawData((UInt8 *)raw.UTF8String,&error);}
        assert((expected==actual)||[expected isEqual:actual]);assert((oldError==error)||[oldError.localizedDescription isEqual:error.localizedDescription]);assert((items==clipboardImageItems)||[items isEqual:clipboardImageItems]);assert(order==clipboardOrder);
    }
    context=parent();reset(context);NSError *heldError=nil;@autoreleasepool{TLinkNativeBudgetScope scope([TLinkNativeCallContext(context,false,false) nativeBudget]);inputTextFromRawData((UInt8 *)"8;;file;;",&heldError);}assert([heldError.localizedDescription containsString:@"Clipboard image path cannot be empty."]);
    bool removed=[[NSFileManager defaultManager] removeItemAtPath:directory error:&fileError];assert(removed&&!fileError);
    clipboardReadValues=nil;clipboardImageItems=nil;clipboardBudget.reset();clipboardFaultStage=nil;clipboardOrder.clear();clipboardOnRead={};clipboardOnDescription={};clipboardNotificationObserver={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());
    puts("Typed clipboard image passed: actual file metadata/read/signatures and frozen JS/RAW byte/reply parity, four formats, empty/directory/missing/16-MiB boundaries, delimiter/Unicode paths, ingress/output/authority, accepted stop/fault/snapshots and lifetime. No real pasteboard changed.");
}
