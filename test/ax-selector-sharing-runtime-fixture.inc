@interface AXSelectorCopyProbe:NSObject <NSCopying>
@property(nonatomic) unsigned behavior;
@end
@implementation AXSelectorCopyProbe
-(id)copyWithZone:(NSZone *)zone{
    (void)zone;
    if(self.behavior==1)return @"different";
    if(self.behavior==2)[NSException raise:@"AXCopyFixture" format:@"copy"];
    if(self.behavior==3)throw std::runtime_error("copy");
    return self;
}
@end
static void selectorSharingCases(){
    for(unsigned behavior=0;behavior<4;++behavior){
        @autoreleasepool{
            selectorReset();TLinkAXFixtureResetOwners();AXSelectorCopyProbe *probe=[AXSelectorCopyProbe new];probe.behavior=behavior;
            NSString *input=(NSString *)(id)probe;
            assert(!MeasuredAXSelectorPlan::StableString(input)&&selectorCopyCalls==0);
            selectorTrackCopyOwners=true;
            assert(MeasuredAXSelectorPlan::CopyIdentity(input)==(behavior==0));
            assert(selectorCopyCalls==1&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureDroppedOwners()==1&&TLinkAXFixtureLiveOwners()==0);
        }
    }
    selectorReset();assert(!MeasuredAXSelectorPlan::CopyIdentity(nil));
    NSMutableString *mutableText=[@"target" mutableCopy];assert(!MeasuredAXSelectorPlan::CopyIdentity(mutableText)&&!MeasuredAXSelectorPlan::StableString(mutableText));
    NSMutableArray *rows=[NSMutableArray array];
    for(unsigned n=0;n<1000;++n){
        [rows addObject:@{@"index":@(n),@"identifier":@"ID",@"role":@"BUTTON",@"label":@"TARGET",@"value":@"TARGET VALUE",@"intersects_screen":@YES,@"clickable":@YES}];
    }
    NSDictionary *input=findInput(rows),*selector=@{@"identifier":@"id",@"role":@"button",@"text":@"target",@"index":@999};
    NSDictionary *before=nil;
    for(bool shared:{false,true}){
        @autoreleasepool{
            selectorReset();selectorClassPolicy=1;selectorExpected=@[selector[@"identifier"],selector[@"role"],selector[@"text"]];
            NSDictionary *value=shared?MeasuredAXFindInSnapshot(input,selector):BeforeSharedAXFindInSnapshot(input,selector);
            if(shared)assert([value isEqual:before]);else before=value;
            assert(selectorExpectedFolds==3&&selectorFolds==4003&&selectorClassChecks==(shared?5U:6U)&&selectorModeComparisons==(shared?3U:5U));
            assert([value[@"match_count"] unsignedIntegerValue]==1000&&value[@"element"]==rows[999]);
        }
    }
    for(unsigned kind:{1U,2U}){
        for(unsigned site:{1U,2U}){
            @autoreleasepool{
                selectorReset();selectorClassPolicy=1;selectorModeFaultAt=site;selectorModeFaultKind=kind;
                MeasuredAXSelectorPlan::Mode mode(@"prefix");MeasuredAXSelectorPlan::Text first(@"t",mode,NO),second(@"ta",mode,NO);bool caught=false;
                @try{try{first.accepts(@"target",MeasuredAXTextMatches);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"AXModeFixture"];}
                assert(caught&&selectorModeComparisons==site);selectorModeFaultAt=0;const NSUInteger calls=selectorModeComparisons;
                assert(first.accepts(@"target",MeasuredAXTextMatches)&&selectorModeComparisons==calls+2);
                assert(second.accepts(@"target",MeasuredAXTextMatches)&&selectorModeComparisons==calls+2);
            }
        }
    }
    for(unsigned policy:{0U,2U,3U}){
        @autoreleasepool{
            selectorReset();selectorClassPolicy=policy;NSMutableString *modeText=[@"prefix" mutableCopy];
            NSString *firstValue=@"tar",*secondValue=@"ta";selectorForcedExpected=@[firstValue,secondValue];
            MeasuredAXSelectorPlan::Mode mode(modeText);MeasuredAXSelectorPlan::Text first(firstValue,mode,NO),second(secondValue,mode,NO);
            assert(first.accepts(@"target",MeasuredAXTextMatches));[modeText setString:@"exact"];
            assert(!first.accepts(@"target",MeasuredAXTextMatches)&&!second.accepts(@"target",MeasuredAXTextMatches)&&selectorModeComparisons==0);
        }
    }
    @autoreleasepool{
        selectorReset();selectorClassPolicy=3;AXSelectorExpectedProbe *probe=[AXSelectorExpectedProbe new];probe.value=@"prefix";
        NSString *firstValue=@"tar",*secondValue=@"ta";selectorForcedExpected=@[firstValue,secondValue];
        MeasuredAXSelectorPlan::Mode mode((NSString *)(id)probe);MeasuredAXSelectorPlan::Text first(firstValue,mode,NO),second(secondValue,mode,NO);
        assert(first.accepts(@"target",MeasuredAXTextMatches));probe.value=@"exact";
        assert(!first.accepts(@"target",MeasuredAXTextMatches)&&!second.accepts(@"target",MeasuredAXTextMatches)&&selectorModeComparisons==0&&selectorCopyCalls==0);
    }
    selectorReset();std::puts("AX selector sharing passed: copy-identity true/refusal/NS-C++ cleanup without custom-class admission, mutable refusal, 1000 frozen graphs with 5 vs6 class checks/3 vs5 mode comparisons, shared decode retry and mutable mode freshness. Actual Foundation eligibility/device gains pending.");
}
