static NSUInteger findFlagReads=0,findCancelAt=0,findThrowAt=0;
static unsigned findThrowKind=0;
@interface TLinkFixtureFindFlag:NSObject
-(BOOL)boolValue;
@end
@implementation TLinkFixtureFindFlag
-(BOOL)boolValue {
    ++findFlagReads;
    if(findFlagReads==findCancelAt)cancelled=true;
    if(findFlagReads==findThrowAt){
        if(findThrowKind==1)[NSException raise:@"AXFindFixture" format:@"later row"];
        if(findThrowKind==2)throw std::runtime_error("later row");
    }
    return YES;
}
@end
static void resetFind(){cancelled=false;matchedArrayAppends=findFlagReads=findCancelAt=findThrowAt=0;findThrowKind=0;}
static NSDictionary *findInput(NSArray *rows,BOOL incomplete=NO){
    return @{@"ok":@YES,@"schema":TLinkAXSnapshotSchema,@"source":TLinkAXBackendName,@"elements":rows,
        @"count":@(rows.count),@"scanned_count":@(rows.count),@"source_count":@(rows.count+(incomplete?1:0)),
        @"serialization_failure_count":@0,@"partial":@(incomplete),@"truncated":@(incomplete),@"context_changed":@NO,
        @"pid":@123,@"bundle_id":@"fixture.bundle",@"fixture_metadata":@{@"retained":@YES}};
}
static NSData *findJSON(NSDictionary *value){
    NSError *error=nil;NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:&error];
    assert(bytes&&!error);return bytes;
}
static NSDictionary *compareFind(NSDictionary *input,NSDictionary *selector){
    resetFind();NSDictionary *expected=LegacyAXFindInSnapshot(input,selector);NSUInteger appends=matchedArrayAppends;
    resetFind();NSDictionary *actual=TLinkAXFindInSnapshot(input,selector);
    assert((actual==expected||[actual isEqual:expected])&&matchedArrayAppends==0);
    assert(TLinkAXResultCompleteForAction(actual)==TLinkAXResultCompleteForAction(expected));
    if([expected isKindOfClass:[NSDictionary class]]){
        assert([findJSON(actual) isEqualToData:findJSON(expected)]);
        assert(appends==[expected[@"match_count"] unsignedIntegerValue]);
        if([expected[@"found"] boolValue])assert(actual[@"element"]==expected[@"element"]);
    }
    return actual;
}
static void findGoldenCases(){
    NSArray *words=@[@"Login",@"login.primary",@"LOGOUT",@"",@"Cài đặt",@"测试"];
    NSArray *roles=@[@"button",@"text",@"link",@"element"];
    NSArray *modes=@[@"contains",@"exact",@"prefix",@"equals",@"unknown",@42,[NSNull null]];
    NSArray *indices=@[@0,@1,@2,@999,@1000,@(-3),@2.9,@"3",[NSNull null]];
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        NSMutableArray *rows=[NSMutableArray array];
        for(unsigned j=0;j<n%41;++j){
            [rows addObject:@{@"index":@(j),@"label":words[j%words.count],@"value":words[(j+2)%words.count],
                @"identifier":[NSString stringWithFormat:@"id-%u",j%4],@"role":roles[j%roles.count],
                @"intersects_screen":@(j%3!=0),@"clickable":@(j%2==0),
                @"frame":@{@"x":@(j),@"y":@2,@"width":@10,@"height":@20},
                @"activation_point":@{@"x":@(j+5),@"y":@12}}];
        }
        NSMutableDictionary *selector=[NSMutableDictionary dictionary];
        switch(n%6){
            case 0:break;
            case 1:selector[@"text"]=words[(n/3)%words.count];break;
            case 2:selector[@"identifier"]=[NSString stringWithFormat:@"id-%u",n%4];break;
            case 3:selector[@"role"]=roles[(n/5)%roles.count];break;
            case 4:selector[@"text"]=@"login";selector[@"role"]=@"button";break;
            case 5:selector[@"text"]=@"LOGIN";selector[@"identifier"]=@"id-1";break;
        }
        selector[n%2?@"match":@"matchMode"]=modes[(n/2)%modes.count];
        if(n%7==0)selector[@"match"]=@"equals";
        selector[n%2?@"case_sensitive":@"caseSensitive"]=@((n/2)%2!=0);
        if(n%3!=0)selector[@"visibleOnly"]=@(n%2!=0);
        if(n%5==0)selector[@"visible_only"]=@NO;
        selector[n%2?@"clickable_only":@"clickableOnly"]=@(n%3==0);
        selector[@"index"]=indices[(n/7)%indices.count];
        NSDictionary *input=findInput(rows,n%11==0);compareFind(input,selector);
    }}
    compareFind(nil,nil);
    NSDictionary *error=TLinkAXError(@"fixture_error",@{@"partial":@YES});
    assert(compareFind(error,@{})==error);
}
static void findCountCases(){
    NSMutableArray *rows=[NSMutableArray array];
    for(unsigned n=0;n<1000;++n)[rows addObject:@{@"index":@(n),@"identifier":@"target",@"intersects_screen":@YES}];
    NSDictionary *input=findInput(rows);
    NSArray *plans=@[@[@0,@0],@[@1,@1],@[@999,@999],@[@1000,@999],@[@(-3),@0]];
    for(NSArray *plan in plans){
        NSDictionary *selector=@{@"identifier":@"target",@"index":plan[0]};
        NSDictionary *value=compareFind(input,selector);
        assert([value[@"match_count"] unsignedIntegerValue]==1000&&[value[@"found"] boolValue]);
        assert([value[@"element"][@"index"] unsignedIntegerValue]==[plan[1] unsignedIntegerValue]);
        assert(TLinkAXResultCompleteForAction(value));
    }
    std::puts("AX find fixture: 1000 legacy match-array appends versus zero current appends; full match count/index and selected-row identity preserved.");
}
static void findCancellationAndFaultCases(){
    TLinkFixtureFindFlag *flag=[TLinkFixtureFindFlag new];NSMutableArray *rows=[NSMutableArray array];
    for(unsigned n=0;n<5;++n)[rows addObject:@{@"index":@(n),@"intersects_screen":flag,@"identifier":@"target"}];
    NSDictionary *input=findInput(rows),*selector=@{@"identifier":@"target",@"index":@0};
    for(bool current:{false,true}){
        @autoreleasepool{
            resetFind();findCancelAt=2;
            NSDictionary *value=current?TLinkAXFindInSnapshot(input,selector):LegacyAXFindInSnapshot(input,selector);
            expectError(value,@"ui_cancelled_or_timed_out");assert(findFlagReads==2&&!TLinkAXResultCompleteForAction(value));
        }
    }
    for(unsigned kind:{1U,2U}){
        for(bool current:{false,true}){
            @autoreleasepool{
                resetFind();findThrowAt=4;findThrowKind=kind;bool caught=false;
                @try{try{
                    if(current)TLinkAXFindInSnapshot(input,selector);else LegacyAXFindInSnapshot(input,selector);
                }catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXFindFixture"];}
                assert(caught&&findFlagReads==4);
            }
        }
    }
    resetFind();NSDictionary *value=TLinkAXFindInSnapshot(input,selector);
    assert(findFlagReads==5&&[value[@"match_count"] unsignedIntegerValue]==5&&matchedArrayAppends==0);
}
static void findResultLifetime(){
    NSDictionary *held;__weak NSDictionary *selected;
    @autoreleasepool{
        resetFind();NSMutableDictionary *row=[@{@"identifier":@"retained",@"intersects_screen":@YES} mutableCopy];selected=row;
        held=TLinkAXFindInSnapshot(findInput(@[row]),@{@"identifier":@"retained"});
    }
    assert(selected&&held[@"element"]==selected&&[held[@"element"][@"identifier"] isEqualToString:@"retained"]);
    held=nil;
}
static void findCases(){
    findGoldenCases();findCountCases();findCancellationAndFaultCases();findResultLifetime();resetFind();
    std::puts("AX find passed: 1000 frozen complete graph/sorted-JSON comparisons, normalization/filter/order/index/partial parity, 1000 matches without array growth, later-row cancel/NS/C++ failure and selected-row pool lifetime. Root/selector fusion/device qualification pending.");
}
