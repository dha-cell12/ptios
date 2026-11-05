#include "../shared/TLinkAXAdmission.h"
#include <cassert>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <thread>
#include <vector>
using namespace TLinkAXAdmission;
static_assert(MaxPending==8,"UI Tree v1 admission contract");
int main(){
    State state;std::vector<std::unique_ptr<Lease>> held;
    for(unsigned n=0;n<MaxPending;++n){held.emplace_back(new Lease(state));assert(held.back()->held()&&state.pending()==n+1);}
    {Lease refused(state);assert(!refused.held()&&state.pending()==MaxPending);refused.release();}
    assert(state.pending()==MaxPending);held[3]->release();held[3]->release();assert(state.pending()==MaxPending-1);
    {Lease replacement(state);assert(replacement.held()&&state.pending()==MaxPending);}
    held.clear();assert(state.pending()==0);
    try{Lease scope(state);assert(scope.held());throw std::runtime_error("work");}catch(const std::runtime_error &){}
    assert(state.pending()==0);
    State other;{Lease one(state),two(other);assert(one.held()&&two.held()&&state.pending()==1&&other.pending()==1);}
    assert(state.pending()==0&&other.pending()==0);
    for(unsigned n=0;n<100000;++n){Lease scope(state);assert(scope.held()&&state.pending()==1);}
    std::vector<std::thread> threads;
    for(unsigned worker=0;worker<16;++worker)threads.emplace_back([&]{
        for(unsigned n=0;n<10000;++n){Lease scope(state);assert(state.pending()<=MaxPending);scope.release();scope.release();}
    });
    for(auto &thread:threads)thread.join();
    assert(state.pending()==0);
    Lease shared(state);threads.clear();for(unsigned n=0;n<8;++n)threads.emplace_back([&]{shared.release();});
    for(auto &thread:threads)thread.join();
    assert(state.pending()==0&&!shared.held());
    std::puts("AX admission passed: eight-slot refusal/recovery, denied-owner isolation, scope/exception release, independent states, 100k lifecycles, 160k concurrent attempts and duplicate release; zero final charges.");
}
