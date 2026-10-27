// Controlled Process boundary; the bridge, task entry, context and reply sink are real.
static NSString *frontmostValue=nil;
static unsigned frontmostReads=0,frontmostFault=0;
static int frontmostReadTask=0;
static TLinkNativeBudgetPtr frontmostBudget;
static std::function<void()> frontmostOnRead;
static NSString *frontmostRead(int task){
    ++frontmostReads;frontmostReadTask=task;frontmostBudget=TLinkCurrentNativeBudget();
    assert(frontmostBudget&&!frontmostBudget->cleanup());
    if(!frontmostBudget->capturesResponse())assert(frontmostBudget->response().capacity()==0);
    if(frontmostFault==1)[NSException raise:@"FrontmostFixture" format:@"read throws"];
    if(frontmostFault==2)throw std::runtime_error("frontmost fixture");
    if(frontmostOnRead)frontmostOnRead();return frontmostValue;
}
static NSString *frontMostAppId(){return frontmostRead(TASK_FRONTMOST_APP_ID);}
static NSString *frontMostAppOrientation(){return frontmostRead(TASK_FRONTMOST_APP_ORIENTATION);}
static void frontmostLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=bytes[0]=='3'&&bytes[1]=='4'?TASK_FRONTMOST_APP_ID:TASK_FRONTMOST_APP_ORIENTATION;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse());
    if(!licenseAllowed){
        NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];
        notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;
    }
    if(false){}
#include "fixtures/frontmost-handler-legacy-v1.inc"
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeFrontmostEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedFrontmostCases(TLinkInProcessNativeBridge *bridge){
    mode=@"frontmostRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
        frontmostFault=0;frontmostOnRead={};
    };
    const auto request=[](int task)->TLinkJSNativeRequest *{
        return [[TLinkJSNativeRequest alloc] initWithMethod:task==TASK_FRONTMOST_APP_ID?TLinkJSNativeMethodFrontMostAppId:TLinkJSNativeMethodOrientation arguments:@[@"ignored"]];
    };
    const auto invoke=[bridge,request](int task,TLinkTaskExecutionContext *context)->NSDictionary *{
        NSDictionary *result=[bridge executeRequest:request(task) context:context error:nil].value;
        assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](int task,id value,NSUInteger cap){
        frontmostValue=value==[NSNull null]?nil:value;
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        NSDictionary *expected=[bridge legacyFrontmost:request(task) context:context].value;
        context=parent(1,cap);reset(context);const unsigned reads=frontmostReads;const int gates=licenseCalls,rawCalls=calls;
        NSDictionary *actual=invoke(task,context);assert([actual isEqual:expected]);
        assert(frontmostReads==reads+1&&licenseCalls==gates+1&&lastLicenseTask==task&&frontmostReadTask==task&&calls==rawCalls);
        assert(frontmostBudget&&!frontmostBudget->capturesResponse()&&frontmostBudget->response().capacity()==0);
    };
    for(unsigned n=0;n<160;++n){@autoreleasepool{
        const int task=n%2?TASK_FRONTMOST_APP_ID:TASK_FRONTMOST_APP_ORIENTATION;
        NSString *value=n%2?[NSString stringWithFormat:@"com.example.fixture%u",n]:[NSString stringWithFormat:@"%d",int(n%17)-8];
        parity(task,value,1024*1024);
    }}
    NSString *nul=[NSString stringWithFormat:@"prefix%Ctail;;ignored",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *edges=[@[[NSNull null],@"",@"com.apple.springboard",@"测试.ứng.dụng",@"1",@"-0",@"+2",@"  -3x",@"2.9",@"2147483648",@"-2147483649",@"nan",@";;",@"a;;b;;c",@"a\r\n",@"a\u2028",@"a\u0085",@"a\v",@"\nleading",nul] mutableCopy];
    if(invalid)[edges addObject:invalid];
    for(int task:{TASK_FRONTMOST_APP_ID,TASK_FRONTMOST_APP_ORIENTATION}){
        for(id value in edges){@autoreleasepool{
            parity(task,value,1024*1024);
            frontmostValue=value==[NSNull null]?nil:value;
            TLinkTaskExecutionContext *context=parent();reset(context);
            NSDictionary *expected=[bridge legacyFrontmost:request(task) context:context].value;
            const NSUInteger bytes=[expected[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            assert(bytes>1);parity(task,value,bytes);parity(task,value,bytes-1);
        }}
        TLinkTaskExecutionContext *context=parent();reset(context);frontmostValue=@"2";
        unsigned reads=frontmostReads;int gates=licenseCalls,rawCalls=calls;
        licenseAllowed=false;
        NSDictionary *denied=invoke(task,context);
        context=parent();reset(context);licenseAllowed=false;
        NSDictionary *legacyDenied=[bridge legacyFrontmost:request(task) context:context].value;
        assert([denied isEqual:legacyDenied]&&frontmostReads==reads&&licenseCalls==gates+2&&calls==rawCalls+1);
        context=parent();reset(context);licenseAllowed=false;
        context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(task,context),[NSString stringWithFormat:@"license_required task=%d",task]);
        assert(frontmostReads==reads);
        context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
        failure(invoke(task,context),@"AbortError");assert(frontmostReads==reads&&licenseCalls==gates);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
        failure(invoke(task,context),@"TimeoutError");assert(frontmostReads==reads&&licenseCalls==gates);
        context=parent();reset(context);stopInLicense=true;
        failure(invoke(task,context),@"AbortError");assert(frontmostReads==reads);
        context=parent(0.01);reset(context);licenseDelayMs=30;
        failure(invoke(task,context),@"TimeoutError");assert(frontmostReads==reads);
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
        frontmostOnRead=[token]{[token cancel];};failure(invoke(task,context),@"AbortError");assert(frontmostReads==++reads);
        context=parent(0.01);reset(context);frontmostOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
        failure(invoke(task,context),@"TimeoutError");assert(frontmostReads==++reads);
        for(unsigned fault:{1U,2U}){
            context=parent();reset(context);frontmostFault=fault;
            failure(invoke(task,context),@"native_exception");assert(frontmostReads==++reads);
        }
        context=parent();reset(context);frontmostValue=[NSMutableString stringWithString:@"123"];
        NSDictionary *snapshot=invoke(task,context);[(NSMutableString *)frontmostValue appendString:@"45"];
        if(task==TASK_FRONTMOST_APP_ID)assert([snapshot[@"bundleId"] isEqual:@"123"]);
        else assert([snapshot[@"value"] intValue]==123);
        assert([snapshot[@"parts"][1] isEqual:@"123"]);
        NSDictionary *held=nil;
        @autoreleasepool{
            context=parent();reset(context);frontmostValue=[NSString stringWithFormat:@"%u",123U];
            held=invoke(task,context);frontmostValue=nil;context=nil;
        }
        assert([held[@"parts"][1] isEqual:@"123"]);
    }
    const int gates=licenseCalls,rawCalls=calls;const unsigned reads=frontmostReads;
    failure(TLinkExecuteNativeFrontmost(36,parent()),@"invalid_payload");
    assert(licenseCalls==gates&&frontmostReads==reads&&calls==rawCalls&&!TLinkCurrentNativeBudget());
    frontmostValue=nil;frontmostOnRead={};frontmostBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed frontmost actual bridge/entry passed: 160 ordinary and frozen nil/Unicode/NUL/delimiter/newline/numeric/encoding/output-edge comparisons, task-34/35 authority, caller/gate/read cancellation/deadline, NS/C++ faults, immutable snapshots and no typed RAW dispatch/response vector.");
}
