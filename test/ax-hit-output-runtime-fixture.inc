static NSDictionary *hitOutputCall(bool current){
    return current?TLinkAXElementAtPoint(123,@"fixture.bundle",CGPointMake(30,30)):
        BeforeOutputAXElementAtPoint(123,@"fixture.bundle",CGPointMake(30,30));
}
static NSData *hitOutputJSON(NSDictionary *value){
    NSError *error=nil;NSData *bytes=[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys error:&error];
    assert(bytes&&!error);return bytes;
}
static NSString *hitOutputRepeated(NSString *unit,NSUInteger count){
    return [@"" stringByPaddingToLength:unit.length*count withString:unit startingAtIndex:0];
}
static void hitOutputGoldenCases(){
    for(unsigned n=0;n<128;++n){
        NSDictionary *expected=nil;unsigned oldCreates=0,oldCalls=0;std::vector<uint32_t> oldKeys;
        for(bool current:{false,true}){
            @autoreleasepool{
                reset();observeHitOutput=true;
                node.label=n%3?(id)[NSString stringWithFormat:@"hit-%u-Ứng dụng 测试",n]:(id)@42;
                node.value=n%5?(id)@"value":nil;node.identifier=n%7?(id)@"identifier":(id)[NSNull null];node.traits=@(n%512);
                if(n%11==0)badFrame=true;if(n%13==0)hitError=true;if(n%17==0)hitMissing=true;
                if(n%19==0)hitRootMissing=true;if(n%23==0)hitPrepared=false;if(n%29==0)hitLocked=true;
                NSDictionary *value=hitOutputCall(current);
                if(current){
                    assert([value isEqual:expected]&&[hitOutputJSON(value) isEqualToData:hitOutputJSON(expected)]);
                    assert(hitCreates==oldCreates&&hitCalls==oldCalls&&keys==oldKeys);
                }else{expected=value;oldCreates=hitCreates;oldCalls=hitCalls;oldKeys=keys;}
                assert(hitOutputCalls==(current&&[value[@"ok"] boolValue]?5U:0U));hitOwnersRetired();
            }
            assert(boxes==0&&!lastBox);
        }
    }
}
static void hitOutputTextCases(){
    const unichar nul=0;NSString *nulText=[NSString stringWithCharacters:&nul length:1];
    NSArray *texts=@[@"",hitOutputRepeated(@"a",65536),hitOutputRepeated(@"a",65537),
        hitOutputRepeated(@"测",21845),hitOutputRepeated(@"测",21846),
        hitOutputRepeated(@"😀",16384),hitOutputRepeated(@"😀",16385),
        hitOutputRepeated(nulText,65536),hitOutputRepeated(@"\"",65536),hitOutputRepeated(@"\\",65536)];
    for(unsigned field=0;field<3;++field){
        for(NSString *text in texts){
            NSDictionary *expected=nil;const bool oversize=[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>65536;
            for(bool current:{false,true}){
                @autoreleasepool{
                    reset();observeHitOutput=true;
                    if(field==0)node.label=text;if(field==1)node.value=text;if(field==2)node.identifier=text;
                    NSDictionary *value=hitOutputCall(current);
                    if(current&&oversize){
                        hitErrorCode(value,@"ui_response_too_large");
                        assert([value[@"partial"] boolValue]&&[value[@"pid"] intValue]==123&&!TLinkAXResultCompleteForAction(value));
                    }else{
                        assert([value[@"ok"] boolValue]&&[value[@"found"] boolValue]);
                        if(current)assert([value isEqual:expected]&&[hitOutputJSON(value) isEqualToData:hitOutputJSON(expected)]);
                        else expected=value;
                    }
                    // Large UTF16 text is refused before its byte-admission call.
                    if(current&&text.length>65536)assert(hitOutputCalls==field);
                    hitOwnersRetired();assert(keys.size()==6);
                }
                assert(boxes==0&&!lastBox);
            }
        }
    }
}
static void hitOutputBudgetCases(){
    NSDictionary *baseline=nil;
    @autoreleasepool{reset();baseline=hitOutputCall(false);hitOwnersRetired();}
    size_t row=768,json=0,wire=0;
    for(NSString *key in @[@"label",@"value",@"identifier",@"role"])
        assert(TLinkAXSnapshotOutput::AddString([baseline[@"element"][key] lengthOfBytesUsingEncoding:NSUTF8StringEncoding],row));
    assert(TLinkAXSnapshotOutput::AppendRow(row,0,json,wire));
    for(bool current:{false,true}){
        for(unsigned kind=0;kind<5;++kind){
            @autoreleasepool{
                reset();observeHitOutput=latchHitOutputOverflow=true;
                hitOutputCap=kind==0?1:(kind==1?wire-1:(kind==2?wire:(kind==3?0:1024*1024)));
                NSDictionary *value=hitOutputCall(current);
                if(current&&kind<2){
                    hitErrorCode(value,@"ui_cancelled_or_timed_out");assert(hitOutputOverflowed);
                }
                else assert([value isEqual:baseline]);
                hitOwnersRetired();
            }
            assert(boxes==0&&!lastBox);
        }
    }
    @autoreleasepool{
        reset();observeHitOutput=latchHitOutputOverflow=true;badFrame=true;hitOutputCap=32768;
        hitErrorCode(hitOutputCall(true),@"ui_cancelled_or_timed_out");assert(hitOutputOverflowed);hitOwnersRetired();
    }
    assert(boxes==0&&!lastBox);
    for(unsigned kind:{1U,2U}){
        @autoreleasepool{
            reset();observeHitOutput=true;hitOutputFaultKind=kind;bool caught=false;
            try{NSDictionary *value=hitOutputCall(true);hitErrorCode(value,@"ui_ax_exception");caught=kind==1;}
            catch(const std::runtime_error &){caught=kind==2;}
            assert(caught&&hitOutputCalls==1&&TLinkAXAdmissionState().pending()==0);hitOwnersRetired();
        }
        assert(boxes==0&&!lastBox);
    }
    for(bool deadline:{false,true}){
        @autoreleasepool{
            reset();observeHitOutput=true;
            if(deadline){parent.reset(new ParentBudget{tick+20000000ULL});hitOutputCost=20000000ULL;}
            else stopDuringHitOutput=true;
            hitErrorCode(hitOutputCall(true),@"ui_cancelled_or_timed_out");assert(hitOutputCalls>0);hitOwnersRetired();
        }
        assert(boxes==0&&!lastBox);
    }
}
static void hitOutputCases(){
    std::puts("AX hit output: complete current/C05q hit helper and actual serializer/attributes with real CF, Unicode and JSON");
    hitOutputGoldenCases();hitOutputTextCases();hitOutputBudgetCases();
    NSDictionary *held=nil;
    @autoreleasepool{reset();node.label=hitOutputRepeated(@"测",21845);held=hitOutputCall(true);hitOwnersRetired();node=nil;}
    assert([held[@"element"][@"label"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding]==65535);held=nil;
    for(unsigned n=0;n<128;++n){
        @autoreleasepool{
            reset();observeHitOutput=true;node.label=hitOutputRepeated(@"😀",16385);
            hitErrorCode(hitOutputCall(true),@"ui_response_too_large");hitOwnersRetired();
        }
        assert(boxes==0&&!lastBox);
        @autoreleasepool{reset();assert([hitOutputCall(true)[@"found"] boolValue]);hitOwnersRetired();}
        assert(boxes==0&&!lastBox);
    }
    reset();
    std::puts("AX hit output passed: 128 frozen graphs/JSON/work counts, exact three-field ASCII/Unicode/NUL/escape limits, UTF16 early admission, exact caller wire cap, unlimited/one-byte budgets, sticky overflow/stop translation, nil element, pre-output CF retirement, output NS/C++ unwind, late caller stop and 128 balanced refusal/recovery lifecycles. Provider/metadata/final wire/device bounds remain pending.");
}
