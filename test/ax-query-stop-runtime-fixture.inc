static NSDictionary *queryBoundaryCall(bool current,bool find,NSDictionary *request=@{}){
    if(find)return current?TLinkAXFindElement(123,@"fixture.bundle",request):BeforeStopAXFindElement(123,@"fixture.bundle",request);
    return current?TLinkAXCopySnapshot(123,@"fixture.bundle",request):BeforeStopAXCopySnapshot(123,@"fixture.bundle",request);
}
static void queryBoundaryReset(){reset();resetFind();}
static void queryCancelled(NSDictionary *value){
    expectError(value,@"ui_cancelled_or_timed_out");
    assert([value[@"partial"] boolValue]&&!TLinkAXResultCompleteForAction(value));
}
static void queryBoundaryGoldenCases(){
    for(bool find:{false,true}){
        for(unsigned n=0;n<128;++n){
            NSDictionary *expected=nil;unsigned oldCreates=0,oldQueries=0,oldSerialized=0;
            for(bool current:{false,true}){
                @autoreleasepool{
                    queryBoundaryReset();sourceCount=n%9;nodeCost=(n%3)*1000000ULL;failEvery=n%5==0?3:0;
                    if(n%11==0)prepared=false;if(n%13==0)rootMissing=true;if(n%17==0)queryError=true;
                    NSDictionary *request=@{@"identifier":@"id",@"max_elements":@(1+n%3),@"timeout_ms":@100,@"index":@(n%3),@"visible_only":@((n&1)!=0)};
                    NSDictionary *value=queryBoundaryCall(current,find,request);
                    if(current){
                        assert([value isEqual:expected]&&[findJSON(value) isEqualToData:findJSON(expected)]);
                        assert(creates==oldCreates&&queries==oldQueries&&serialized==oldSerialized);
                    }else{expected=value;oldCreates=creates;oldQueries=queries;oldSerialized=serialized;}
                    assert(boundaryDispatches==1&&rootRetains==rootDrops);
                }
                assert(!returnedArray);
            }
        }
    }
}
static void queryBoundaryStopCases(){
    NSDictionary *request=@{@"identifier":@"id"};
    for(bool find:{false,true}){
        for(unsigned phase=0;phase<3;++phase){
            for(bool current:{false,true}){
                @autoreleasepool{
                    queryBoundaryReset();
                    if(phase==0)cancelled=true;
                    if(phase==1)boundaryQueueStop=true;
                    if(phase==2)boundaryReturnStop=true;
                    NSDictionary *value=queryBoundaryCall(current,find,request);
                    if(current)queryCancelled(value);
                    else if(phase==2)assert([value[@"ok"] boolValue]);
                    else expectError(value,find?@"ui_find_failed":@"ui_snapshot_failed");
                    assert(boundaryDispatches==(current&&phase==0?0U:1U));
                    if(phase<2)assert(lockCalls==0&&prepareCalls==0&&creates==0&&queries==0&&serialized==0);
                    assert(rootRetains==rootDrops);
                }
                assert(!returnedArray);
            }
        }
        for(bool current:{false,true}){
            @autoreleasepool{
                queryBoundaryReset();prepared=false;boundaryReturnStop=true;
                NSDictionary *value=queryBoundaryCall(current,find,request);
                if(current)queryCancelled(value);else expectError(value,@"ui_axruntime_unavailable");
                assert(creates==0&&queries==0&&rootRetains==rootDrops);
            }
        }
    }
    // Find's existing public selector validation still runs before its stop gate.
    for(unsigned kind=0;kind<2;++kind){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){
            queryBoundaryReset();cancelled=true;id selector=kind==0?(id)@42:(id)@{};
            NSDictionary *value=current?TLinkAXFindElement(123,@"fixture.bundle",selector):BeforeStopAXFindElement(123,@"fixture.bundle",selector);
            if(current)assert([value isEqual:expected]);else expected=value;
            expectError(value,kind==0?@"ui_selector_invalid":@"ui_selector_requires_text_identifier_or_role");
            assert(boundaryDispatches==0&&creates==0);
        }
    }
}
static void queryLastRowCases(){
    for(unsigned kind=0;kind<5;++kind){
        TLinkFixtureFindFlag *flag=[TLinkFixtureFindFlag new];
        NSArray *rows=kind==0?@[]:@[@{@"identifier":kind==4?@"miss":@"target",@"intersects_screen":flag,@"clickable":flag}];
        NSDictionary *input=findInput(rows);
        NSDictionary *selector=kind==3?@{@"identifier":@"target",@"visible_only":@NO,@"clickable_only":@YES}:@{@"identifier":@"target"};
        for(bool current:{false,true}){
            @autoreleasepool{
                queryBoundaryReset();findFlagReturns=kind!=2&&kind!=3;findCancelAt=1;
                if(kind==0)cancelled=true;
                NSDictionary *value=current?TLinkAXFindInSnapshot(input,selector):BeforeStopAXFindInSnapshot(input,selector);
                if(current)queryCancelled(value);
                else assert([value[@"ok"] boolValue]&&TLinkAXResultCompleteForAction(value));
                assert(findFlagReads==(kind==0?0U:1U));
            }
        }
    }
    queryBoundaryReset();cancelled=true;
    NSDictionary *error=TLinkAXError(@"existing_error",@{@"partial":@YES});
    assert(TLinkAXFindInSnapshot(error,@{})==error&&BeforeStopAXFindInSnapshot(error,@{})==error);
}
static void queryStopCases(){
    std::puts("AX query stop: complete current/C05l public wrappers and matcher, actual snapshot/CF owners with modeled queue/return cancellation");
    queryBoundaryGoldenCases();queryBoundaryStopCases();queryLastRowCases();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            queryBoundaryReset();boundaryReturnStop=true;
            queryCancelled(queryBoundaryCall(true,n%2!=0,@{@"identifier":@"id"}));assert(rootRetains==rootDrops);
        }
        assert(!returnedArray);
    }
    queryBoundaryReset();
    std::puts("AX query stop passed: 256 frozen public graph/JSON/work-count cases, pre-entry/queued/post-return cancellation, zero pre-stopped work, selector validation/error passthrough, empty/last match/visibility/clickability/mismatch refusal and 128 balanced cycles. Queue preemption/admission/device qualification pending.");
}
