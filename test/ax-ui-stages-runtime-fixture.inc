enum {TASK_UI_TREE_SNAPSHOT=78,TASK_UI_TREE_FIND=79,TASK_UI_TREE_AT=80,TASK_UI_TREE_TAP=81};
static unsigned uiDecodeCalls=0,uiForeCalls=0,uiQueryCalls=0,uiInvalidateCalls=0,uiScaleCalls=0,uiTapCalls=0;
static unsigned uiEffectStage=0,uiEffectKind=0,uiFaultKind=0;
static bool uiEffectFired=false,uiRetryFirst=false,uiChanged=false,uiTapFailure=false;
static NSString *uiFailure=@"",*uiLastTap=nil;
static std::shared_ptr<TLinkNativeCancellation> uiCancellation;
static std::weak_ptr<TLinkNativeBudget> uiCaller;
static void uiEffect(unsigned stage){
    if(uiEffectFired||stage!=uiEffectStage)return;
    uiEffectFired=true;auto caller=uiCaller.lock();assert(caller&&uiCancellation);
    if(uiEffectKind==1){
        assert(caller->deadline());std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(caller->deadline())));
    }else if(uiEffectKind==2)assert(!caller->outputAllowed(caller->outputLimit()+1));
    else uiCancellation->cancel();
    if(uiEffectKind==3){auto alternate=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024*1024);wireLateScope.reset(new TLinkNativeBudgetScope(alternate));}
    if(uiFaultKind==1)[NSException raise:@"UIStagesFixture" format:@"provider"];
    if(uiFaultKind==2)throw std::runtime_error("UI stage");
}
static NSDictionary *uiHandlerForeground(){
    ++uiForeCalls;const unsigned stage=uiQueryCalls==0?2:(uiRetryFirst&&uiQueryCalls==1?5:6);uiEffect(stage);
    if([uiFailure isEqualToString:@"foreground"])return @{@"ok":@NO,@"error":@"ui_fixture_context_error"};
    return @{@"ok":@YES,@"pid":@123,@"bundle_id":stage==6&&uiChanged?@"changed.bundle":@"fixture.bundle"};
}
static NSDictionary *TLinkAXCopyFrontmostContext(){return uiHandlerForeground();}
static NSDictionary *TLinkUITreeAXSpringBoardContext(){return @{@"ok":@NO};}
static NSDictionary *uiDecode(NSString **error){
    ++uiDecodeCalls;uiEffect(1);
    if([uiFailure isEqualToString:@"decode"]){if(error)*error=@"ui_fixture_request_invalid";return nil;}
    return @{@"text":@"target",@"x":[uiFailure isEqualToString:@"coordinates"]?(id)[NSNull null]:(id)@1.25,@"y":@2.5};
}
static NSDictionary *zx_uiTreeRequest(UInt8 *bytes,BOOL optional,NSString **error){(void)bytes;(void)optional;return uiDecode(error);}
static NSDictionary *TLinkUITreeDecodeBody(NSString *body,BOOL optional,NSString **error){(void)body;(void)optional;return uiDecode(error);}
static NSDictionary *uiQuery(pid_t pid,NSString *bundle,NSDictionary *request){
    (void)request;assert(pid==123&&[bundle isEqualToString:@"fixture.bundle"]);++uiQueryCalls;uiEffect(3);
    if(uiRetryFirst&&uiQueryCalls==1)return @{@"ok":@NO,@"error":@"ui_element_query_failed"};
    if([uiFailure isEqualToString:@"query"])return @{@"ok":@NO,@"error":@"ui_fixture_query_error"};
    NSDictionary *element=@{@"enabled":@(![uiFailure isEqualToString:@"disabled"]),@"clickable":@YES,
        @"activation_point_valid":@(![uiFailure isEqualToString:@"point"]),@"activation_point":@{@"x":@1.25,@"y":@2.5}};
    return @{@"ok":@YES,@"schema":@"fixture",@"found":@(![uiFailure isEqualToString:@"missing"]),@"element":element,
        @"partial":@([uiFailure isEqualToString:@"partial"]),@"truncated":@NO,@"count":@1};
}
static NSDictionary *TLinkAXCopySnapshot(pid_t pid,NSString *bundle,NSDictionary *request){return uiQuery(pid,bundle,request);}
static NSDictionary *TLinkAXFindElement(pid_t pid,NSString *bundle,NSDictionary *request){return uiQuery(pid,bundle,request);}
static NSDictionary *TLinkAXElementAtPoint(pid_t pid,NSString *bundle,CGPoint point){assert(point.x==1.25&&point.y==2.5);return uiQuery(pid,bundle,@{});}
#include "AXCompletenessUnderTest.inc"
static void TLinkUITreeInvalidateCachedContext(){++uiInvalidateCalls;uiEffect(4);}
@interface WireUIFixtureScreen:NSObject
+(instancetype)mainScreen;
-(CGFloat)scale;
@end
@implementation WireUIFixtureScreen
+(instancetype)mainScreen{static WireUIFixtureScreen *screen;static dispatch_once_t once;dispatch_once(&once,^{screen=[WireUIFixtureScreen new];});return screen;}
-(CGFloat)scale{++uiScaleCalls;uiEffect(7);return 2;}
@end
static BOOL zx_handleNativeTap(UInt8 *body,NSError **error){
    (void)error;++uiTapCalls;uiLastTap=[NSString stringWithUTF8String:(const char *)body];uiEffect(8);return !uiTapFailure;
}
static BOOL TLinkHandleNativeTap(NSString *body,NSString **error){
    ++uiTapCalls;uiLastTap=[body copy];uiEffect(8);if(uiTapFailure&&error)*error=@"ui_tap_dispatch_failed";return !uiTapFailure;
}
#include "UIRootContext.inc"
#include "UITrollContext.inc"
#include "CurrentUIStagesRoot.inc"
#include "BeforeUIStagesRoot.inc"
#include "CurrentUIStagesTroll.inc"
#include "BeforeUIStagesTroll.inc"
static void uiReset(){
    reset();uiHandlerActive=true;uiDecodeCalls=uiForeCalls=uiQueryCalls=uiInvalidateCalls=uiScaleCalls=uiTapCalls=0;
    uiEffectStage=uiEffectKind=uiFaultKind=0;uiEffectFired=uiRetryFirst=uiChanged=uiTapFailure=false;
    uiFailure=@"";uiLastTap=nil;uiCancellation.reset();uiCaller.reset();
}
static NSData *uiCall(bool root,bool current,int task){
    UInt8 empty=0;
    if(root){if(current)CurrentUIStagesRoot(task,&empty,NULL);else BeforeUIStagesRoot(task,&empty,NULL);return captured;}
    return current?CurrentUIStagesTroll(task,@""):BeforeUIStagesTroll(task,@"");
}
static void uiGoldenCases(){
    for(bool root:{false,true})for(int task:{78,79,80,81})for(unsigned n=0;n<32;++n){
        NSDictionary *before=nil;unsigned oldFore=0,oldQueries=0;
        for(bool current:{false,true}){@autoreleasepool{
            uiReset();uiRetryFirst=!root&&n%3==0;
            NSDictionary *value=decoded(uiCall(root,current,task));
            if(current)assert([value isEqual:before]&&uiForeCalls==oldFore&&uiQueryCalls==oldQueries);
            else{before=value;oldFore=uiForeCalls;oldQueries=uiQueryCalls;}
            assert(uiTapCalls==(task==81?1U:0U));
            if(task==81)assert([uiLastTap isEqualToString:@"2.500;;5.000;;50;;0"]);
            assert(uiInvalidateCalls==(uiRetryFirst?1U:0U));
        }}
    }
    for(bool root:{false,true})for(NSString *failure in @[@"decode",@"foreground",@"query",@"partial",@"missing",@"disabled",@"point",@"context"]){
        NSData *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            uiReset();uiFailure=failure;uiChanged=[failure isEqualToString:@"context"];
            NSData *reply=uiCall(root,current,81);if(current)assert([reply isEqualToData:before]);else before=reply;
            assert(uiTapCalls==0);
        }}
    }
    for(bool root:{false,true})for(bool current:{false,true}){@autoreleasepool{
        uiReset();uiFailure=@"coordinates";errorReply(uiCall(root,current,80),@"ui_hit_test_coordinates_required");assert(uiQueryCalls==0&&uiTapCalls==0);
    }}
}
static void uiStopCases(){
    for(bool root:{false,true})for(int task:{78,79,80,81})for(unsigned stage:{0U,1U,2U,3U,6U,7U}){
        if(stage==7&&task!=81)continue;
        for(bool current:{false,true}){@autoreleasepool{
            uiReset();uiEffectStage=stage;uiCancellation=std::make_shared<TLinkNativeCancellation>();
            auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,0,1024*1024);uiCaller=budget;
            if(stage==0)uiCancellation->cancel();
            TLinkNativeBudgetScope scope(budget);
            NSData *reply=uiCall(root,current,task);errorReply(reply,@"ui_cancelled_or_timed_out");
            if(current){
                assert(uiForeCalls==(stage<=1?0U:(stage<=3?1U:2U)));
                assert(uiQueryCalls==(stage<=2?0U:1U)&&uiTapCalls==0);
                assert(uiScaleCalls==(stage==7?2U:0U));
            }else{assert(uiForeCalls==2&&uiQueryCalls==1&&uiTapCalls==(task==81?1U:0U));}
            uiCancellation.reset();
        }}
    }
    for(unsigned stage:{3U,4U,5U})for(bool current:{false,true}){@autoreleasepool{
        uiReset();uiRetryFirst=true;uiEffectStage=stage;uiCancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,0,1024*1024);uiCaller=budget;TLinkNativeBudgetScope scope(budget);
        errorReply(uiCall(false,current,79),@"ui_cancelled_or_timed_out");
        assert(uiQueryCalls==(current?1U:2U));
        assert(uiInvalidateCalls==(current&&stage==3?0U:1U));
        assert(uiForeCalls==(current?(stage==5?2U:1U):3U));uiCancellation.reset();
    }}
}
static void uiAuthorityAndFaultCases(){
    for(bool root:{false,true})for(unsigned stage:{2U,3U,6U,8U})for(bool current:{false,true}){@autoreleasepool{
        uiReset();uiEffectStage=stage;uiCancellation=std::make_shared<TLinkNativeCancellation>();
        uiFailure=stage==2?@"foreground":(stage==3?@"query":@"");uiChanged=stage==6;uiTapFailure=stage==8;
        auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,0,1024*1024);uiCaller=budget;TLinkNativeBudgetScope scope(budget);
        NSString *code=stage==2?@"ui_fixture_context_error":(stage==3?@"ui_fixture_query_error":(stage==6?@"ui_context_changed":@"ui_tap_dispatch_failed"));
        errorReply(uiCall(root,current,81),code);assert(uiTapCalls==(stage==8?1U:0U));uiCancellation.reset();
    }}
    for(bool root:{false,true})for(unsigned kind:{1U,2U,3U}){@autoreleasepool{
        uiReset();uiEffectStage=2;uiEffectKind=kind;uiCancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,kind==1?TLinkNativeDeadline(.025):0,1024*1024);uiCaller=budget;
        TLinkNativeBudgetScope scope(budget);NSData *reply=uiCall(root,true,81);wireLateScope.reset();
        errorReply(reply,kind==2?@"ui_response_too_large":@"ui_cancelled_or_timed_out");assert(uiQueryCalls==0&&uiTapCalls==0);
        uiCancellation.reset();
    }}
    for(bool root:{false,true})for(unsigned stage:{2U,3U,6U,7U,8U})for(unsigned fault:{1U,2U})for(bool current:{false,true}){
        std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            uiReset();uiEffectStage=stage;uiFaultKind=fault;uiCancellation=std::make_shared<TLinkNativeCancellation>();
            auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,0,1024*1024);weak=budget;uiCaller=budget;TLinkNativeBudgetScope scope(budget);bool caught=false;
            @try{try{uiCall(root,current,81);}catch(const std::runtime_error &){caught=fault==2;}}
            @catch(NSException *exception){caught=fault==1&&[exception.name isEqualToString:@"UIStagesFixture"];}
            assert(caught&&uiTapCalls==(stage==8?1U:0U));uiCancellation.reset();
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
    }
    for(bool root:{false,true}){@autoreleasepool{
        uiReset();uiEffectStage=8;uiCancellation=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(uiCancellation,0,1024*1024);uiCaller=budget;TLinkNativeBudgetScope scope(budget);
        errorReply(uiCall(root,true,81),@"ui_cancelled_or_timed_out");assert(uiTapCalls==1);uiCancellation.reset();
    }}
    uiReset();reset();
}
static void uiStagesCases(){
    std::puts("UI stage package: complete actual/C05aa Task78-81 handlers/context guards with real JSON/native budgets; private queries/screen/tap controlled");
    uiGoldenCases();uiStopCases();uiAuthorityAndFaultCases();
    std::puts("UI stage package passed: 256 full-graph live task cases, original context/completeness/action refusals, foreground/query/verification/coordinate cancellation, stopped retry isolation, captured deadline/output/TLS, NS/C++ unwind and committed tap without replay. Real UI/device qualification pending.");
}
