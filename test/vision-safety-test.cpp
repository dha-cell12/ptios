#include "../shared/TLinkVisionPolicy.h"
#include <cassert>
#include <cstdio>
#include <thread>
int main(){
    TLinkVisionROI roi;
    assert(TLinkVisionPlan(100,80,10,20,0,0,roi)&&roi.width==90&&roi.height==60);
    assert(TLinkVisionPlan(100,80,10,20,1000,1000,roi)&&roi.width==90&&roi.height==60);
    assert(!TLinkVisionPlan(100,80,-1,0,10,10,roi));
    assert(!TLinkVisionPlan(100,80,100,0,10,10,roi));
    assert(!TLinkVisionPlan(100,80,0,0,-1,10,roi));
    assert(!TLinkVisionPlan(8193,1,0,0,1,1,roi));
    assert(!TLinkVisionPlan(4096,4096,0,0,1,1,roi));
    assert(!TLinkVisionPlan(3000,2000,0,0,0,0,roi));
    assert(TLinkVisionPlan(2048,2048,0,0,0,0,roi));
    assert(!TLinkVisionPlan(100,80,0,0,std::numeric_limits<double>::quiet_NaN(),1,roi));
    for(unsigned i=0;i<100000;++i){double x=i%100,y=i%80;assert(TLinkVisionPlan(100,80,x,y,0,0,roi));assert(roi.width>0&&roi.height>0&&roi.x+roi.width==100&&roi.y+roi.height==80);}
    {
        auto first=std::make_shared<TLinkVisionContext>(TLinkNativeBudgetPtr{},100);
        auto second=std::make_shared<TLinkVisionContext>(TLinkNativeBudgetPtr{},100);
        TLinkVisionContext third({},100);assert(first->admitted()&&second->admitted()&&!third.admitted());
        assert(!first->stopped(8000000099ULL)&&first->stopped(8000000100ULL));
        assert(first->outputAllowed(1048576)&&!first->outputAllowed(1048577));
        TLinkVisionScope scope(first);assert(TLinkVisionSlot()==first);
        {TLinkVisionScope nested(second);assert(TLinkVisionSlot()==second);}assert(TLinkVisionSlot()==first);
    }
    assert(!TLinkVisionSlot());
    auto token=std::make_shared<TLinkNativeCancellation>();auto parent=std::make_shared<TLinkNativeBudget>(token,0,32);
    {TLinkVisionContext ctx(parent);assert(ctx.outputAllowed(32)&&!ctx.outputAllowed(33)&&ctx.stopped());}
    parent=std::make_shared<TLinkNativeBudget>(token,0,32);
    {TLinkVisionContext ctx(parent);token->cancel();assert(ctx.stopped());}
    std::vector<std::thread> threads;
    for(unsigned n=0;n<8;++n)threads.emplace_back([]{for(unsigned i=0;i<10000;++i){auto ctx=std::make_shared<TLinkVisionContext>(TLinkNativeBudgetPtr{});TLinkVisionScope scope(ctx);assert(TLinkVisionSlot()==ctx);}});
    for(auto &thread:threads)thread.join();
    {TLinkVisionContext a({}),b({}),c({});assert(a.admitted()&&b.admitted()&&!c.admitted());}
    puts("Vision policy passed: 100k ROI plans, pixel/axis/output boundaries, eight-second/parent cancellation, nested TLS and 80k concurrent admission lifecycles.");
}
