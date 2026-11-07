static NSUInteger selectorFolds,selectorExpectedFolds,selectorStopAt,selectorFaultAt;
static unsigned selectorFaultKind;
static unsigned selectorClassPolicy=0; // 0: actual classifier; 1: force fast in the immutable-only scenario; 2: compatibility only.
static NSArray *selectorExpected;
// A non-Foundation expected string facade: it must keep the complete
// compatibility dispatch and observe content changes between calls.
@interface AXSelectorExpectedProbe:NSObject
@property(nonatomic,copy) NSString *value;
@property(nonatomic) unsigned folds;
-(NSUInteger)length;
-(NSString *)lowercaseString;
@end
@implementation AXSelectorExpectedProbe
-(BOOL)isKindOfClass:(Class)type{return type==[NSString class]||[super isKindOfClass:type];}
-(NSUInteger)length{return self.value.length;}
-(NSString *)lowercaseString{++self.folds;return [self.value lowercaseString];}
@end
static NSString *fixtureSelectorFold(NSString *text){
    ++selectorFolds;for(NSString *expected in selectorExpected)if(text==expected){++selectorExpectedFolds;break;}
    if(selectorFolds==selectorStopAt)cancelled=true;
    if(selectorFolds==selectorFaultAt){if(selectorFaultKind==1)[NSException raise:@"AXSelectorFixture" format:@"fold"];if(selectorFaultKind==2)throw std::runtime_error("selector fold");}
    return [text lowercaseString];
}
static bool fixtureSelectorStableString(NSString *text);
#include "AXSelectorPlanMeasured.inc"
static bool fixtureSelectorStableString(NSString *text){
    if(selectorClassPolicy==0)return MeasuredAXSelectorPlan::StableString(text);
    if(selectorClassPolicy==2)return false;
    // Policy 1 is used only by the all-immutable 1000-row matrix. This isolates
    // plan reuse from platform-specific Foundation class identities.
    return true;
}
#include "AXSelectorBeforePlan.inc"
#include "AXSelectorMeasured.inc"
static void selectorReset(){queryBoundaryReset();selectorFolds=selectorExpectedFolds=selectorStopAt=selectorFaultAt=selectorFaultKind=selectorClassPolicy=0;selectorExpected=nil;}
static void selectorPlanCases(){
    std::puts("AX selector plans: complete actual/frozen matcher and measured production plan; immutable fields versus mutable/custom fallback");
    NSMutableArray *rows=[NSMutableArray array];
    for(unsigned n=0;n<1000;++n)[rows addObject:@{@"index":@(n),@"identifier":@"ID",@"role":@"BUTTON",@"label":@"TARGET",@"value":@"TARGET VALUE",@"intersects_screen":@YES,@"clickable":@YES}];
    NSDictionary *input=findInput(rows),*selector=@{@"identifier":@"id",@"role":@"button",@"text":@"target",@"index":@999};
    for(unsigned policy=0;policy<3;++policy){
        NSDictionary *before=nil;
        for(bool current:{false,true}){@autoreleasepool{
            selectorReset();selectorClassPolicy=policy;selectorExpected=@[selector[@"identifier"],selector[@"role"],selector[@"text"]];
            const bool identifierFast=fixtureSelectorStableString(selector[@"identifier"])&&fixtureSelectorStableString(@"contains");
            const bool roleFast=fixtureSelectorStableString(selector[@"role"])&&fixtureSelectorStableString(@"exact");
            const bool textFast=fixtureSelectorStableString(selector[@"text"])&&fixtureSelectorStableString(@"contains");
            const NSUInteger expected=current?((identifierFast?1U:1000U)+(roleFast?1U:1000U)+(textFast?1U:2000U)):4000U;
            NSDictionary *value=current?MeasuredAXFindInSnapshot(input,selector):BeforePlanAXFindInSnapshot(input,selector);
            if(current)assert([value isEqual:before]);else before=value;
            if(selectorExpectedFolds!=expected||selectorFolds!=expected+4000U)std::fprintf(stderr,"AX selector folds: policy=%u gates=%d/%d/%d expected=%lu/%lu received=%lu/%lu\n",policy,(int)identifierFast,(int)roleFast,(int)textFast,(unsigned long)expected,(unsigned long)(expected+4000U),(unsigned long)selectorExpectedFolds,(unsigned long)selectorFolds);
            assert(selectorExpectedFolds==expected&&selectorFolds==expected+4000U);
            if(policy==1)assert(identifierFast&&roleFast&&textFast&&expected==(current?3U:4000U));
            if(policy==2)assert(!identifierFast&&!roleFast&&!textFast&&expected==4000U);
            assert([value[@"match_count"] unsignedIntegerValue]==1000&&value[@"element"]==rows[999]);
            if(current)std::printf("AX selector fold path passed: policy=%u gates=%d/%d/%d expected=%lu total=%lu\n",policy,(int)identifierFast,(int)roleFast,(int)textFast,(unsigned long)selectorExpectedFolds,(unsigned long)selectorFolds);
        }}
    }
    for(unsigned n=0;n<128;++n){NSDictionary *expected=nil;
        for(bool current:{false,true}){@autoreleasepool{
            selectorReset();NSMutableString *text=[@"target" mutableCopy];
            NSMutableDictionary *options=[selector mutableCopy];options[@"text"]=text;options[@"index"]=@(n%1000);options[@"match"]=n%2?@"prefix":@"equals";options[@"caseSensitive"]=@((n%3)==0);
            NSDictionary *value=current?MeasuredAXFindInSnapshot(input,options):BeforePlanAXFindInSnapshot(input,options);
            if(current)assert([value isEqual:expected]);else expected=value;
            assert(!MeasuredAXSelectorPlan::StableString(text));
        }}
    }
    // Stable fields are folded only after the candidate is reached. Hidden
    // rows and earlier identifier misses leave text/role plans unprepared.
    for(bool hidden:{false,true}){selectorReset();selectorExpected=@[@"id",@"button",@"target"];
        NSDictionary *row=@{@"identifier":@"miss",@"role":@"BUTTON",@"label":@"TARGET",@"value":@"TARGET",@"intersects_screen":@(!hidden)};
        MeasuredAXFindInSnapshot(findInput(@[row]),selector);assert(selectorFolds==(hidden?0U:2U)&&selectorExpectedFolds==(hidden?0U:1U));
    }
    for(unsigned stage=1;stage<=4;++stage){selectorReset();selectorStopAt=stage;queryCancelled(MeasuredAXFindInSnapshot(input,selector));assert(selectorFolds==stage+(stage%2?1U:0U));}
    for(unsigned kind:{1U,2U}){selectorReset();selectorFaultAt=3;selectorFaultKind=kind;bool caught=false;
        @try{try{MeasuredAXFindInSnapshot(input,selector);}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){caught=kind==1&&[exception.name isEqual:@"AXSelectorFixture"];}
        assert(caught);selectorReset();assert([MeasuredAXFindInSnapshot(input,selector)[@"match_count"] unsignedIntValue]==1000);
    }
    for(unsigned policy:{0U,2U}){
        @autoreleasepool{selectorReset();selectorClassPolicy=policy;NSString *mutableText=[@"target" mutableCopy];
            assert(!fixtureSelectorStableString(mutableText));
            MeasuredAXSelectorPlan::Text plan(mutableText,@"exact",NO);assert(plan.accepts(@"TARGET",MeasuredAXTextMatches));
            [(NSMutableString *)mutableText setString:@"other"];assert(plan.accepts(@"OTHER",MeasuredAXTextMatches));}
        @autoreleasepool{selectorReset();selectorClassPolicy=policy;AXSelectorExpectedProbe *probe=[AXSelectorExpectedProbe new];probe.value=@"target";
            NSString *expected=(NSString *)(id)probe;assert(!MeasuredAXSelectorPlan::StableString(expected)&&!fixtureSelectorStableString(expected));
            MeasuredAXSelectorPlan::Text plan(expected,@"exact",NO);assert(plan.accepts(@"TARGET",MeasuredAXTextMatches));
            probe.value=@"other";assert(plan.accepts(@"OTHER",MeasuredAXTextMatches)&&probe.folds==2);}
    }
    selectorReset();std::puts("AX selector plans passed: actual Foundation eligibility plus controlled fast/compatibility paths, 1000 frozen matches/count/index/row identity; controlled folds 3/4003 vs4000/8000, mutable/custom mutation fallback, lazy rejection, 128 mode/case graphs and cancel/fault recovery. Actual Foundation fast-path availability/device gains pending.");
}
@interface AXSelectorSizeProbe:NSObject
@property(nonatomic) NSUInteger units;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) unsigned byteReads;
@property(nonatomic) BOOL stopOnBytes;
-(NSUInteger)length;
-(NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding;
@end
@implementation AXSelectorSizeProbe
-(BOOL)isKindOfClass:(Class)type{return type==[NSString class]||[super isKindOfClass:type];}
-(NSUInteger)length{return self.units;}
-(NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)encoding{assert(encoding==NSUTF8StringEncoding);++self.byteReads;if(self.stopOnBytes)cancelled=true;return self.bytes;}
@end
static void selectorAdmissionCases(){
    for(NSString *key in @[@"text",@"identifier",@"role",@"match",@"matchMode"]){
        for(unsigned kind=0;kind<3;++kind){@autoreleasepool{
            selectorReset();NSMutableDictionary *request=[@{@"text":@"target"} mutableCopy];
            NSString *unit=kind==0?@"x":(kind==1?@"ả":@"😀");const NSUInteger width=[unit lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSString *large=[@"" stringByPaddingToLength:(65536/width+1)*unit.length withString:unit startingAtIndex:0];request[key]=large;
            NSDictionary *value=TLinkAXFindElement(123,@"fixture.bundle",request);expectError(value,@"ui_response_too_large");
            assert(boundaryDispatches==0&&creates==0&&queries==0&&TLinkAXAdmissionState().pending()==0);
        }}
        for(NSUInteger bytes:{0U,65536U}){@autoreleasepool{
            selectorReset();NSMutableDictionary *request=[@{@"text":@"target"} mutableCopy];
            NSString *value=[@"" stringByPaddingToLength:bytes withString:@"x" startingAtIndex:0];request[key]=value;
            TLinkAXFindElement(123,@"fixture.bundle",request);assert(boundaryDispatches==(bytes==0&&[key isEqual:@"text"]?0U:1U));
        }}
        for(NSString *unit in @[@"ả",@"😀"]){@autoreleasepool{
            const NSUInteger width=[unit lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSMutableString *exact=[[@"" stringByPaddingToLength:(65536/width)*unit.length withString:unit startingAtIndex:0] mutableCopy];
            if(65536%width)[exact appendString:@"x"];
            assert([exact lengthOfBytesUsingEncoding:NSUTF8StringEncoding]==65536);
            selectorReset();NSMutableDictionary *request=[@{@"text":@"target"} mutableCopy];request[key]=[exact copy];
            TLinkAXFindElement(123,@"fixture.bundle",request);assert(boundaryDispatches==1);
            selectorReset();[exact appendString:@"x"];request[key]=exact;
            expectError(TLinkAXFindElement(123,@"fixture.bundle",request),@"ui_response_too_large");assert(boundaryDispatches==0);
        }}
    }
    for(unsigned kind=0;kind<3;++kind){selectorReset();AXSelectorSizeProbe *probe=[AXSelectorSizeProbe new];probe.units=kind==0?65537:1;probe.bytes=kind==1?65537:1;probe.stopOnBytes=kind==2;
        NSDictionary *request=@{@"text":probe};NSDictionary *value=TLinkAXFindElement(123,@"fixture.bundle",request);
        if(kind==2)queryCancelled(value);else expectError(value,@"ui_response_too_large");
        assert(probe.byteReads==(kind==0?0U:1U)&&boundaryDispatches==0&&TLinkAXAdmissionState().pending()==0);
    }
    selectorReset();NSString *large=[@"" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0];
    TLinkAXFindElement(123,@"fixture.bundle",@{@"text":@"target",@"match":@"contains",@"matchMode":large});assert(boundaryDispatches==1);
    selectorReset();cancelled=true;queryCancelled(TLinkAXFindElement(123,@"fixture.bundle",@{@"text":large}));assert(boundaryDispatches==0);
    selectorReset();std::puts("AX selector admission passed: actual pre-queue/public entry, four fields/aliases, ASCII/UTF8/emoji/exact/oversize/empty, UTF16 early refusal, stop and zero denied admission/query work. Whole selector graph/device bounds pending.");
}
static void selectorOwnerCases(){
    for(unsigned n=0;n<128;++n)for(bool current:{false,true}){
        NSDictionary *held=nil;TLinkAXFixtureResetOwners();
        @autoreleasepool{
            selectorReset();trackSelectorOwner=true;
            held=current?TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id"}):BeforePlanAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id"});
            assert([held[@"ok"] boolValue]&&TLinkAXFixtureCreatedOwners()==1);
            nodePoolOwnerCounts(current?0:1,1,1,current?1:0,current?"find operation pool":"preceding caller pool");
            assert(TLinkAXAdmissionState().pending()==0&&rootRetains==rootDrops);
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==1&&[held[@"found"] boolValue]);
    }
    for(bool current:{false,true}){
        TLinkAXFixtureResetOwners();
        @autoreleasepool{selectorReset();trackSelectorOwner=selectorStopOnOwnerDrop=true;
            NSDictionary *value=current?TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id"}):BeforePlanAXFindElement(123,@"fixture.bundle",@{@"identifier":@"id"});
            if(current)queryCancelled(value);else assert([value[@"ok"] boolValue]);assert(TLinkAXAdmissionState().pending()==0);
        }assert(TLinkAXFixtureLiveOwners()==0);
    }
    selectorReset();std::puts("AX find operation pool passed: 128 selected-result lifetimes, explicit MRC acquisition owner retired before return, zero admission charges, drain-time cancellation without replay and frozen caller-pool behavior. Foundation allocation/device gains pending.");
}
