static NSData *beforeWireBudgetCall(bool root,bool capability,NSDictionary *value){
    if(root){
        if(capability)BeforeWireBudgetRootCapability(NULL);else BeforeWireBudgetRootResponse(value,NULL);
        return captured;
    }
    return capability?BeforeWireBudgetTrollCapability():BeforeWireBudgetTrollResponse(value);
}
static void wireLateEffectCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(unsigned stage:{1U,2U}){
        for(unsigned kind=0;kind<8;++kind)for(bool current:{false,true}){
            std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();wireEffectStage=stage;wireEffectKind=kind;
                wireEffectCancellation=std::make_shared<TLinkNativeCancellation>();
                auto parent=std::make_shared<TLinkNativeBudget>(wireEffectCancellation,kind==1?TLinkNativeDeadline(.025):0,1024*1024,false,true);
                auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;wireEffectBudget=budget;
                TLinkNativeBudgetScope scope(budget);NSData *reply=nil;bool caught=false;
                NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀",@"nested":@[@1,@{},[NSNull null]]};fixtureCapability=graph;
                @try{try{reply=current?call(root,capability,true,graph):beforeWireBudgetCall(root,capability,graph);}
                    catch(const std::runtime_error &){caught=kind==7;}}
                @catch(NSException *exception){caught=kind==6&&[exception.name isEqualToString:@"WireEffectFixture"];}
                wireLateScope.reset();
                if(kind==1&&wireEffectCalls==0){
                    // A loaded CI host may consume the deadline before encoding.
                    errorReply(reply,@"ui_cancelled_or_timed_out");assert(!caught&&base64Calls<=1&&wireFinalCalls==0);
                }else{
                    assert(wireEffectCalls==1&&base64Calls==1&&caught==(kind==6||kind==7));
                    const bool refuses=current&&kind<6&&kind!=5;
                    assert(wireFinalCalls==((stage==1&&(refuses||caught))?0U:1U));
                    if(caught)assert(!reply);
                    else if(refuses)errorReply(reply,kind==2||kind==3?@"ui_response_too_large":@"ui_cancelled_or_timed_out");
                    else decoded(reply);
                    if(kind==0||kind==4)assert(budget->reason()==TLinkNativeStop::Cancelled);
                    if(kind==1)assert(budget->reason()==TLinkNativeStop::Deadline);
                    if(kind==2)assert(budget->reason()==(current?TLinkNativeStop::OutputLimit:TLinkNativeStop::None));
                    if(kind==3)assert(budget->reason()==TLinkNativeStop::OutputLimit);
                    if(kind==5)assert(budget->reason()==TLinkNativeStop::None);
                }
                assert(parent->response().empty()||(kind==2||kind==3));
                wireEffectCancellation.reset();
            }
            assert(weak.expired()&&!TLinkCurrentNativeBudget()&&!wireLateScope);
        }
    }
    wireEffectBudget.reset();reset();
}
static void wireLateRecoveryCases(){
    for(bool root:{false,true})for(bool capability:{false,true}){
        for(unsigned n=0;n<32;++n){
            @autoreleasepool{
                reset();wireEffectStage=n%2+1;wireEffectKind=0;wireEffectCancellation=std::make_shared<TLinkNativeCancellation>();
                auto budget=std::make_shared<TLinkNativeBudget>(wireEffectCancellation,0,1024*1024);wireEffectBudget=budget;
                TLinkNativeBudgetScope scope(budget);errorReply(call(root,capability,true,@{@"ok":@YES}),@"ui_cancelled_or_timed_out");
            }
            @autoreleasepool{reset();decoded(call(root,capability,true,@{@"ok":@YES}));}
        }
    }
    reset();
}
static void wireLateAdmissionCases(){
    std::puts("AX late wire admission: actual four codecs/C05w, real JSON/base64/formatting/native budgets with effects at encoder and final-byte boundaries");
    wireLateEffectCases();wireLateRecoveryCases();
    std::puts("AX late wire admission passed: cancellation/deadline/parent output consumption after base64/final construction, captured caller across nested scopes, sticky overflow priority, NS/C++ unwind, 128 recovery cycles and no late success publication. Notify/socket/device qualification pending.");
}
