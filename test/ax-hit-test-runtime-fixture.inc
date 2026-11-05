static NSDictionary *hitCall(bool current,CGPoint point=CGPointMake(30,30),pid_t pid=123){
    return current?TLinkAXElementAtPoint(pid,@"fixture.bundle",point):PrecedingAXElementAtPoint(pid,@"fixture.bundle",point);
}
static void hitErrorCode(NSDictionary *value,NSString *code){
    if([value[@"ok"] boolValue]||![value[@"error"] isEqualToString:code])NSLog(@"AX hit error mismatch expected=%@ actual=%@",code,value);
    assert(![value[@"ok"] boolValue]&&[value[@"error"] isEqualToString:code]);
}
static void hitOwnersRetired(){
    const bool retired=rootRetains==rootDrops&&hitRetains==hitDrops;
    if(!retired)std::fprintf(stderr,"AX hit owners: root=%u/%u hit=%u/%u\n",rootRetains,rootDrops,hitRetains,hitDrops);
    assert(retired);
}
static void hitParityCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;unsigned oldCreates=0,oldCalls=0,oldRoots=0,oldHits=0;std::vector<uint32_t> oldKeys;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();node.frame=CGRectMake(10+n%9,20,40,20);node.traits=@(n%512);node.point=CGPointMake(30,30);
                if(n%5==0)badFrame=true;if(n%7==0)sTLinkAXSetTimeout=nullptr;
                if(n%11==0)hitError=true;if(n%13==0)hitMissing=true;if(n%17==0)hitRootMissing=true;
                if(n%19==0)hitPrepared=false;if(n%23==0)hitLocked=true;if(n%29==0)hitScreenOff=true;if(n%31==0)sTLinkAXHitTest=nullptr;
                NSDictionary *value=hitCall(current,CGPointMake(30.125,30.25));
                if(current){
                    if(![value isEqual:expected])NSLog(@"AX hit parity failure seed=%u expected=%@ actual=%@",n,expected,value);
                    assert([value isEqual:expected]&&hitCreates==oldCreates&&hitCalls==oldCalls&&rootDrops==oldRoots&&hitDrops==oldHits&&keys==oldKeys);
                    NSData *oldJSON=[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingSortedKeys error:NULL];
                    NSData *newJSON=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
                    assert(oldJSON&&[newJSON isEqual:oldJSON]);
                }else{expected=value;oldCreates=hitCreates;oldCalls=hitCalls;oldRoots=rootDrops;oldHits=hitDrops;oldKeys=keys;}
                if(hitSetters)assert(std::fabs(hitRootTimeout-.5)<1e-6);hitOwnersRetired();
            }
            assert(boxes==0&&!lastBox);
        }
    }
    for(unsigned kind=0;kind<5;++kind){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            reset();CGPoint point=CGPointMake(30,30);pid_t pid=123;
            if(kind==0)pid=0;if(kind==1)point.x=NAN;if(kind==2)point.y=INFINITY;if(kind==3)point.x=-1;if(kind==4)hitSkipDispatch=true;
            NSDictionary *value=hitCall(current,point,pid);if(current)assert([value isEqual:expected]);else expected=value;
            assert(hitCreates==0&&hitCalls==0);hitOwnersRetired();
        }
    }
}
static void hitDeadlineCases(){
    for(bool expired:{false,true}){
        reset();if(expired)parent.reset(new ParentBudget{tick});else cancelled=true;
        hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");assert(hitDispatches==0&&hitCreates==0&&hitCalls==0);hitOwnersRetired();
    }
    @autoreleasepool{
        reset();parent.reset(new ParentBudget{tick+20000000ULL});const uint64_t end=parent->end;hitCreateCost=5000000ULL;hitCallCost=1000000ULL;
        NSDictionary *value=hitCall(true);assert([value[@"ok"] boolValue]&&[value[@"found"] boolValue]);
        assert(std::fabs(hitRootTimeout-.015)<1e-6&&parent->end==end&&keys.size()==6);hitOwnersRetired();
    }
    @autoreleasepool{
        reset();parent.reset(new ParentBudget{tick+2000000000ULL});hitCall(true);assert(std::fabs(hitRootTimeout-.5)<1e-6);hitOwnersRetired();
    }
    for(unsigned phase=0;phase<11;++phase){
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+20000000ULL});const uint64_t end=parent->end;
            switch(phase){case 0:hitQueueCost=20000000ULL;break;case 1:hitLockCost=20000000ULL;break;
                case 2:hitPrepareCost=20000000ULL;break;case 3:hitCreateCost=20000000ULL;break;case 4:rootSetupCost=20000000ULL;break;
                case 5:hitCallCost=20000000ULL;break;case 6:hitRootDropCost=20000000ULL;break;case 7:hitDropCost=20000000ULL;break;
                case 8:attributeCost=20000000ULL;break;case 9:hitPostQueueCost=20000000ULL;break;case 10:hitScreenCost=20000000ULL;break;}
            hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");assert(parent->end==end);hitOwnersRetired();
            if(phase<=2||phase==10)assert(hitCreates==0&&hitCalls==0);
            if(phase==3||phase==4)assert(rootRetains==1&&hitCalls==0);
            if(phase==3)assert(hitSetters==0);
            if(phase==5||phase==6)assert(hitCalls==1&&keys.empty());
            if(phase==8)assert(keys.size()==1);
        }
        assert(boxes==0&&!lastBox);
    }
    @autoreleasepool{
        reset();parent.reset(new ParentBudget{tick+20000000ULL});sTLinkAXSetTimeout=nullptr;hitCallCost=20000000ULL;
        hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");assert(hitSetters==0&&hitCalls==1&&keys.empty());hitOwnersRetired();
    }
    for(unsigned phase:{1U,2U,3U,4U,5U,8U}){
        @autoreleasepool{reset();hitCancelPhase=phase;hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");hitOwnersRetired();}
        assert(boxes==0);
    }
    for(unsigned at:{1U,6U}){
        @autoreleasepool{reset();cancelAt=at;hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");assert(keys.size()==at);hitOwnersRetired();}
        assert(boxes==0&&!lastBox);
    }
    // Without a caller budget the historical per-RPC limits remain; no new
    // implicit 500ms total window is introduced.
    @autoreleasepool{
        reset();hitCallCost=600000000ULL;attributeCost=100000000ULL;
        NSDictionary *value=hitCall(true);assert([value[@"ok"] boolValue]&&[value[@"found"] boolValue]&&keys.size()==6);hitOwnersRetired();
    }
}
static void hitFaultCases(){
    for(unsigned phase:{3U,4U,5U,6U}){
        for(unsigned kind:{1U,2U}){
            @autoreleasepool{
                reset();bool caught=false;NSDictionary *value=nil;
                if(phase==6){throwKey=2003;throwKind=kind;}else{hitFaultPhase=phase;hitFaultKind=kind;}
                try{value=hitCall(true);}catch(const std::runtime_error &){caught=kind==2;}
                assert(caught==(kind==2));hitOwnersRetired();
                if(kind==1){
                    if(phase==6)assert([value[@"ok"] boolValue]&&![value[@"found"] boolValue]);
                    else hitErrorCode(value,@"ui_ax_exception");
                }
                if(phase==5||phase==6)assert(hitRetains==1&&hitDrops==1);
            }
            // Exception-exited pools drain at this normal enclosing boundary.
            assert(boxes==0&&!lastBox);
            @autoreleasepool{reset();assert([hitCall(true)[@"found"] boolValue]);hitOwnersRetired();}
        }
    }
}
static void hitTestCases(){
    std::puts("AX hit-test Foundation: complete actual/frozen public helper, actual attribute/serializer, controlled dispatch/AX/parent and real CF/CG ownership");
    hitParityCases();hitDeadlineCases();hitFaultCases();
    NSDictionary *held=nil;
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{reset();node.label=[NSMutableString stringWithFormat:@"hit-%u-测试",n];held=hitCall(true);hitOwnersRetired();}
        assert([held[@"element"][@"label"] length]>0&&boxes==0&&!lastBox);
    }
    held=nil;parent.reset();node=nil;rootObject=nil;
    std::puts("AX hit-test passed: 128 frozen graphs/JSON/provider cases, original invalid/lock/fallback fields, caller remainder/500ms clamp, queue/setup/query/serialization/cleanup expiry and cancellation, missing setter, NS/C++ root/hit/out-value cleanup and 128 pool lifecycles. No new standalone total deadline; private AX/device qualification pending.");
}
