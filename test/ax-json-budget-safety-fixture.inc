static void jsonOutputAdmissionCases(){
    using namespace TLinkAXJSONOutput;
    for(unsigned n=0;n<100000;++n){
        const size_t bytes=(n*31U)%2048,wire=5+4*((bytes+2)/3),prefix=n%4;
        const bool unlimited=n%3==0,shortage=n%3==1;
        const size_t cap=unlimited?0:wire+prefix-(shortage?1:0);
        auto budget=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,cap,false,true);
        if(!unlimited)for(size_t i=0;i<prefix;++i)assert(budget->appendCString((const uint8_t *)"p")==1);
        auto child=std::make_shared<TLinkNativeBudget>(0,budget);
        assert(AdmitOutput(child,bytes)==!shortage);
        assert(budget->response().size()==(unlimited?0:prefix)); // Admission reserves no bytes.
        assert((budget->reason()==TLinkNativeStop::OutputLimit)==shortage);
        if(shortage)assert(!AdmitOutput(child,0));
    }
    auto captured=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,64);
    {
        auto other=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1);
        TLinkNativeBudgetScope nested(other);
        assert(AdmitOutput(captured,2)&&other->reason()==TLinkNativeStop::None);
    }
    auto small=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,8);
    {
        TLinkNativeBudgetScope nested(captured);
        assert(!AdmitOutput(small,2)&&captured->reason()==TLinkNativeStop::None);
    }
    auto hard=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,1);
    assert(!AdmitOutput(hard,std::numeric_limits<size_t>::max())&&hard->reason()==TLinkNativeStop::None);
    assert(AdmitOutput(TLinkNativeBudgetPtr{},786426)&&!AdmitOutput(TLinkNativeBudgetPtr{},786427));
    assert(!TLinkCurrentNativeBudget());
    std::puts("AX JSON output admission passed: 100k real parent/remaining/prefix/exact/short/unlimited cases, sticky refusal without reservation, captured-budget isolation and hard-wire rejection without native poisoning.");
}
