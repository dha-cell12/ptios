static NSData *beforeWirePublishCall(bool capability,NSDictionary *graph){
    if(capability)BeforeWirePublishRootCapability(NULL);else BeforeWirePublishRootResponse(graph,NULL);
    return captured;
}
static void wirePublishRetentionCases(){
    for(bool capability:{false,true}){
        NSMutableArray *before=[NSMutableArray array];
        for(bool current:{false,true}){
            TLinkAXFixtureResetOwners();NSData *held=nil;NSDictionary *expected=nil;
            @autoreleasepool{
                for(unsigned n=0;n<128;++n){
                    reset();wirePoolStages=12;wirePublishChurn=true;
                    NSDictionary *graph=@{@"ok":@YES,@"n":@(n),@"text":@"Ứng dụng 测试😀\n\"\\",@"nested":@[@{},@[@1,[NSNull null]]]};fixtureCapability=graph;
                    held=current?call(true,capability,true,graph):beforeWirePublishCall(capability,graph);
                    expected=decoded(held);
                    if(current)assert([expected isEqual:before[n]]);else [before addObject:expected];
                    assert(jsonCalls==1&&base64Calls==1&&wireFinalCalls==1&&wireNotifyCalls==1);
                    assert(TLinkAXFixtureCreatedOwners()==2*(n+1));
                    assert(TLinkAXFixtureLiveOwners()==(current?0U:2*(n+1)));
                    assert(TLinkAXFixturePeakOwners()==(current?2U:2*(n+1)));
                }
            }
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==256);
            assert([decoded(held) isEqual:expected]);
        }
    }
    reset();
}
static void wirePublishPreflightCases(){
    for(bool capability:{false,true})for(unsigned kind:{0U,2U})for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            reset();wirePoolStages=12;wireEffectStage=2;wireEffectKind=kind;
            wireEffectCancellation=std::make_shared<TLinkNativeCancellation>();
            auto parent=std::make_shared<TLinkNativeBudget>(wireEffectCancellation,0,1024*1024,false,true);
            auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;wireEffectBudget=budget;
            TLinkNativeBudgetScope scope(budget);
            NSData *reply=current?call(true,capability,true,@{@"ok":@YES}):beforeWirePublishCall(capability,@{@"ok":@YES});
            errorReply(reply,kind==0?@"ui_cancelled_or_timed_out":@"ui_response_too_large");
            assert(wireEffectCalls==1&&wireNotifyCalls==1&&wireFinalCalls==1);
            assert(TLinkAXFixtureCreatedOwners()==2&&TLinkAXFixtureLiveOwners()==(current?0U:2U));
            assert(budget->reason()==(kind==0?TLinkNativeStop::Cancelled:TLinkNativeStop::OutputLimit));
            wireEffectCancellation.reset();
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==2);
    }
    reset();
}
static void wirePublishCommittedCases(){
    for(bool capability:{false,true})for(unsigned action:{1U,2U})for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            reset();wirePoolStages=8;wirePoolDrainAction=action;
            wirePoolCancellation=std::make_shared<TLinkNativeCancellation>();
            auto parent=std::make_shared<TLinkNativeBudget>(wirePoolCancellation,0,1024*1024,false,true);
            auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;wirePoolBudget=budget;
            TLinkNativeBudgetScope scope(budget);
            NSData *reply=current?call(true,capability,true,@{@"ok":@YES}):beforeWirePublishCall(capability,@{@"ok":@YES});
            // The observer already copied the success during notify. Pool drain
            // may stop the caller afterward; it must not replay/replace bytes.
            decoded(reply);assert(wireNotifyCalls==1);
            assert(wirePoolActionCalls==(current?1U:0U));
            assert(TLinkAXFixtureLiveOwners()==(current?0U:1U));
            assert(budget->reason()==(current&&action==1?TLinkNativeStop::Cancelled:TLinkNativeStop::None));
            assert(parent->response().empty()==(!current||action==1));
            wirePoolDrainAction=0;wirePoolCancellation.reset();
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
    }
    reset();
}
static void wirePublishFaultCases(){
    for(bool capability:{false,true})for(unsigned site:{4U,8U}){
        for(unsigned kind:{1U,2U})for(bool current:{false,true}){
            TLinkAXFixtureResetOwners();std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();wirePoolStages=site;wirePoolThrowKind=kind;
                auto budget=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024*1024);weak=budget;
                TLinkNativeBudgetScope scope(budget);bool caught=false;
                @try{try{if(current)call(true,capability,true,@{@"ok":@YES});else beforeWirePublishCall(capability,@{@"ok":@YES});}
                    catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"WirePoolFixture"];}
                assert(caught&&!captured&&wireNotifyCalls==(site==8?1U:0U));
                assert(TLinkAXFixtureCreatedOwners()==1);
            }
            assert(weak.expired()&&!TLinkCurrentNativeBudget());
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
        }
    }
    reset();
}
static void wirePublishPoolCases(){
    std::puts("AX root publication pool: actual/C05y result/capability codecs, real UTF8/copy observer and explicit MRC pending owners");
    wirePublishRetentionCases();wirePublishPreflightCases();wirePublishCommittedCases();wirePublishFaultCases();
    std::puts("AX root publication pool passed: 128 calls/256 witnesses per route, peak two vs 256 pending, exact held wires/graphs across nested churn/pool drain, unchanged pre-notify refusal, accepted-copy no replay and NS/C++ outer-drain cleanup. Actual transport/device memory remain unqualified.");
}
