// Actual bridge/entry/context/sink; controlled RuntimeUtils and license boundaries.
static NSString *pathValue=nil;
static unsigned pathReads=0,pathFault=0;
static int pathReadTask=0;
static TLinkNativeBudgetPtr pathBudget;
static std::function<void()> pathOnRead;
static NSString *pathRead(int task){
    ++pathReads;pathReadTask=task;pathBudget=TLinkCurrentNativeBudget();
    assert(pathBudget&&!pathBudget->cleanup());
    if(!pathBudget->capturesResponse())assert(pathBudget->response().capacity()==0);
    if(pathFault==1)[NSException raise:@"PathFixture" format:@"read throws"];
    if(pathFault==2)throw std::runtime_error("path fixture");
    if(pathOnRead)pathOnRead();return pathValue;
}
static NSString *rootDirValue(){return pathRead(TASK_ROOT_DIR);}
static NSString *currentDirValue(){return pathRead(TASK_CURRENT_DIR);}
static NSString *botPathValue(){return pathRead(TASK_BOT_PATH);}
static void pathLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef){
    const int taskType=(bytes[0]-'0')*10+bytes[1]-'0';
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();
    assert(licenseBudget&&licenseBudget->capturesResponse());
    if(!licenseAllowed){
        NSString *denial=[NSString stringWithFormat:@"-1;;license_required task=%d\r\n",taskType];
        notifyClient((UInt8 *)denial.UTF8String,writeStreamRef);return;
    }
    if(false){}
#include "fixtures/path-handler-legacy-v1.inc"
}
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativePathEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void typedPathCases(TLinkInProcessNativeBridge *bridge){
    mode=@"pathRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context){
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
        pathFault=0;pathOnRead={};
    };
    const auto request=[](int task)->TLinkJSNativeRequest *{
        NSString *method=task==TASK_ROOT_DIR?TLinkJSNativeMethodRootDir:(task==TASK_CURRENT_DIR?TLinkJSNativeMethodCurrentDir:TLinkJSNativeMethodBotPath);
        return [[TLinkJSNativeRequest alloc] initWithMethod:method arguments:@[@"ignored"]];
    };
    const auto invoke=[bridge,request](int task,TLinkTaskExecutionContext *context)->NSDictionary *{
        NSDictionary *result=[bridge executeRequest:request(task) context:context error:nil].value;
        assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto parity=[bridge,request,invoke,reset](int task,id value,NSUInteger cap){
        pathValue=value==[NSNull null]?nil:value;
        TLinkTaskExecutionContext *context=parent(1,cap);reset(context);
        NSDictionary *expected=[bridge legacyPath:request(task) context:context].value;
        context=parent(1,cap);reset(context);const unsigned reads=pathReads;const int gates=licenseCalls,rawCalls=calls;
        NSDictionary *actual=invoke(task,context);assert([actual isEqual:expected]);
        assert(pathReads==reads+1&&pathReadTask==task&&licenseCalls==gates+1&&lastLicenseTask==task&&calls==rawCalls);
        assert(pathBudget&&!pathBudget->capturesResponse()&&pathBudget->response().capacity()==0);
    };
    for(unsigned n=0;n<120;++n){@autoreleasepool{
        const int task=TASK_ROOT_DIR+int(n%3);
        parity(task,[NSString stringWithFormat:@"/var/mobile/Library/fixture-%d/%u/",task,n],1024*1024);
    }}
    NSString *nul=[NSString stringWithFormat:@"/visible%C/ignored;;suffix",(unichar)0];
    const unichar invalidUTF16=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&invalidUTF16 length:1];
    NSMutableArray *edges=[@[[NSNull null],@"",@"/",@"/var/mobile/Library/TLinkauto/",@"/var/mobile/Library/TLinkauto//scripts/",@"./../folder with spaces/",@"/ứng/dụng/测试/",@";;",@"/a;;/b",@"/a\r\n",@"/a\u2029",@"/a\f",nul] mutableCopy];
    if(invalid)[edges addObject:invalid];
    for(int task:{TASK_ROOT_DIR,TASK_CURRENT_DIR,TASK_BOT_PATH}){
        for(id value in edges){@autoreleasepool{
            parity(task,value,1024*1024);pathValue=value==[NSNull null]?nil:value;
            TLinkTaskExecutionContext *context=parent();reset(context);
            NSDictionary *expected=[bridge legacyPath:request(task) context:context].value;
            const NSUInteger bytes=[expected[@"raw"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            assert(bytes>1);parity(task,value,bytes);parity(task,value,bytes-1);
        }}
        pathValue=@"/fixture/";TLinkTaskExecutionContext *context=parent();reset(context);
        unsigned reads=pathReads;int gates=licenseCalls;
        licenseAllowed=false;NSDictionary *denied=invoke(task,context);
        context=parent();reset(context);licenseAllowed=false;
        assert([denied isEqual:[bridge legacyPath:request(task) context:context].value]);
        assert(pathReads==reads&&licenseCalls==gates+2);
        context=parent();reset(context);licenseAllowed=false;
        context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};
        failure(invoke(task,context),[NSString stringWithFormat:@"license_required task=%d",task]);
        context=parent();reset(context);[context.cancellationToken cancel];gates=licenseCalls;
        failure(invoke(task,context),@"AbortError");assert(pathReads==reads&&licenseCalls==gates);
        context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,1024)];
        failure(invoke(task,context),@"TimeoutError");assert(pathReads==reads&&licenseCalls==gates);
        context=parent();reset(context);stopInLicense=true;failure(invoke(task,context),@"AbortError");assert(pathReads==reads);
        context=parent(0.01);reset(context);licenseDelayMs=30;failure(invoke(task,context),@"TimeoutError");assert(pathReads==reads);
        context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;
        pathOnRead=[token]{[token cancel];};failure(invoke(task,context),@"AbortError");assert(pathReads==++reads);
        context=parent(0.01);reset(context);pathOnRead=[]{std::this_thread::sleep_for(std::chrono::milliseconds(30));};
        failure(invoke(task,context),@"TimeoutError");assert(pathReads==++reads);
        for(unsigned fault:{1U,2U}){
            context=parent();reset(context);pathFault=fault;failure(invoke(task,context),@"native_exception");assert(pathReads==++reads);
        }
        context=parent();reset(context);pathValue=[NSMutableString stringWithString:@"/original/"];
        NSDictionary *snapshot=invoke(task,context);[(NSMutableString *)pathValue appendString:@"changed/"];
        NSString *key=task==TASK_ROOT_DIR?@"rootDir":(task==TASK_CURRENT_DIR?@"currentDir":@"botPath");
        assert([snapshot[@"path"] isEqual:@"/original/"]&&[snapshot[key] isEqual:snapshot[@"path"]]);
        NSDictionary *held=nil;
        @autoreleasepool{
            context=parent();reset(context);pathValue=[NSString stringWithFormat:@"/fixture-%d/",task];
            held=invoke(task,context);pathValue=nil;context=nil;
        }
        assert([held[@"parts"][1] isEqual:held[@"path"]]&&[held[key] isEqual:held[@"path"]]);
    }
    const int gates=licenseCalls,rawCalls=calls;const unsigned reads=pathReads;
    for(int task:{0,34,43,47,INT_MAX})failure(TLinkExecuteNativePath(task,parent()),@"invalid_payload");
    assert(licenseCalls==gates&&pathReads==reads&&calls==rawCalls&&!TLinkCurrentNativeBudget());
    pathValue=nil;pathOnRead={};pathBudget.reset();licenseBudget.reset();touchToken=nil;mode=@"echo";
    puts("Typed path actual bridge/entry passed: 120 ordinary and frozen path/alias/Unicode/NUL/delimiter/newline/encoding/output-edge comparisons, task-44/45/46 authority, caller/gate/read cancellation/deadline, faults, immutable/pool lifetime and no typed RAW dispatch/response vector.");
}
