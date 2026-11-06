static NSData *beforeWirePoolCall(bool root,bool capability,NSDictionary *value){
    if(root){
        if(capability)BeforeWirePoolRootCapability(NULL);else BeforeWirePoolRootResponse(value,NULL);
        return captured;
    }
    return capability?BeforeWirePoolTrollCapability():BeforeWirePoolTrollResponse(value);
}
static void wirePoolRetentionCases(){
    for(bool root:{false,true})for(bool capability:{false,true}){
      NSMutableArray *before=[NSMutableArray array];
      for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();NSData *held=nil;NSDictionary *expected=nil;
        @autoreleasepool{
            for(unsigned n=0;n<128;++n){
                reset();wirePoolStages=3;
                NSDictionary *graph=@{@"ok":@YES,@"n":@(n),@"text":@"Ứng dụng 测试😀\n\"\\",@"nested":@[@{},@[@1,[NSNull null]]]};fixtureCapability=graph;
                held=current?call(root,capability,true,graph):beforeWirePoolCall(root,capability,graph);
                expected=decoded(held);assert([expected[@"text"] isEqualToString:graph[@"text"]]);
                if(current)assert([expected isEqual:before[n]]);else [before addObject:expected];
                assert(TLinkAXFixtureCreatedOwners()==2*(n+1));
                assert(TLinkAXFixtureLiveOwners()==(current?0U:2*(n+1)));
                assert(TLinkAXFixturePeakOwners()==(current?1U:2*(n+1)));
                assert(jsonCalls==1&&base64Calls==1&&wireFinalCalls==1);
            }
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==256);
        assert([decoded(held) isEqual:expected]);
      }
    }
    reset();
}
static void wirePoolDrainStopCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(unsigned stage:{1U,2U}){
        for(unsigned action:{1U,2U})for(bool current:{false,true}){
            TLinkAXFixtureResetOwners();std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();wirePoolStages=stage;wirePoolDrainAction=action;
                wirePoolCancellation=std::make_shared<TLinkNativeCancellation>();
                auto parent=std::make_shared<TLinkNativeBudget>(wirePoolCancellation,0,1024*1024,false,true);
                auto budget=std::make_shared<TLinkNativeBudget>(0,parent);weak=budget;wirePoolBudget=budget;
                TLinkNativeBudgetScope scope(budget);
                NSDictionary *graph=@{@"ok":@YES,@"text":@"held through drain"};fixtureCapability=graph;
                NSData *reply=current?call(root,capability,true,graph):beforeWirePoolCall(root,capability,graph);
                if(current){
                    errorReply(reply,action==1?@"ui_cancelled_or_timed_out":@"ui_response_too_large");
                    assert(wirePoolActionCalls==1&&TLinkAXFixtureLiveOwners()==0);
                    assert(budget->reason()==(action==1?TLinkNativeStop::Cancelled:TLinkNativeStop::OutputLimit));
                    assert(wireFinalCalls==(stage==1?0U:1U));
                }else{
                    decoded(reply);assert(wirePoolActionCalls==0&&TLinkAXFixtureLiveOwners()==1);
                    assert(budget->reason()==TLinkNativeStop::None&&wireFinalCalls==1);
                }
                assert(base64Calls==1);
                // The old pending witness drains after the caller is no longer
                // running; it must not mutate another request at caller drain.
                wirePoolDrainAction=0;wirePoolCancellation.reset();
            }
            assert(weak.expired()&&!TLinkCurrentNativeBudget());
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
        }
    }
    reset();
}
static void wirePoolUnwindCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(unsigned stage:{1U,2U}){
        for(unsigned kind:{1U,2U})for(bool current:{false,true}){
            TLinkAXFixtureResetOwners();std::weak_ptr<TLinkNativeBudget> weak;
            @autoreleasepool{
                reset();wirePoolStages=stage;wirePoolThrowKind=kind;
                auto budget=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1024*1024);weak=budget;
                TLinkNativeBudgetScope scope(budget);bool caught=false;
                @try{try{if(current)call(root,capability,true,@{@"ok":@YES});else beforeWirePoolCall(root,capability,@{@"ok":@YES});}
                    catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"WirePoolFixture"];}
                assert(caught&&TLinkAXFixtureCreatedOwners()==1);
            }
            // Exception-exited Clang pools are not assumed to drain. A normal
            // enclosing caller pool supplies the final ownership assertion.
            assert(weak.expired()&&!TLinkCurrentNativeBudget());
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1);
        }
    }
    reset();
}
static void wirePhasePoolCases(){
    std::puts("AX wire phase pools: real JSON/base64/formatting, actual/C05x codecs and explicit MRC pending owners");
    wirePoolRetentionCases();wirePoolDrainStopCases();wirePoolUnwindCases();
    std::puts("AX wire phase pools passed: 128 calls/256 owners per route, peak one vs 256 pending witnesses, held result after pools, drain-time cancellation/output refusal and NS/C++ outer-drain cleanup. Sentinel counts are not Foundation allocation/device RSS measurements.");
}
