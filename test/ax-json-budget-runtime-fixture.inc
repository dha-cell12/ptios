static NSOutputStream *heldBudgetStream;
static std::weak_ptr<TLinkNativeBudget> budgetWriterOwner;
static unsigned budgetWriterMode=0,budgetWriterCalls=0;
static NSInteger jsonBudgetWriter(id object,NSOutputStream *stream,NSError *__autoreleasing *error){
    heldBudgetStream=stream;++budgetWriterCalls;
    if(budgetWriterMode==5)return TLinkAXWriteJSON(object,stream,error);
    const uint8_t body[]={'{','"','a','"',':','1','}'};
    if(budgetWriterMode==1){
        if([stream write:body maxLength:3]!=3)return 0;
        return [stream write:body+3 maxLength:4]==4?7:0;
    }
    if(budgetWriterMode==3||budgetWriterMode==4){
        auto other=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,budgetWriterMode==3?1:1024*1024);
        TLinkNativeBudgetScope nested(other);const NSInteger written=[stream write:body maxLength:7];
        assert(other->reason()==TLinkNativeStop::None);return written;
    }
    const NSInteger written=[stream write:body maxLength:7];
    if(budgetWriterMode==2){auto owner=budgetWriterOwner.lock();assert(owner&&owner->appendCString((const uint8_t *)"more")==4);}
    return written;
}
static NSUInteger budgetBufferLength(bool current){
    return current?((TLinkAXJSONStream *)heldBudgetStream).byteCount:
        ((BeforeOutputTLinkAXJSONStream *)heldBudgetStream).bytes.length;
}
static NSData *budgetWriterCall(bool current,id graph,BOOL *large,BOOL *stopped){
    return current?TLinkAXJSONDataWithWriter(graph,large,jsonBudgetWriter,stopped):
        BeforeOutputTLinkAXJSONDataWithWriter(graph,large,jsonBudgetWriter,stopped);
}
static void jsonBudgetWriterCases(){
    for(bool current:{false,true})for(unsigned kind=0;kind<9;++kind){
        std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            heldBudgetStream=nil;budgetWriterCalls=0;budgetWriterMode=0;
            const size_t cap=kind==0?1:(kind==1?16:(kind==2?17:(kind==3?0:(kind==4?13:(kind==5?20:(kind==6?17:16))))));
            const size_t prefix=kind==8?3:0;
            auto owner=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,cap,false,true);
            if(prefix)assert(owner->appendCString((const uint8_t *)"old")==3);
            auto child=std::make_shared<TLinkNativeBudget>(0,owner);weak=child;budgetWriterOwner=owner;
            if(kind==4)budgetWriterMode=1;
            if(kind==5)budgetWriterMode=2;
            if(kind==6)budgetWriterMode=3;
            if(kind==7)budgetWriterMode=4;
            TLinkNativeBudgetScope scope(child);BOOL large=YES,stopped=YES;
            NSData *data=budgetWriterCall(current,@{},&large,&stopped);
            const bool reject=kind==0||kind==1||kind==4||kind==5||kind==7||kind==8;
            if(current&&reject){
                assert(!data&&large&&!stopped&&owner->reason()==TLinkNativeStop::OutputLimit);
                assert(budgetWriterCalls==(kind==0?0U:1U));
                if(kind==0)assert(!heldBudgetStream);
                else{
                    assert(budgetBufferLength(true)==(kind==4?3U:(kind==5?7U:0U)));
                    if(kind!=5)assert(heldBudgetStream.streamError.code==5);
                }
            }else{assert(data&&data.length==7&&!large&&!stopped&&owner->reason()==TLinkNativeStop::None);}
            if(heldBudgetStream)assert(heldBudgetStream.streamStatus==NSStreamStatusClosed);
            assert(owner->response().size()==(kind==5?4:prefix));
            heldBudgetStream=nil;
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
    }
    budgetWriterOwner.reset();
    for(bool current:{false,true}){@autoreleasepool{
        heldBudgetStream=nil;budgetWriterCalls=0;budgetWriterMode=5;
        NSString *text=[@"" stringByPaddingToLength:100000 withString:@"x" startingAtIndex:0];
        auto owner=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,64);
        TLinkNativeBudgetScope scope(owner);BOOL large=YES,stopped=YES;
        NSData *data=budgetWriterCall(current,@{@"text":text},&large,&stopped);
        if(current)assert(!data&&large&&!stopped&&budgetBufferLength(true)<=42);
        else assert(data&&data.length>42&&!large&&!stopped);
        assert(budgetWriterCalls==1&&heldBudgetStream.streamStatus==NSStreamStatusClosed);heldBudgetStream=nil;
    }}
    // An already-cancelled caller must not be poisoned by the new minimum-wire check.
    @autoreleasepool{
        auto cancel=std::make_shared<TLinkNativeCancellation>();cancel->cancel();
        auto owner=std::make_shared<TLinkNativeBudget>(cancel,0,1);TLinkNativeBudgetScope scope(owner);
        heldBudgetStream=nil;budgetWriterCalls=0;BOOL large=YES,stopped=YES;
        assert(!budgetWriterCall(true,@{},&large,&stopped)&&!large&&stopped&&budgetWriterCalls==0);
        assert(owner->reason()==TLinkNativeStop::Cancelled);
    }
}
static void jsonBudgetCodecCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(bool shortBudget:{false,true})for(bool current:{false,true}){@autoreleasepool{
        reset();useBeforeOutputJSON=true;NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀"};fixtureCapability=graph;
        const size_t wire=call(root,capability,true,graph).length;
        jsonCalls=base64Calls=0;lastJSON=captured=nil;useBeforeOutputJSON=!current;
        auto owner=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,wire+3-(shortBudget?1:0),false,true);
        assert(owner->appendCString((const uint8_t *)"old")==3);
        auto child=std::make_shared<TLinkNativeBudget>(0,owner);TLinkNativeBudgetScope scope(child);
        NSData *reply=call(root,capability,true,graph);
        if(shortBudget){
            errorReply(reply,@"ui_response_too_large");assert(base64Calls==0&&owner->reason()==TLinkNativeStop::OutputLimit);
            assert(current?lastJSON==nil:lastJSON!=nil);
        }else{decoded(reply);assert(base64Calls==1&&owner->reason()==TLinkNativeStop::None);}
        assert(jsonCalls==1&&owner->response().size()==3);
    }}
    for(unsigned n=0;n<128;++n){@autoreleasepool{
        reset();auto owner=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,9);
        {
            TLinkNativeBudgetScope scope(owner);BOOL large=YES,stopped=YES;
            NSData *data=TLinkAXBoundedJSONDataWithStop(@{},&large,&stopped);assert(data&&!large&&!stopped&&data.length==2);
        }
        auto other=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,8);
        {
            TLinkNativeBudgetScope scope(other);BOOL large=NO,stopped=YES;
            assert(!TLinkAXBoundedJSONDataWithStop(@{},&large,&stopped)&&large&&!stopped);
        }
    }}
}
static void jsonBudgetCases(){
    std::puts("AX JSON output budget: actual/current C05u writer, real native parent/remaining output and controlled chunks plus Foundation encoder");
    jsonBudgetWriterCases();jsonBudgetCodecCases();reset();
    std::puts("AX JSON output budget passed: minimum/exact/short/unlimited allowances, prefix and nested TLS isolation, zero rejected appends, pre-copy growth refusal, bounded real-writer prefix, cancellation precedence, four codec parity and 128 exact/refusal lifecycles. Admission reserves no output; Foundation internals/final delivery/device qualification pending.");
}
