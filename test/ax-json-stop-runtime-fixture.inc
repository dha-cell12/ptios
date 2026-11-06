static std::shared_ptr<TLinkNativeCancellation> stopWriterCancellation;
static NSOutputStream *heldStopStream;
static unsigned stopWriterMode=11,stopWriterCalls=0;
static BOOL stopWriterSpace=NO;
static NSInteger jsonStopWriter(id object,NSOutputStream *output,NSError *__autoreleasing *error){
    (void)object;(void)error;++stopWriterCalls;heldStopStream=output;
    const uint8_t body[]={'{','}'};
    if(stopWriterMode==6||stopWriterMode==7){
        auto cancel=std::make_shared<TLinkNativeCancellation>();
        if(stopWriterMode==6)cancel->cancel();else stopWriterCancellation->cancel();
        auto other=std::make_shared<TLinkNativeBudget>(cancel,0,1024);
        TLinkNativeBudgetScope nested(other);stopWriterSpace=output.hasSpaceAvailable;
        return [output write:body maxLength:2];
    }
    if(stopWriterMode==8){
        const auto budget=TLinkCurrentNativeBudget();assert(budget&&budget->deadline());
        while(TLinkNativeNowNs()<budget->deadline())
            std::this_thread::sleep_until(TLinkNativeClock::time_point(std::chrono::nanoseconds(budget->deadline())));
        return [output write:body maxLength:2];
    }
    if(stopWriterMode==0)stopWriterCancellation->cancel();
    if(stopWriterMode==3){stopWriterCancellation->cancel();return 0;}
    if(stopWriterMode==1){
        assert([output write:body maxLength:1]==1);stopWriterCancellation->cancel();
        const NSInteger final=[output write:body+1 maxLength:1];return final<0?0:2;
    }
    const NSInteger written=[output write:body maxLength:2];
    if(stopWriterMode==2)stopWriterCancellation->cancel();
    if(stopWriterMode==4||stopWriterMode==5){
        if(stopWriterMode==4)stopWriterCancellation->cancel();
        NSMutableData *large=[NSMutableData dataWithLength:TLinkAXJSONOutput::MaxJSONBytes+1];
        assert([output write:(const uint8_t *)large.bytes maxLength:large.length]==-1);
        if(stopWriterMode==5)stopWriterCancellation->cancel();
        return 0;
    }
    if(stopWriterMode==9){stopWriterCancellation->cancel();[NSException raise:@"JSONStopFixture" format:@"writer"];}
    if(stopWriterMode==10){stopWriterCancellation->cancel();throw std::runtime_error("stopped writer");}
    return written;
}
static NSData *stopWriterCall(bool current,BOOL *large,BOOL *stopped){
    *stopped=NO;
    return current?TLinkAXJSONDataWithWriter(@{},large,jsonStopWriter,stopped):
        BeforeStopTLinkAXJSONDataWithWriter(@{},large,jsonStopWriter);
}
static void resetStopWriter(unsigned mode){
    stopWriterMode=mode;stopWriterCalls=0;stopWriterSpace=NO;heldStopStream=nil;
}
static void jsonStopPreflightCases(){
    for(bool parent:{false,true})for(unsigned kind=0;kind<5;++kind)for(bool current:{false,true}){@autoreleasepool{
        resetStopWriter(11);stopWriterCancellation=std::make_shared<TLinkNativeCancellation>();
        const bool cleanup=kind==3;
        auto owner=std::make_shared<TLinkNativeBudget>(stopWriterCancellation,kind==1||cleanup?TLinkNativeNowNs():0,64,cleanup);
        if(kind==0||cleanup)stopWriterCancellation->cancel();
        if(kind==2){assert(!owner->outputAllowed(65));stopWriterCancellation->cancel();}
        auto budget=parent?std::make_shared<TLinkNativeBudget>(0,owner):owner;
        TLinkNativeBudgetScope scope(budget);BOOL large=YES,stopped=YES;
        NSData *data=stopWriterCall(current,&large,&stopped);
        const bool cancel=kind==0||kind==1||(cleanup&&parent),limit=kind==2;
        if(current&&(cancel||limit))assert(!data&&stopWriterCalls==0&&large==limit&&stopped==cancel&&!heldStopStream);
        else assert(data&&stopWriterCalls==1&&!large&&!stopped&&heldStopStream.streamStatus==NSStreamStatusClosed);
        heldStopStream=nil;
    }}
    stopWriterCancellation.reset();assert(!TLinkCurrentNativeBudget());
}
static void jsonStopDuringWriterCases(){
    for(bool parent:{false,true})for(unsigned mode=0;mode<=10;++mode)for(bool current:{false,true}){
        std::weak_ptr<TLinkNativeBudget> weak;
        @autoreleasepool{
            resetStopWriter(mode);stopWriterCancellation=std::make_shared<TLinkNativeCancellation>();
            auto owner=std::make_shared<TLinkNativeBudget>(stopWriterCancellation,mode==8?TLinkNativeDeadline(.01):0,1024*1024);
            auto budget=parent?std::make_shared<TLinkNativeBudget>(0,owner):owner;weak=budget;
            TLinkNativeBudgetScope scope(budget);BOOL large=YES,stopped=YES;NSData *data=nil;bool caught=false;
            @try{try{data=stopWriterCall(current,&large,&stopped);}catch(const std::runtime_error &){caught=mode==10;}}
            @catch(NSException *exception){caught=mode==9&&[exception.name isEqualToString:@"JSONStopFixture"];}
            assert(caught==(mode==9||mode==10));
            if(heldStopStream)assert(heldStopStream.streamStatus==NSStreamStatusClosed);
            if(mode>=9)assert(!data&&!large&&!stopped);
            else if(mode==6){assert(data&&!large&&!stopped&&stopWriterSpace);}
            else if(current){assert(!data&&!large&&stopped);}
            else if(mode==3||mode==4||mode==5){assert(!data&&!stopped&&large==(mode==4||mode==5));}
            else assert(data&&!large&&!stopped);
            if(mode!=8)assert(stopWriterCalls==1); // Expired CI scheduling may skip the deadline writer entirely.
            if(mode==7)assert(stopWriterSpace==!current);
            heldStopStream=nil;
        }
        assert(weak.expired()&&!TLinkCurrentNativeBudget());
    }
    stopWriterCancellation.reset();
}
static NSData *beforeJSONStopCall(bool root,bool capability,NSDictionary *value){
    if(root){if(capability)BeforeJSONStopRootCapability(NULL);else BeforeJSONStopRootResponse(value,NULL);return captured;}
    return capability?BeforeJSONStopTrollCapability():BeforeJSONStopTrollResponse(value);
}
static void jsonStopCodecCases(){
    for(bool root:{false,true})for(bool capability:{false,true})for(unsigned kind=0;kind<3;++kind)for(bool current:{false,true}){@autoreleasepool{
        reset();auto cancel=std::make_shared<TLinkNativeCancellation>();
        auto owner=std::make_shared<TLinkNativeBudget>(cancel,kind==1?TLinkNativeNowNs():0,1024*1024);
        if(kind==2)assert(!owner->outputAllowed(1024*1024+1));else if(kind==0)cancel->cancel();
        auto child=std::make_shared<TLinkNativeBudget>(0,owner);TLinkNativeBudgetScope scope(child);
        NSData *reply=current?call(root,capability,true,@{@"ok":@YES}):beforeJSONStopCall(root,capability,@{@"ok":@YES});
        if(current||kind==2){
            errorReply(reply,kind==2?@"ui_response_too_large":@"ui_cancelled_or_timed_out");assert(base64Calls==0);
            assert(current?!lastJSON:lastJSON!=nil);
        }else{decoded(reply);assert(base64Calls==1);}
        assert(jsonCalls==(current&&capability?0U:1U)&&child->reason()==(kind==2?TLinkNativeStop::OutputLimit:(kind==1?TLinkNativeStop::Deadline:TLinkNativeStop::Cancelled)));
    }}
    for(bool root:{false,true})for(bool capability:{false,true}){
        NSDictionary *expected=nil;
        for(bool current:{false,true}){@autoreleasepool{
            reset();NSDictionary *graph=@{@"ok":@YES,@"text":@"Ứng dụng 测试😀"};fixtureCapability=graph;
            NSDictionary *value=decoded(current?call(root,capability,true,graph):beforeJSONStopCall(root,capability,graph));
            if(current)assert([value isEqual:expected]);else expected=value;
        }}
    }
}
static void jsonStopLifetimeCases(){
    for(unsigned n=0;n<128;++n){
        std::weak_ptr<TLinkNativeBudget> weak;NSData *held=nil;
        @autoreleasepool{
            auto cancel=std::make_shared<TLinkNativeCancellation>();auto budget=std::make_shared<TLinkNativeBudget>(cancel,0,1024*1024);weak=budget;
            TLinkNativeBudgetScope scope(budget);BOOL large=YES,stopped=YES;
            held=TLinkAXBoundedJSONDataWithStop(@{@"n":@(n)},&large,&stopped);assert(held&&!large&&!stopped);
        }
        assert(weak.expired()&&held&&!TLinkCurrentNativeBudget());
        @autoreleasepool{
            auto cancel=std::make_shared<TLinkNativeCancellation>();cancel->cancel();
            auto budget=std::make_shared<TLinkNativeBudget>(cancel,0,1024);TLinkNativeBudgetScope scope(budget);BOOL large=YES;
            assert(!TLinkAXBoundedJSONData(@{},&large)&&!large);
        }
    }
}
static void jsonStopCases(){
    std::puts("AX JSON stop: actual captured budget/stream/writer and C05t frozen implementation with real cancellation/deadline/parent scopes");
    jsonStopPreflightCases();jsonStopDuringWriterCases();jsonStopCodecCases();jsonStopLifetimeCases();
    reset();
    std::puts("AX JSON stop passed: pre-writer refusal, chunk/final cancellation, deadline, parent/cleanup/output-limit precedence, nested TLS isolation, NS/C++ close/unwind, four cancellation codecs without base64 and 128 independent result/budget lifecycles. Opaque Foundation work/device qualification pending.");
}
