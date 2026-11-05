static unsigned poolNormalizations=0,poolCancelAt=0,poolThrowAt=0,poolThrowKind=0;
// A controlled string-like candidate, not a Foundation subclass. Only its
// normalization method creates explicit pending MRC owners; real returned
// strings still use Foundation lowercase/matching. These mock rows are not
// wire/JSON fixtures; the existing ordinary-string golden cases cover that.
@interface TLinkFixturePoolText:NSObject
@property(nonatomic,copy) NSString *text;
-(NSString *)lowercaseString;
@end
@implementation TLinkFixturePoolText
-(NSString *)lowercaseString {
    ++poolNormalizations;TLinkAXFixtureAutoreleaseOwner();
    if(poolNormalizations==poolCancelAt)cancelled=true;
    if(poolNormalizations==poolThrowAt){
        if(poolThrowKind==1)[NSException raise:@"AXFindPoolFixture" format:@"normalize"];
        if(poolThrowKind==2)throw std::runtime_error("normalize");
    }
    return [self.text lowercaseString];
}
@end
static void findPoolReset(){
    reset();resetFind();TLinkAXFixtureResetOwners();poolNormalizations=poolCancelAt=poolThrowAt=poolThrowKind=0;
}
static NSArray *findPoolRows(unsigned count,BOOL misses=NO){
    TLinkFixturePoolText *label=[TLinkFixturePoolText new],*value=[TLinkFixturePoolText new],*identifier=[TLinkFixturePoolText new];
    label.text=@"TARGET";value.text=@"target value";identifier.text=misses?@"missing":@"target";
    NSMutableArray *rows=[NSMutableArray array];
    for(unsigned n=0;n<count;++n)[rows addObject:@{@"index":@(n),@"intersects_screen":@YES,@"label":label,@"value":value,@"identifier":identifier}];
    return rows;
}
static NSDictionary *findPoolCall(bool current,NSDictionary *input,NSDictionary *selector){
    return current?TLinkAXFindInSnapshot(input,selector):BeforePoolAXFindInSnapshot(input,selector);
}
static void findPoolOwnerCases(){
    for(bool misses:{false,true}){
        for(unsigned index:{0U,999U}){
            NSArray *rows=findPoolRows(1000,misses);NSDictionary *input=findInput(rows);
            NSDictionary *expected=nil;
            for(bool current:{false,true}){
                @autoreleasepool{
                    findPoolReset();
                    NSDictionary *selector=misses?@{@"identifier":@"target"}:@{@"text":@"target",@"index":@(index)};
                    NSDictionary *value=findPoolCall(current,input,selector);
                    if(current)assert([value isEqual:expected]);else expected=value;
                    const unsigned calls=misses?1000U:2000U;
                    assert(poolNormalizations==calls&&TLinkAXFixtureCreatedOwners()==calls);
                    nodePoolOwnerCounts(current?0:calls,current?(misses?1:2):calls,calls,current?calls:0,current?"current find":"preceding find");
                    assert([value[@"match_count"] unsignedIntValue]==(misses?0U:1000U));
                    if(!misses)assert(value[@"element"]==rows[index]);
                }
                assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==TLinkAXFixtureDroppedOwners());
            }
        }
    }
}
static void findPoolCancelAndFaultCases(){
    for(bool current:{false,true}){
        NSDictionary *held=nil;
        @autoreleasepool{
            findPoolReset();poolCancelAt=20;
            held=findPoolCall(current,findInput(findPoolRows(10)),@{@"text":@"target"});
            queryCancelled(held);assert(poolNormalizations==20);
            assert(TLinkAXFixtureLiveOwners()==(current?0U:20U));
        }
        queryCancelled(held);held=nil;assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==20);
        for(unsigned kind:{1U,2U}){
            @autoreleasepool{
                findPoolReset();poolThrowAt=3;poolThrowKind=kind;bool caught=false;
                @try{try{findPoolCall(current,findInput(findPoolRows(10)),@{@"text":@"target"});}
                    catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXFindPoolFixture"];}
                assert(caught&&poolNormalizations==3);
            }
            // Exception exit does not drain a pool. Only this normal outer
            // boundary is a valid final-deallocation observation point.
            assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureCreatedOwners()==3&&TLinkAXFixtureDroppedOwners()==3);
        }
    }
}
static void findPoolSelectedLifetime(){
    for(bool current:{false,true}){
        NSDictionary *held=nil;__weak NSDictionary *selected;
        @autoreleasepool{
            findPoolReset();NSArray *rows=findPoolRows(2);selected=rows[1];
            held=findPoolCall(current,findInput(rows),@{@"text":@"target",@"index":@1});
        }
        @autoreleasepool{
            assert(selected&&held[@"element"]==selected&&TLinkAXFixtureLiveOwners()==0);
            TLinkFixturePoolText *label=held[@"element"][@"label"];
            assert([label.text isEqualToString:@"TARGET"]);held=nil;
        }
        assert(!selected&&TLinkAXFixtureLiveOwners()==0);
    }
}
static void findPoolCases(){
    std::puts("AX find pools: complete current/C05n matcher, controlled candidates/normalizations and explicit pending MRC owners");
    findPoolOwnerCases();findPoolCancelAndFaultCases();findPoolSelectedLifetime();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            findPoolReset();NSDictionary *value=findPoolCall(true,findInput(findPoolRows(16)),@{@"text":@"target"});
            assert([value[@"match_count"] unsignedIntValue]==16&&poolNormalizations==32&&TLinkAXFixtureLiveOwners()==0);
        }
        assert(TLinkAXFixtureCreatedOwners()==TLinkAXFixtureDroppedOwners());
    }
    reset();resetFind();
    std::puts("AX find pools passed: 1000 rows/full count/index, peak 2 versus2000 normalization owners and 1 versus1000 on rejection, selected-row/input-pool lifetime, final cancellation, NS/C++ outer drain and 128 balanced lifecycles. Actual string allocations/RSS/device gains remain unqualified.");
}
