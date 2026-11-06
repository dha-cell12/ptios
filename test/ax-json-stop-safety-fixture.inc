static void jsonStopPolicyCases(){
    using namespace TLinkAXJSONOutput;
    assert(!ClassifyStop(TLinkNativeBudgetPtr{}).active);
    for(unsigned n=0;n<100000;++n){
        auto cancel=std::make_shared<TLinkNativeCancellation>();
        const unsigned kind=n%5;
        const bool cleanup=kind==4;
        auto budget=std::make_shared<TLinkNativeBudget>(cancel,kind==2||cleanup?TLinkNativeNowNs():0,64,cleanup);
        if(kind==1||cleanup)cancel->cancel();
        if(kind==3){assert(!budget->outputAllowed(65));cancel->cancel();}
        auto child=std::make_shared<TLinkNativeBudget>(0,budget);
        const auto state=ClassifyStop(cleanup?budget:child);
        assert(state.active==(kind==1||kind==2||kind==3));
        assert(state.tooLarge==(kind==3)&&state.cancelled==(kind==1||kind==2));
        assert(state.active==(cleanup?budget:child)->stopped());
        if(cleanup)assert(child->stopped());
        if(cleanup){assert(!budget->outputAllowed(65));assert(ClassifyStop(child).tooLarge);}
    }
    auto outerCancel=std::make_shared<TLinkNativeCancellation>();
    auto captured=std::make_shared<TLinkNativeBudget>(outerCancel,0,0);
    {
        TLinkNativeBudgetScope outer(captured);
        auto innerCancel=std::make_shared<TLinkNativeCancellation>();innerCancel->cancel();
        auto inner=std::make_shared<TLinkNativeBudget>(innerCancel,0,64);
        {
            TLinkNativeBudgetScope nested(inner);
            assert(TLinkNativeStopped()&&!ClassifyStop(captured).active);
        }
        outerCancel->cancel();assert(ClassifyStop(captured).cancelled);
        {
            auto live=std::make_shared<TLinkNativeBudget>(std::make_shared<TLinkNativeCancellation>(),0,64);
            TLinkNativeBudgetScope nested(live);
            assert(!TLinkNativeStopped()&&ClassifyStop(captured).cancelled);
        }
    }
    assert(!TLinkCurrentNativeBudget());
    std::puts("AX JSON stop policy passed: 100k real parent/cancel/deadline/output-limit/cleanup classifications, sticky overflow precedence, unlimited output and captured-budget isolation from nested TLS scopes.");
}
