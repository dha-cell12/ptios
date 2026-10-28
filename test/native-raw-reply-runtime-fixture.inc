// Actual bounded dispatch/sink/decoder versus the frozen NSData decoder.
// Task effects are controlled; real CF stream creation and ARC ownership run.
static void rawReplyCases(TLinkInProcessNativeBridge *bridge){
    puts("RAW reply Foundation: direct owned UTF8 string versus frozen NSData decode/dispatch/rollback");fflush(stdout);
    mode=@"rawReplyRuntime";
    const auto reset=[](TLinkTaskExecutionContext *context,const std::vector<std::string> &chunks,unsigned scenario){
        rawReplyChunks=chunks;rawReplyPayloads.clear();rawReplyScenario=scenario;
        if(scenario==3)[context.cancellationToken cancel];
        if(scenario==4)[context setNativeBudget:std::make_shared<TLinkNativeBudget>(nullptr,1,4096)];
    };
    const auto parity=[bridge,reset](const std::vector<std::string> &chunks,NSUInteger cap=4096,unsigned scenario=0,NSString *payload=@"18")->NSDictionary *{
        auto context=parent(30,cap);reset(context,chunks,scenario);int before=calls,releaseBefore=releases;
        NSDictionary *expected=[bridge legacyRawPayload:payload context:context];const auto payloads=rawReplyPayloads;
        const int delta=calls-before,releaseDelta=releases-releaseBefore;
        context=parent(30,cap);reset(context,chunks,scenario);before=calls;releaseBefore=releases;
        NSDictionary *actual=[bridge executeRawPayload:payload context:context];
        const bool same=[actual isEqual:expected];
        if(!same){fprintf(stdout,"RAW reply parity failure: %s\n",[NSString stringWithFormat:@"payload=%@ cap=%lu scenario=%u expected=%@ actual=%@",payload,(unsigned long)cap,scenario,expected,actual].UTF8String);fflush(stdout);}assert(same);
        assert(calls==before+delta&&releases==releaseBefore+releaseDelta&&rawReplyPayloads==payloads&&!TLinkCurrentNativeBudget());
        return actual;
    };
    for(unsigned n=0;n<160;++n){
        const std::string body="0;;entry "+std::to_string(n)+";;"+std::string(n%73,'x')+"\r\n";
        const size_t at=n%body.size();parity({body.substr(0,at),body.substr(at)});
    }
    for(NSString *text in @[@"",@"0",@"0\r\n",@"1;;error\r\n",@"-1;;failure\r\n",@"00;;data",@" 0;;data",@"0;;",@"0;;;;",@";;",@"0;;x;;y;;",@"\n0;;x\r\n",@"0;;x\ninner\rline;;z\n",@"0;;ảnh;测试 😀 e\u0301",[NSString stringWithFormat:@"0;;%C%C%C",(unichar)0x2028,(unichar)0x2029,(unichar)0x85]]){
        const std::string wire=text.UTF8String;
        for(size_t at=0;at<=wire.size();++at)parity({wire.substr(0,at),wire.substr(at)});
        parity({wire},wire.size());if(!wire.empty())parity({wire},wire.size()-1);
    }
    // Split multibyte scalars, BOM/noncharacters, overlong/truncated/illegal
    // sequences and UTF16 BOM bytes are admitted by the same byte sink first.
    const std::vector<std::string> encodings={std::string("\xef\xbb\xbf")+"0;;data",std::string("0;;")+"\xef\xbf\xbe",std::string("0;;")+"\xf0\x9f\x98\x80",
        "\xff","\x80","\xc0\xaf","\xe0\x80\xaf","\xed\xa0\x80","\xf4\x90\x80\x80","\xf5\x80\x80\x80","\xc2","\xe2\x82","\xf0\x9f\x98","\xff\xfe"};
    for(const auto &wire:encodings){for(size_t at=0;at<=wire.size();++at)parity({wire.substr(0,at),wire.substr(at)});parity({wire},4096,1);}
    parity({});parity({"",""});
    parity({std::string("0;;a\0ignored",12),";;tail\r\n"});parity({std::string("\0ignored",8),"0;;tail\r\n"});
    for(unsigned scenario=0;scenario<=4;++scenario){parity({"0;;value\r\n"},4096,scenario);parity({},4096,scenario);parity({"\xff"},4096,scenario);}
    for(NSUInteger cap:{NSUInteger(1),NSUInteger(2),NSUInteger(3),NSUInteger(8),NSUInteger(9)}){
        parity({"0;;value\r\n"},cap);parity({"0;;","value\r\n"},cap);parity({"0;;","value\r\n"},cap,1);
    }
    const size_t limit=1024*1024;const std::string large="0;;"+std::string(limit-3,'x');
    parity({large},limit);parity({large},limit-1);parity({large+"x"},limit);parity({large.substr(0,limit/2),large.substr(limit/2)},limit);
    // The decoder still precedes stop conversion and allocation rollback. A
    // valid partial response can carry an owned ID even after output overflow.
    for(NSString *payload in @[@"66",@"481;;0;;0;;5;;5",@"482;;/fixture.png"]){
        for(const auto &reply:std::vector<std::string>{"0;;41\r\n","0;;41junk\r\n","0;;0\r\n","0;;-1\r\n","1;;41\r\n","00;;41\r\n","0;;;;41\r\n",std::string("0;;41")+"\xff"})parity({reply},4096,1,payload);
        parity({"0;;41",std::string(1024,'x')},1024,0,payload);
        parity({"0;;41\r\n"},4096,2,payload);parity({"0;;41\r\n"},1023,0,payload);
    }
    for(NSString *payload in @[@"6741;;session;;run;;test",@"483;;41;;session;;run;;test"]){parity({},4096,3,payload);parity({},4096,4,payload);}
    NSString *nulPayload=[NSString stringWithFormat:@"18%Ctail",(unichar)0];
    for(NSString *payload in @[@"",@"1",[@"18" stringByPaddingToLength:8193 withString:@"x" startingAtIndex:0],nulPayload]){parity({"0\r\n"},4096,0,payload);}
    // The response owns its bytes after both the request vector and caller
    // pool retire; later buffers and a failed decode cannot alter held data.
    NSDictionary *held=nil;@autoreleasepool{held=parity({large},limit);observed=nil;}
    for(unsigned n=0;n<128;++n)parity({"0;;replacement\r\n"});parity({"\xff"});
    assert([held[@"ok"] boolValue]&&[held[@"raw"] length]==limit&&[held[@"parts"][1] length]==limit-3);
    rawReplyChunks.clear();rawReplyChunks.shrink_to_fit();rawReplyPayloads.clear();rawReplyPayloads.shrink_to_fit();rawReplyScenario=0;mode=@"echo";
    puts("RAW reply passed: frozen full-dispatch parity, chunked Unicode/BOM/malformed UTF8, empty ACK/NUL/newline/parts, exact 1-MiB output, stop/encoding/overflow precedence, creation rollback and cleanup, immutable cross-pool ownership and 128 replacement lifecycles. No intermediate response NSData or borrowed string storage.");
}
