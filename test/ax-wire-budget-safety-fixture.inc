static void wireBudgetAdmissionCases(){
    using namespace TLinkAXWireBudget;
    for(unsigned n=0;n<100000;++n){
        const size_t wire=5+(n%1024)*4,prefix=n%7;
        auto cancel=std::make_shared<TLinkNativeCancellation>();
        auto parent=std::make_shared<TLinkNativeBudget>(cancel,0,wire+prefix,false,true);
        auto budget=std::make_shared<TLinkNativeBudget>(0,parent);
        for(size_t i=0;i<prefix;++i)assert(parent->appendCString((const uint8_t *)"p")==1);
        assert(Check(budget,wire)==Admission::Ready&&parent->response().size()==prefix);
        if(n%2){
            cancel->cancel();assert(Check(budget,wire)==Admission::Stopped);
            assert(parent->reason()==TLinkNativeStop::Cancelled);
        }else{
            assert(parent->appendCString((const uint8_t *)"x")==1);
            assert(Check(budget,wire)==Admission::TooLarge&&Check(budget,0)==Admission::TooLarge);
            assert(parent->reason()==TLinkNativeStop::OutputLimit);
        }
        assert(parent->response().size()==prefix+(n%2?0:1));
    }
    auto cancel=std::make_shared<TLinkNativeCancellation>();cancel->cancel();
    auto stopped=std::make_shared<TLinkNativeBudget>(cancel,0,1);
    assert(Check(stopped,100)==Admission::Stopped&&stopped->reason()==TLinkNativeStop::Cancelled);
    auto expired=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),TLinkNativeNowNs(),1);
    assert(Check(expired,100)==Admission::Stopped&&expired->reason()==TLinkNativeStop::Deadline);
    auto cleanup=std::make_shared<TLinkNativeBudget>(cancel,TLinkNativeNowNs(),1024,true);
    assert(Check(cleanup,13)==Admission::Ready);
    auto live=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,13);
    {TLinkNativeBudgetScope scope(stopped);assert(Check(live,13)==Admission::Ready);}
    {TLinkNativeBudgetScope scope(live);assert(Check(stopped,13)==Admission::Stopped);}
    auto unlimited=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,0);
    assert(Check(unlimited,TLinkAXWireOutput::MaxSuccessWireBytes)==Admission::Ready);
    assert(Check(unlimited,std::numeric_limits<size_t>::max())==Admission::TooLarge&&unlimited->reason()==TLinkNativeStop::None);
    assert(Check(TLinkNativeBudgetPtr{},13)==Admission::Ready);
    assert(Check(TLinkNativeBudgetPtr{},TLinkAXWireOutput::MaxSuccessWireBytes+1)==Admission::TooLarge);
    assert(std::strcmp(FailureWire(Admission::Stopped),"-1;;ui_cancelled_or_timed_out\r\n")==0);
    assert(std::strcmp(FailureWire(Admission::TooLarge),"-1;;ui_response_too_large\r\n")==0);
    assert(!TLinkCurrentNativeBudget());
    std::puts("AX wire budget passed: 100k captured parent/prefix/exact/cancel/consumed-output cases, sticky refusal without reservation, deadline/cleanup/unlimited/TLS and hard-size boundaries.");
}
