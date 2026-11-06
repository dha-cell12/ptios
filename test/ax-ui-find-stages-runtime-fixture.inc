// A method seam for selector reads, avoiding Foundation class-cluster init.
@interface UIStageOptions:NSObject
@property(nonatomic,strong) NSDictionary *backing;
@end
@implementation UIStageOptions
-(BOOL)isKindOfClass:(Class)type{return type==[NSDictionary class]||[super isKindOfClass:type];}
-(NSUInteger)count{return self.backing.count;}
-(NSEnumerator *)keyEnumerator{return self.backing.keyEnumerator;}
-(id)objectForKey:(id)key{if([key isEqual:@"timeout_ms"])cancelled=true;return self.backing[key];}
-(id)objectForKeyedSubscript:(id)key{return [self objectForKey:key];}
@end
static void findStageCases(){
    std::puts("AX matcher/enqueue stages: complete actual/C05aa shared formatter/find wrappers");
    for(unsigned stage=1;stage<=4;++stage)for(bool current:{false,true}){@autoreleasepool{
        findPoolReset();poolCancelAt=stage;
        TLinkFixturePoolText *text=[TLinkFixturePoolText new];text.text=@"target";
        NSDictionary *input=findInput(@[@{@"identifier":text,@"role":text,@"label":text,@"value":text,@"intersects_screen":@YES,@"clickable":@YES}]);
        NSDictionary *selector=@{@"identifier":@"target",@"role":@"target",@"text":@"target"};
        NSDictionary *value=current?TLinkAXFindInSnapshot(input,selector):BeforeStagesAXFindInSnapshot(input,selector);
        queryCancelled(value);assert(poolNormalizations==(current?stage:4U)&&TLinkAXFixtureLiveOwners()==0);
    }}
    for(bool current:{false,true}){@autoreleasepool{
        queryBoundaryReset();UIStageOptions *selector=[UIStageOptions new];selector.backing=@{@"text":@"target",@"timeout_ms":@1500};
        NSDictionary *value=current?TLinkAXFindElement(123,@"fixture.bundle",(NSDictionary *)(id)selector):BeforeStagesAXFindElement(123,@"fixture.bundle",(NSDictionary *)(id)selector);
        queryCancelled(value);assert(boundaryDispatches==(current?0U:1U)&&creates==0&&queries==0);
        assert(TLinkAXAdmissionState().pending()==0);
    }}
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){@autoreleasepool{
            queryBoundaryReset();NSMutableArray *rows=[NSMutableArray array];
            for(unsigned i=0;i<n%17;++i)[rows addObject:@{@"identifier":@"target",@"role":@"element",@"label":@"TARGET",@"value":@"target value",@"intersects_screen":@(i%2==0),@"clickable":@(i%3==0)}];
            NSDictionary *selector=@{@"text":@"target",@"identifier":@"target",@"index":@(n%4),@"visible_only":@((n&1)!=0)};
            NSDictionary *input=findInput(rows,n%3==0);
            NSDictionary *value=current?TLinkAXFindInSnapshot(input,selector):BeforeStagesAXFindInSnapshot(input,selector);
            if(current)assert([value isEqual:expected]&&[findJSON(value) isEqualToData:findJSON(expected)]);else expected=value;
        }}
    }
    queryBoundaryReset();
    std::puts("AX matcher/enqueue stages passed: four normalization cancellation boundaries skip downstream work, zero enqueue after option-time stop, balanced admission and 128 full frozen graph/JSON cases. Actual string/device performance pending.");
}
