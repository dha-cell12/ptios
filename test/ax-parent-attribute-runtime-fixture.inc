static NSDictionary *parentSerialize(bool current){
    return current?Current::TLinkAXSerializeElement((__bridge CFTypeRef)node,CGRectMake(0,0,320,640),7):
        BeforeParent::TLinkAXSerializeElement((__bridge CFTypeRef)node,CGRectMake(0,0,320,640),7);
}
static void parentAttributeGoldenCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;std::vector<uint32_t> oldKeys;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();parent.reset(new ParentBudget{tick+1000000000ULL});attributeCost=(n%3)*1000000ULL;
                node.traits=@(n%512);node.frame=CGRectMake(n%5==0?500:10,20,40,20);node.point=CGPointMake(n%7==0?-10:30,30);
                node.label=n%2?(id)@123:(id)@"Cài đặt 测试";node.value=n%3?(id)@"value":(id)[NSNull null];
                if(n%11==0)badFrame=true;if(n%13==0)errorKey=2001;if(n%17==0)nilKey=2007;
                NSDictionary *value=parentSerialize(current);
                if(current){
                    assert(equal(value,expected)&&keys==oldKeys);
                    if(value){
                        NSData *oldJSON=[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingSortedKeys error:NULL];
                        NSData *newJSON=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:NULL];
                        assert(oldJSON&&[newJSON isEqual:oldJSON]);
                    }
                }else{expected=value;oldKeys=keys;}
                assert(timeouts.size()==(current?keys.size():1));
                for(double timeout:timeouts)assert(std::fabs(timeout-.1)<1e-6);
            }
            assert(boxes==0&&!lastBox);
        }
    }
}
static void parentAttributeDeadlineCases(){
    for(bool current:{false,true}){
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+100000000ULL});const uint64_t start=tick,end=parent->end;
            attributeCost=60000000ULL;honorAttributeTimeout=true;
            NSDictionary *value=parentSerialize(current);
            assert((value==nil)==current&&keys.size()==2&&parent->end==end);
            assert(tick-start==(current?100000000ULL:120000000ULL));
            assert(timeouts.size()==(current?2U:1U)&&valueDrops==(current?1U:0U));
            if(current)assert(std::fabs(timeouts[0]-.1)<1e-6&&std::fabs(timeouts[1]-.04)<1e-6);
        }
        assert(boxes==0&&!lastBox);
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+100000000ULL});const uint64_t start=tick;
            attributeCost=20000000ULL;setupCost=10000000ULL;
            NSDictionary *value=parentSerialize(current);
            assert((value==nil)==current&&keys.size()==(current?3U:5U));
            assert(tick-start==(current?100000000ULL:110000000ULL));
            assert(timeouts.size()==(current?4U:1U));
        }
        assert(boxes==0&&!lastBox);
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+100000000ULL});attributeCost=60000000ULL;sTLinkAXSetTimeout=nullptr;
            NSDictionary *value=parentSerialize(current);
            assert((value==nil)==current&&keys.size()==2&&timeouts.empty());
        }
        assert(boxes==0&&!lastBox);
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+100000000ULL});decodeCost=100000000ULL;
            NSDictionary *value=parentSerialize(current);assert((value==nil)==current&&keys.size()==1);
        }
        assert(boxes==0&&!lastBox);
    }
    for(unsigned at=1;at<=6;++at){
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();parent.reset(new ParentBudget{tick+1000000000ULL});cancelAt=at;
                NSDictionary *value=parentSerialize(current);assert((value==nil)==current&&keys.size()==at);
            }
            assert(boxes==0&&!lastBox);
        }
    }
    @autoreleasepool{
        reset();parent.reset(new ParentBudget{tick+100000000ULL});cancelSetup=true;
        assert(!parentSerialize(true)&&keys.empty()&&timeouts.size()==1);
    }
}
static void parentAttributeOwnerCases(){
    for(uint32_t key:{2003U,2007U,2001U}){
        @autoreleasepool{
            reset();parent.reset(new ParentBudget{tick+20000000ULL});attributeCost=20000000ULL;int error=-1;
            id value=Current::TLinkAXAttribute((__bridge CFTypeRef)node,key,&error);
            assert(!value&&error==0&&valueDrops==1&&keys.size()==1);
        }
        assert(boxes==0&&!lastBox);
    }
    for(unsigned kind:{1U,2U}){
        for(uint32_t key:{2003U,2007U}){
            @autoreleasepool{
                reset();parent.reset(new ParentBudget{tick+1000000000ULL});throwKey=key;throwKind=kind;bool caught=false;
                @try{try{Current::TLinkAXAttribute((__bridge CFTypeRef)node,key,NULL);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXAttributeFixture"];}
                assert(caught&&valueDrops==1&&keys.size()==1);
            }
            assert(boxes==0&&!lastBox);
        }
    }
    @autoreleasepool{
        reset();parent.reset(new ParentBudget{tick+20000000ULL});attributeCost=60000000ULL;honorAttributeTimeout=true;
        hitErrorCode(hitCall(true),@"ui_cancelled_or_timed_out");assert(keys.size()==1&&valueDrops==1);hitOwnersRetired();
    }
    assert(boxes==0&&!lastBox);
}
static void parentAttributeCases(){
    std::puts("AX parent attributes: complete current/C05j serializer and attribute helpers, actual hit-test, real CF owners and controlled cooperative timeout provider");
    parentAttributeGoldenCases();parentAttributeDeadlineCases();parentAttributeOwnerCases();
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{reset();parent.reset(new ParentBudget{tick+1000000000ULL});assert(parentSerialize(true));}
        assert(boxes==0&&!lastBox);
    }
    parent.reset();node=nil;rootObject=nil;
    std::puts("AX parent attributes passed: 128 frozen graph/JSON/field cases, fresh per-query remainder, controlled 100ms versus120ms overrun, setup admission, missing setter/late decoder, six cancellation positions, errorOut/NS/C++ CF cleanup, actual hit-test refusal and 128 pool lifecycles. Opaque AX/device timing remains unqualified.");
}
