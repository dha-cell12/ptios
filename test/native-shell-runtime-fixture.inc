// Actual legacy normalization/result model/entry/JS. Runner is controlled; no commands execute.
#include <cfloat>
#include "NativeShellConstants.h"
#include "NativeShellResult.inc"
#include "NativeShellHelpers.inc"
static TLinkShellResult *shellReply=nil;
static NSString *shellSeenCommand=nil,*shellFaultStage=nil;
static TLinkTaskExecutionContext *shellSeenContext=nil;
static double shellSeenTimeout=0;
static NSUInteger shellSeenLimit=0;
static unsigned shellEffects=0,shellFault=0;
static std::vector<std::string> shellOrder;
static TLinkNativeBudgetPtr shellBudget;
static std::function<void(NSString *)> shellOnStage;
static void shellObserve(NSString *stage){
    shellOrder.push_back(stage.UTF8String);shellBudget=TLinkCurrentNativeBudget();assert(shellBudget&&!shellBudget->cleanup());
    if(shellOnStage)shellOnStage(stage);
    if([stage isEqual:shellFaultStage]&&shellFault==1)[NSException raise:@"ShellFixture" format:@"runner boundary throws"];
    if([stage isEqual:shellFaultStage]&&shellFault==2)throw std::runtime_error("shell runner boundary throws");
}
static TLinkShellResult *nativeShellRun(NSString *command,TLinkTaskExecutionContext *context,double timeout,NSUInteger limit){
    shellSeenCommand=[command copy];shellSeenContext=context;shellSeenTimeout=timeout;shellSeenLimit=limit;
    assert([context nativeBudget]==TLinkCurrentNativeBudget());shellObserve(@"start");++shellEffects;shellObserve(@"committed");
    if(!shellReply)return nil;
    TLinkShellResult *result=[TLinkShellResult new];result.exitCode=shellReply.exitCode;result.terminationSignal=shellReply.terminationSignal;
    result.timedOut=shellReply.timedOut;result.cancelled=shellReply.cancelled;result.drainForcedClosed=shellReply.drainForcedClosed;
    result.stdoutStr=shellReply.stdoutStr;result.stderrStr=shellReply.stderrStr;result.stdoutTruncated=shellReply.stdoutTruncated;result.stderrTruncated=shellReply.stderrTruncated;
    return result;
}
#define RunShellCore nativeShellRun
#pragma push_macro("YES")
#pragma push_macro("NO")
#undef YES
#undef NO
#include "NativeShellEntry.inc"
#pragma pop_macro("NO")
#pragma pop_macro("YES")
static void shellLegacyTask(UInt8 *bytes,CFWriteStreamRef writeStreamRef,TLinkTaskExecutionContext *context){
    const int taskType=TASK_RUN_SHELL;UInt8 *eventData=bytes+2;
    ++licenseCalls;lastLicenseTask=taskType;licenseBudget=TLinkCurrentNativeBudget();assert(licenseBudget&&licenseBudget->capturesResponse()&&!licenseBudget->cleanup());
    if(licenseDelayMs)std::this_thread::sleep_for(std::chrono::milliseconds(licenseDelayMs));if(stopInLicense)[touchToken cancel];
    if(!licenseAllowed){notifyClient((UInt8 *)"-1;;license_required task=13\r\n",writeStreamRef);return;}
    if(TLinkNativeStopped()){notifyClient((UInt8 *)"1;;native_cancelled_or_timed_out\r\n",writeStreamRef);return;}
    if(false){}
#include "fixtures/shell-handler-legacy-v1.inc"
}
#undef RunShellCore
static void typedShellCases(TLinkInProcessNativeBridge *bridge){
    @try {try{
    mode=@"shellRuntime";puts("Shell Foundation: actual scanner/formatter/model/entry and frozen JS/task parity; runner controlled");fflush(stdout);
    const auto reset=[](TLinkTaskExecutionContext *context,unsigned scenario=0,NSString *out=@"ordinary output",NSString *err=@""){
        shellReply=[TLinkShellResult new];shellReply.exitCode=0;shellReply.stdoutStr=out;shellReply.stderrStr=err;
        if(scenario==1)shellReply.timedOut=true;if(scenario==2)shellReply.cancelled=true;
        if(scenario==3)shellReply.exitCode=17;if(scenario==4){shellReply.timedOut=true;shellReply.cancelled=true;shellReply.exitCode=-1;}
        if(scenario==5)shellReply.stdoutTruncated=true;if(scenario==6)shellReply.stderrTruncated=true;if(scenario==7)shellReply=nil;
        shellSeenCommand=shellFaultStage=nil;shellSeenContext=nil;shellSeenTimeout=0;shellSeenLimit=0;shellEffects=shellFault=0;shellOrder.clear();shellBudget.reset();shellOnStage={};
        touchToken=context.cancellationToken;licenseAllowed=true;stopInLicense=false;licenseDelayMs=0;
    };
    const auto request=[](NSArray *args)->TLinkJSNativeRequest *{return [[TLinkJSNativeRequest alloc] initWithMethod:TLinkJSNativeMethodRunShell arguments:args];};
    const auto invoke=[bridge,request](NSArray *args,TLinkTaskExecutionContext *context)->TLinkJSNativeResponse *{
        TLinkJSNativeResponse *result=[bridge executeRequest:request(args) context:context error:nil];assert(!TLinkCurrentNativeBudget());return result;
    };
    const auto inheritedContext=[](NSUInteger cap){
        auto context=parent(30,cap);[context setNativeBudget:[TLinkNativeCallContext(context,false,false) nativeBudget]];return context;
    };
    const auto parity=[bridge,reset,request,invoke,inheritedContext](NSArray *args,NSUInteger cap=4096,unsigned scenario=0,NSString *out=@"ordinary output",NSString *err=@"")->NSUInteger{
        // A fixed inherited budget separates numeric timeout fidelity from
        // sub-millisecond request admission races in the real budget prelude.
        auto context=inheritedContext(cap);reset(context,scenario,out,err);int gates=licenseCalls;
        TLinkJSNativeResponse *expected=[bridge legacyShell:request(args) context:context];const auto order=shellOrder;
        NSString *command=shellSeenCommand;const double timeout=shellSeenTimeout;const NSUInteger limit=shellSeenLimit;const unsigned effects=shellEffects;const int gateDelta=licenseCalls-gates;
        NSString *owner=shellSeenContext.ownerSessionId,*run=shellSeenContext.ownerRunId,*runtime=shellSeenContext.ownerRuntime;
        const double defaultTimeout=shellSeenContext.defaultTimeoutSeconds;const NSUInteger defaultOutput=shellSeenContext.defaultMaxOutputBytes;
        context=inheritedContext(cap);reset(context,scenario,out,err);gates=licenseCalls;const int rawCalls=calls;
        TLinkJSNativeResponse *actual=invoke(args,context);const bool same=actual.ok==expected.ok&&((actual.value==expected.value)||[actual.value isEqual:expected.value]);
        if(!same){fprintf(stdout,"Shell parity failure: %s\n",[NSString stringWithFormat:@"args=%@ cap=%lu scenario=%u expected=%@ actual=%@",args,(unsigned long)cap,scenario,expected.value,actual.value].UTF8String);fflush(stdout);}assert(same);
        if(!actual.ok)assert([actual.errorCode isEqual:expected.errorCode]&&[actual.errorMessage isEqual:expected.errorMessage]);
        assert(shellOrder==order&&shellEffects==effects&&((command==shellSeenCommand)||[command isEqual:shellSeenCommand])&&shellSeenTimeout==timeout&&shellSeenLimit==limit);
        assert(((owner==shellSeenContext.ownerSessionId)||[owner isEqual:shellSeenContext.ownerSessionId])&&((run==shellSeenContext.ownerRunId)||[run isEqual:shellSeenContext.ownerRunId])&&((runtime==shellSeenContext.ownerRuntime)||[runtime isEqual:shellSeenContext.ownerRuntime]));
        assert(shellSeenContext.defaultTimeoutSeconds==defaultTimeout&&shellSeenContext.defaultMaxOutputBytes==defaultOutput&&calls==rawCalls&&licenseCalls==gates+gateDelta);
        if(gateDelta)assert(lastLicenseTask==13);if(shellBudget)assert(!shellBudget->capturesResponse()&&shellBudget->response().capacity()==0&&shellSeenLimit==SIZE_MAX);
        id raw=actual.value[@"raw"];return [raw isKindOfClass:[NSString class]]?[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]:0;
    };
    for(unsigned n=0;n<160;++n)parity(@[[NSString stringWithFormat:@"fixture command %u; 测试",n],@(1.12345+(n%8)*0.25)]);
    for(unsigned scenario=0;scenario<=7;++scenario){const NSUInteger size=parity(@[@"fixture",@1.5],4096,scenario);assert(size);parity(@[@"fixture",@1.5],size,scenario);if(size>1)parity(@[@"fixture",@1.5],size-1,scenario);}
    for(NSNumber *timeout in @[@(-0.0),@(-1),@0,@0.0001,@0.00049,@0.0005,@0.00051,@0.9995,@1.2345,@299.9995,@301,@(DBL_MAX),@(NAN),@(INFINITY),@(-INFINITY)])parity(@[@"fixture",timeout]);
    for(NSString *command in @[@"", @"12;;fixture", @"0;;fixture", @"-1;;fixture", @" 2 ;;fixture", @"2tail;;fixture", @";;fixture", @"1;;", @"fixture;;more;;text", @"line one\nline two\r", @"emoji 😀/ảnh/测试"])parity(@[command]);
    parity(@[]);parity(@[@"fixture",@"1.2345",@"ignored"]);
    for(bool prefixed:{false,true})for(NSString *unit in @[@"x",@"界"]){
        const NSUInteger limit=prefixed?8183:8190; // task 13; optional 1.000;;
        NSString *exact=[@"" stringByPaddingToLength:limit withString:unit startingAtIndex:0];parity(prefixed?@[exact,@1]:@[exact],65536);parity(prefixed?@[[exact stringByAppendingString:@"x"],@1]:@[[exact stringByAppendingString:@"x"]],65536);
    }
    NSString *nul=[NSString stringWithFormat:@"before%Cafter",(unichar)0];const unichar lone=0xd800;NSString *invalid=[[NSString alloc] initWithCharacters:&lone length:1];
    parity(@[nul]);if(invalid)parity(@[invalid]);
    for(NSString *out in @[@"", @"plain", @"0;;aGk=", @"42;;aGk=", @"0;;not base64", @"测试\r\nline;;YWJj",nul,invalid?:@"fallback"]){
        for(unsigned scenario:{0U,1U,2U,3U,5U,6U})parity(@[@"fixture"],65536,scenario,out,@" stderr\r\n");
    }
    // Real task 13's ordinary reply is plain escaped text, while the unchanged
    // JS decoder reads exitCode/base64 metadata only when extra ;; fields exist.
    auto context=inheritedContext(4096);reset(context,0,@"plain");NSDictionary *plain=invoke(@[@"fixture"],context).value;assert([plain[@"ok"] boolValue]&&!plain[@"exitCode"]&&!plain[@"output"]);
    context=inheritedContext(4096);reset(context,0,@"42;;aGk=");NSDictionary *columns=invoke(@[@"fixture"],context).value;assert([columns[@"exitCode"] intValue]==42&&[columns[@"output"] isEqual:@"hi"]);
    NSString *large=[@"" stringByPaddingToLength:768*1024 withString:@"x\n" startingAtIndex:0];parity(@[@"fixture"],1024*1024,5,large);parity(@[@"fixture"],1024*1024,0,large);
    puts("Shell Foundation: task-13 authority, caller budgets, accepted effects and fault/pool lifetime");fflush(stdout);
    context=parent();reset(context);licenseAllowed=false;context.allowsAutomationForOwner=^BOOL(NSString *owner){(void)owner;return true;};failure(invoke(@[@"fixture"],context).value,@"license_required task=13");assert(shellOrder.empty());
    context=parent();reset(context);int gates=licenseCalls;[context.cancellationToken cancel];failure(invoke(@[@"fixture"],context).value,@"AbortError");assert(licenseCalls==gates&&shellOrder.empty());
    context=parent();reset(context);[context setNativeBudget:std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},1,4096)];failure(invoke(@[@"fixture"],context).value,@"TimeoutError");assert(licenseCalls==gates&&shellOrder.empty());
    context=parent();reset(context);stopInLicense=true;failure(invoke(@[@"fixture"],context).value,@"AbortError");assert(shellOrder.empty());
    context=parent(0.1);reset(context);licenseDelayMs=150;failure(invoke(@[@"fixture"],context).value,@"TimeoutError");assert(shellOrder.empty());
    for(NSString *point in @[@"start",@"committed"]){context=parent();reset(context);TLinkCancellationToken *token=context.cancellationToken;shellOnStage=[point,token](NSString *stage){if([stage isEqual:point])[token cancel];};
        failure(invoke(@[@"fixture"],context).value,@"AbortError");assert(shellEffects==1);}
    context=parent(0.1);reset(context);shellOnStage=[](NSString *stage){if([stage isEqual:@"start"])std::this_thread::sleep_for(std::chrono::milliseconds(150));};failure(invoke(@[@"fixture"],context).value,@"TimeoutError");assert(shellEffects==1);
    context=parent(1,2);reset(context);failure(invoke(@[@"fixture"],context).value,@"response_too_large");assert(shellEffects==1);
    for(unsigned fault:{1U,2U})for(NSString *point in @[@"start",@"committed"]){context=parent();reset(context);shellFault=fault;shellFaultStage=point;failure(invoke(@[@"fixture"],context).value,@"native_exception");assert(shellEffects==([point isEqual:@"start"]?0U:1U));}
    context=parent(0.2);reset(context);assert([invoke(@[@"fixture",@10],context).value[@"ok"] boolValue]);assert(shellBudget->deadline()<=TLinkNativeNowNs()+200000000ULL&&shellSeenTimeout==10);
    context=parent();reset(context);NSMutableString *command=[@"fixture snapshot" mutableCopy],*output=[@"immutable output" mutableCopy];shellReply.stdoutStr=output;shellOnStage=[command](NSString *stage){if([stage isEqual:@"start"])[command setString:@"changed"];};NSDictionary *held=nil;
    @autoreleasepool{held=invoke(@[command],context).value;context=nil;}[output setString:@"changed"];assert([shellSeenCommand isEqual:@"fixture snapshot"]&&[held[@"raw"] isEqual:@"0;;immutable output\r\n"]);
    for(unsigned n=0;n<128;++n){context=inheritedContext(4096);reset(context);assert([invoke(@[@"fixture"],context).value[@"ok"] boolValue]&&shellEffects==1);}
    shellReply=nil;shellSeenCommand=shellFaultStage=nil;shellSeenContext=nil;shellOrder.clear();shellBudget.reset();shellOnStage={};licenseBudget.reset();touchToken=nil;mode=@"echo";
    assert(!TLinkCurrentNativeBudget());puts("Typed shell passed: actual legacy scanner/reply/model and frozen JS/task parity, %.3f and numeric command prefixes, UTF-8/ingress/output/status/metadata, task-13 authority, caller stop/accepted effects, NS/C++ faults and lifetime. Runner controlled; no commands executed. Real spawn/drain/process qualification remains pending.");
    }catch(const std::exception &exception){fprintf(stdout,"Shell fixture: uncaught C++ exception: %s\n",exception.what());fflush(stdout);throw;}catch(...){puts("Shell fixture: uncaught non-standard C++ exception");fflush(stdout);throw;}}
    @catch(NSException *exception){fprintf(stdout,"Shell fixture: uncaught Objective-C exception: %s\n",exception.description.UTF8String?:"(no description)");fflush(stdout);@throw;}
}
