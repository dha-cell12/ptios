static NSData *capabilityPreflightCall(bool root,bool current){
    if(current)return call(root,true,true,nil);
    if(root){BeforeCapabilityPreflightRoot(NULL);return captured;}
    return BeforeCapabilityPreflightTroll();
}
static void capabilityStoppedEntryCases(){
    for(bool root:{false,true})for(unsigned kind=0;kind<4;++kind)for(bool current:{false,true}){
        std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            reset();auto cancel=std::make_shared<TLinkNativeCancellation>();
            auto parent=std::make_shared<TLinkNativeBudget>(cancel,kind==1?TLinkNativeNowNs():0,kind==3?1:1024*1024,false,true);
            auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;
            if(kind==2)assert(!parent->outputAllowed(parent->outputLimit()+1));else if(kind!=1)cancel->cancel();
            TLinkNativeBudgetScope scope(budget);
            errorReply(capabilityPreflightCall(root,current),kind==2?@"ui_response_too_large":@"ui_cancelled_or_timed_out");
            assert(capabilityCalls==(current?0U:1U)&&foregroundCalls==(current||root?0U:1U));
            assert(jsonCalls==(current?0U:1U)&&base64Calls==0&&parent->response().empty());
            assert(budget->reason()==(kind==2?TLinkNativeStop::OutputLimit:(kind==1?TLinkNativeStop::Deadline:TLinkNativeStop::Cancelled)));
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
    }
    reset();
}
static void capabilityProviderStopCases(){
    for(bool root:{false,true})for(unsigned site=1;site<=(root?1U:2U);++site){
        for(unsigned kind=0;kind<4;++kind)for(bool current:{false,true}){
            std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();capabilityEffectSite=site;capabilityEffectKind=kind;
                capabilityCancellation=std::make_shared<TLinkNativeCancellation>();
                auto parent=std::make_shared<TLinkNativeBudget>(capabilityCancellation,kind==1?TLinkNativeDeadline(.025):0,1024*1024,false,true);
                auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;capabilityBudget=budget;
                TLinkNativeBudgetScope scope(budget);NSData *reply=capabilityPreflightCall(root,current);wireLateScope.reset();
                if(kind==1&&capabilityEffectCalls==0){
                    // A loaded host may expire at entry or after the first probe.
                    assert(current&&capabilityCalls<=1&&foregroundCalls==0&&jsonCalls==0);
                    errorReply(reply,@"ui_cancelled_or_timed_out");
                }else{
                    assert(capabilityEffectCalls==1&&capabilityCalls==1);
                    assert(foregroundCalls==(root||(current&&site==1)?0U:1U));
                    assert(jsonCalls==(current?0U:1U));
                    if(!current&&kind==3){decoded(reply);assert(base64Calls==1);}
                    else{errorReply(reply,kind==2?@"ui_response_too_large":@"ui_cancelled_or_timed_out");assert(base64Calls==0);}
                }
                assert(parent->response().empty());
                assert(budget->reason()==(kind==2?TLinkNativeStop::OutputLimit:(kind==1?TLinkNativeStop::Deadline:TLinkNativeStop::Cancelled)));
                capabilityCancellation.reset();
            }
            assert(weak.expired()&&!TLinkCurrentNativeBudget()&&!wireLateScope);
        }
    }
    reset();
}
static void capabilityProviderFaultCases(){
    for(bool root:{false,true})for(unsigned site=1;site<=(root?1U:2U);++site){
        for(unsigned kind:{1U,2U})for(bool current:{false,true}){
            std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();capabilityEffectSite=site;capabilityFaultKind=kind;
                capabilityCancellation=std::make_shared<TLinkNativeCancellation>();
                auto budget=std::make_shared<TLinkNativeBudget>(capabilityCancellation,0,1024*1024);weak=budget;capabilityBudget=budget;
                TLinkNativeBudgetScope scope(budget);bool caught=false;
                @try{try{capabilityPreflightCall(root,current);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"CapabilityPreflightFixture"];}
                assert(caught&&capabilityEffectCalls==1&&capabilityCalls==1);
                assert(foregroundCalls==(site==2?1U:0U)&&jsonCalls==0&&base64Calls==0&&!captured);
                assert(budget->reason()==TLinkNativeStop::Cancelled);capabilityCancellation.reset();
            }
            assert(weak.expired()&&!TLinkCurrentNativeBudget());
        }
    }
    reset();
}
static void capabilityCleanupCases(){
    for(bool root:{false,true})for(bool child:{false,true})for(bool current:{false,true}){@autoreleasepool{
        reset();auto cancel=std::make_shared<TLinkNativeCancellation>();cancel->cancel();
        auto cleanup=std::make_shared<TLinkNativeBudget>(cancel,TLinkNativeNowNs(),1024*1024,true);
        auto budget=child?std::make_shared<TLinkNativeBudget>(0,cleanup):cleanup;
        TLinkNativeBudgetScope scope(budget);NSData *reply=capabilityPreflightCall(root,current);
        if(child)errorReply(reply,@"ui_cancelled_or_timed_out");else decoded(reply);
        const bool skips=current&&child;
        assert(capabilityCalls==(skips?0U:1U)&&foregroundCalls==(skips||root?0U:1U));
        assert(jsonCalls==(skips?0U:1U)&&base64Calls==(child?0U:1U));
        assert(budget->reason()==(child?TLinkNativeStop::Deadline:TLinkNativeStop::None));
    }}
    reset();
}
static void capabilityRecoveryCases(){
    for(bool root:{false,true})for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();auto cancel=std::make_shared<TLinkNativeCancellation>();cancel->cancel();
            auto budget=std::make_shared<TLinkNativeBudget>(cancel,0,1024*1024);TLinkNativeBudgetScope scope(budget);
            errorReply(capabilityPreflightCall(root,true),@"ui_cancelled_or_timed_out");
            assert(capabilityCalls==0&&foregroundCalls==0&&jsonCalls==0&&base64Calls==0);
        }
        NSDictionary *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            reset();fixtureCapability=@{@"ok":@YES,@"n":@(n),@"text":@"Ứng dụng 测试😀\n\"\\",@"nested":@[@1,@{},[NSNull null]]};
            NSDictionary *value=decoded(capabilityPreflightCall(root,current));
            if(current)assert([value isEqual:before]);else before=value;
            assert(capabilityCalls==1&&foregroundCalls==(root?0U:1U)&&jsonCalls==1&&base64Calls==1);
        }}
    }
    reset();
}
static void capabilityPreflightCases(){
    std::puts("AX capability preflight: actual/C05z Task77 branches, real native budgets/JSON/codecs and counted capability/foreground provider seams");
    capabilityStoppedEntryCases();capabilityProviderStopCases();capabilityProviderFaultCases();capabilityCleanupCases();capabilityRecoveryCases();
    std::puts("AX capability preflight passed: zero providers/JSON for stopped entry, post-probe foreground refusal, captured nested caller, cancel/deadline/output priority, NS/C++ propagation/weak retirement and 256 cancelled/recovered full-graph cases. Actual private probes/device latency remain unqualified.");
}
