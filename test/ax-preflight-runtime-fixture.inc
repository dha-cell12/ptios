// Controlled option normalization; no Foundation number/class-cluster assumptions.
@interface AXPreflightNumber:NSObject
@property(nonatomic) BOOL stopOnRead;
@property(nonatomic) uint64_t cost;
-(NSInteger)integerValue;
@end
@implementation AXPreflightNumber
-(NSInteger)integerValue{++preflightOptionReads;tick+=self.cost;if(self.stopOnRead)cancelled=true;return 1500;}
@end
static NSDictionary *preflightCall(bool current,NSDictionary *options=@{},pid_t pid=123){
    return current?TLinkAXCopySnapshotUnlocked(pid,@"fixture.bundle",options):BeforePreflightAXCopySnapshotUnlocked(pid,@"fixture.bundle",options);
}
static void preflightGoldenCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;unsigned oldSerialized=0,oldQueries=0,oldDrops=0;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();sourceCount=n%13;queryCost=2000000ULL;nodeCost=(n%3)*1000000ULL;failEvery=n%7==0?3:0;
                preflightLockCost=preflightPrepareCost=preflightScreenCost=1000000ULL;
                NSDictionary *options=@{@"max_elements":@(1+n%7),@"max_scanned_elements":@(1+n%9),
                    @"timeout_ms":@100,@"visible_only":@((n&1)!=0),@"clickable_only":@((n&2)!=0)};
                NSDictionary *value=preflightCall(current,options);
                if(current){
                    assert([value isEqual:expected]&&[findJSON(value) isEqualToData:findJSON(expected)]);
                    assert(serialized==oldSerialized&&queries==oldQueries&&rootDrops==oldDrops);
                }else{expected=value;oldSerialized=serialized;oldQueries=queries;oldDrops=rootDrops;}
                assert(rootRetains==rootDrops&&arrayDrops==0&&lockCalls==1&&prepareCalls==1);
            }
            assert(!returnedArray);
        }
    }
}
static void preflightStopCases(){
    for(bool deadline:{false,true}){
        for(bool empty:{false,true}){
            for(unsigned stage=0;stage<=5;++stage){
                NSDictionary *expected=nil;
                for(bool current:{false,true}){
                    @autoreleasepool{
                        reset();sourceCount=empty?0:4;
                        AXPreflightNumber *number=[AXPreflightNumber new];
                        if(deadline){
                            parent.reset(new ParentBudget);parent->end=tick+(stage==0?0:20000000ULL);
                            if(stage==1)preflightLockCost=20000000ULL;
                            if(stage==2)preflightPrepareCost=20000000ULL;
                            if(stage==3)number.cost=20000000ULL;
                            if(stage==4)queryCost=20000000ULL;
                            if(stage==5)preflightScreenCost=20000000ULL;
                        }else{
                            if(stage==0)cancelled=true;
                            else if(stage==3)number.stopOnRead=YES;
                            else preflightStopStage=stage;
                        }
                        NSDictionary *value=preflightCall(current,@{@"timeout_ms":number});
                        expectError(value,@"ui_cancelled_or_timed_out");
                        assert([value[@"partial"] boolValue]==(stage>=4));
                        if(current)assert([value isEqual:expected]);else expected=value;
                        assert(serialized==0&&rootRetains==rootDrops);
                        assert(lockCalls==(current&&stage==0?0U:1U));
                        assert(prepareCalls==(current&&stage<=1?0U:1U));
                        assert(preflightOptionReads==(current&&stage<=2?0U:1U));
                        assert(creates==(current&&stage<=3?0U:1U));
                        assert(queries==(stage>=4?1U:0U));
                        assert(preflightScreenReads==(stage>=4&&(!current||stage==5)?1U:0U));
                        if(stage==4){assert(rawOutRetains==1&&arrayDrops==(current?1U:0U));}
                        else assert(arrayDrops==0);
                    }
                    assert(!returnedArray);
                }
            }
        }
    }
}
static void preflightPriorityCases(){
    for(bool current:{false,true}){
        reset();cancelled=true;expectError(preflightCall(current,@{},0),@"ui_invalid_pid");assert(lockCalls==0&&creates==0);
        for(unsigned kind=0;kind<3;++kind){
            @autoreleasepool{
                reset();preflightStopStage=4;queryError=kind==0;queryMissing=kind==1;wrongArray=kind==2;
                expectError(preflightCall(current),@"ui_element_query_failed");snapshotRawOwnersRetired();assert(preflightScreenReads==0);
            }
            assert(!returnedArray);
        }
        @autoreleasepool{
            reset();sourceCount=0;queryCost=120000000ULL;
            NSDictionary *value=preflightCall(current,@{@"timeout_ms":@100});
            assert([value[@"ok"] boolValue]&&[value[@"partial"] boolValue]&&[value[@"truncated"] boolValue]);
            assert([value[@"duration_ms"] intValue]==120&&!TLinkAXResultCompleteForAction(value));
        }
        assert(!returnedArray);
    }
    // A newly observed stop precedes stale lock/prepare failure, as at public return.
    for(unsigned stage:{1U,2U}){
        reset();preflightStopStage=stage;locked=stage==1;prepared=stage!=2;
        expectError(preflightCall(true),@"ui_cancelled_or_timed_out");assert(creates==0);
    }
    // A provider exception still takes its original path before the post-query gate.
    for(unsigned kind:{1U,2U}){
        @autoreleasepool{
            reset();preflightStopStage=4;ownerFaultSite=4;ownerFaultKind=kind;bool caught=false;
            try{NSDictionary *value=preflightCall(true);expectError(value,@"ui_ax_exception");caught=kind==1;}
            catch(const std::runtime_error &){caught=kind==2;}
            assert(caught&&preflightScreenReads==0);snapshotRawOwnersRetired();
        }
        assert(!returnedArray);
    }
}
static void preflightCases(){
    std::puts("AX snapshot preflight: actual/C05o snapshots with controlled stop/deadline providers and real CF ownership");
    preflightGoldenCases();preflightStopCases();preflightPriorityCases();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();preflightStopStage=4;
            expectError(preflightCall(true),@"ui_cancelled_or_timed_out");snapshotRawOwnersRetired();
        }
        assert(!returnedArray);
        @autoreleasepool{reset();assert([preflightCall(true)[@"ok"] boolValue]&&rootRetains==rootDrops);}
        assert(!returnedArray);
    }
    reset();
    std::puts("AX snapshot preflight passed: 128 frozen graphs/JSON/work counts, six explicit/parent-stop stages with empty/nonempty arrays, skipped lock/prepare/options/root/screen work, query-error priority, raw out retirement, local-only partials, unwind and 128 recovery cycles. AX/device qualification pending.");
}
