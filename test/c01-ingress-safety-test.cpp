#include "../shared/TLinkC01Ingress.h"
#include <cassert>
#include <cstdio>
#include <string>
static const uint8_t *wire(const char *text){return reinterpret_cast<const uint8_t *>(text);}
int main(){
    for(const char *s:{"23","28","69","91"})assert(TLinkC01DurationNs(wire(s),2)==3000000000ULL);
    for(const char *s:{"21","49","68","70","271;;","276;;"})assert(TLinkC01DurationNs(wire(s),strlen(s))==8000000000ULL);
    for(const char *s:{"","6","10","18","272","275","67","483;;1","95"})assert(!TLinkC01DurationNs(wire(s),strlen(s)));
    auto token=std::make_shared<TLinkNativeCancellation>();
    auto parent=std::make_shared<TLinkNativeBudget>(token,TLinkNativeDeadline(30),16,false,true);
    uint64_t deadline=parent->deadline(),entered=TLinkNativeNowNs();
    auto child=TLinkC01TaskBudget(wire("69"),2,parent,entered);
    assert(child!=parent&&child->deadline()==entered+3000000000ULL&&parent->deadline()==deadline);
    assert(child->capturesResponse()&&child->appendCString(wire("0;;hello"))==8&&parent->response().size()==8);
    assert(child->response().data()==parent->response().data());
    assert(child->appendCString(wire("012345678"))==-1&&parent->reason()==TLinkNativeStop::OutputLimit&&child->reason()==TLinkNativeStop::OutputLimit);
    assert(TLinkC01TaskBudget(wire("10"),2,parent)==parent);
    parent=std::make_shared<TLinkNativeBudget>(token,TLinkNativeDeadline(.02),32,false,true);
    child=TLinkC01TaskBudget(wire("69"),2,parent);assert(child->deadline()==parent->deadline());
    const auto waits=TLinkC01IPCTimeouts(child,5);assert(waits.send>0&&waits.receive>0&&waits.send+waits.receive<=.02);
    assert(!child->waitNs(1000000000ULL)&&child->reason()==TLinkNativeStop::Deadline);
    parent=std::make_shared<TLinkNativeBudget>(token,0,32,false,true);child=TLinkC01TaskBudget(wire("69"),2,parent);
    token->cancel();assert(child->reason()==TLinkNativeStop::Cancelled&&TLinkC01IPCTimeouts(child,5).receive==0);
    auto expired=TLinkC01TaskBudget(wire("69"),2,{},TLinkNativeNowNs()-3000000001ULL);assert(expired->stopped());
    auto cleanup=std::make_shared<TLinkNativeBudget>(token,0,32,true,true);
    child=TLinkC01TaskBudget(wire("69"),2,cleanup);assert(!child->cleanup()&&child->stopped());
    assert(TLinkC01TaskBudget(wire("67"),2,cleanup)==cleanup);
    auto fresh=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,64,false,true);
    auto old=TLinkC01TaskBudget(wire("69"),2,fresh,TLinkNativeNowNs()-3000000001ULL);
    auto sibling=TLinkC01TaskBudget(wire("69"),2,fresh);assert(old->stopped()&&!fresh->stopped()&&!sibling->stopped());
    for(unsigned i=0;i<64;++i){
        auto cancel=std::make_shared<TLinkNativeCancellation>();auto root=std::make_shared<TLinkNativeBudget>(cancel,0,64);
        auto running=TLinkC01TaskBudget(wire("69"),2,root);std::atomic_bool waitingEntered{false};
        std::thread worker([&]{waitingEntered.store(true);assert(!running->waitNs(60000000000ULL));});
        while(!waitingEntered.load())std::this_thread::yield();cancel->cancel();worker.join();assert(running->reason()==TLinkNativeStop::Cancelled);
    }
    const uint64_t now=90000000000ULL;
    for(const char *s:{"TASK::69pick;;1","TASK::271;;x","TASK::276;;x","TASK::21template","TASK::291;;file","TASK::35"}){
        auto bytes=TLinkC01Encode(wire(s),strlen(s),now+3000000000ULL);assert(bytes.size()==strlen(s)+12);
        TLinkC01Envelope envelope;
        assert(TLinkC01Decode(bytes.data(),bytes.size(),envelope,now)==TLinkC01DecodeResult::Valid);
        assert(envelope.deadline==now+3000000000ULL&&envelope.length==strlen(s)&&memcmp(envelope.payload,s,envelope.length)==0);
        for(size_t size=0;size<20;++size)assert(TLinkC01Decode(bytes.data(),size,envelope,now)==TLinkC01DecodeResult::Invalid);
        assert(TLinkC01Decode(bytes.data(),bytes.size(),envelope,now+3000000000ULL)==TLinkC01DecodeResult::Expired&&!envelope.payload);
        bytes[0]^=1;assert(TLinkC01Decode(bytes.data(),bytes.size(),envelope,now)==TLinkC01DecodeResult::Invalid);
    }
    for(const char *s:{"TASK::10","TASK::67","TASK::275","CMD_PING","TASK::99"})assert(TLinkC01Encode(wire(s),strlen(s),now+1).empty());
    auto bytes=TLinkC01Encode(wire("TASK::69"),8,now+8000000001ULL);TLinkC01Envelope envelope;
    assert(TLinkC01Decode(bytes.data(),bytes.size(),envelope,now)==TLinkC01DecodeResult::Invalid);
    std::string oversized(4096,'x');assert(TLinkC01Encode(wire(oversized.c_str()),oversized.size(),now+1).empty());
    uint32_t random=31;
    for(unsigned n=0;n<100000;++n){
        std::vector<uint8_t> input(1+n%96);for(auto &v:input){random=random*1664525U+1013904223U;v=uint8_t(random>>24);}
        assert(TLinkC01Decode(input.data(),input.size(),envelope,now)!=TLinkC01DecodeResult::Valid);
    }
    {TLinkNativeBudgetScope first(parent);{TLinkNativeBudgetScope second(child);assert(TLinkCurrentNativeBudget()==child);}assert(TLinkCurrentNativeBudget()==parent);}
    assert(!TLinkCurrentNativeBudget());
    puts("C01 ingress passed: classification, non-extending deadlines, shared output/cancel, cleanup isolation, bounded envelope/fuzz and IPC time allocation.");
}
