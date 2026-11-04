#include "../shared/TLinkSupervisorEnsureAdmission.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>
using namespace TLinkSupervisorEnsureAdmission;
int main(){
    auto state=std::make_shared<State>();
    std::vector<std::shared_ptr<Lease>> held;
    for(unsigned n=0;n<MaxPending;++n){auto lease=std::make_shared<Lease>(state);assert(lease->held());held.push_back(lease);}
    assert(state->pending()==MaxPending);
    auto denied=std::make_shared<Lease>(state);assert(!denied->held());denied->release();assert(state->pending()==MaxPending);
    held.front()->release();held.front()->release();assert(state->pending()==MaxPending-1);
    auto admitted=std::make_shared<Lease>(state);assert(admitted->held());held.clear();admitted->release();assert(state->pending()==0);
    for(unsigned n=0;n<100000;++n){
        auto lease=std::make_shared<Lease>(state);
        {Scope scope{lease};assert(state->pending()==1);}
        assert(state->pending()==0&&!lease->held());lease->release();
    }
    auto lease=std::make_shared<Lease>(state);try{Scope scope{lease};throw std::runtime_error("owner work");}catch(const std::runtime_error &){}
    assert(state->pending()==0&&!lease->held());
    auto independent=std::make_shared<State>();auto other=std::make_shared<Lease>(independent);assert(independent->pending()==1&&state->pending()==0);other->release();
    auto missing=std::make_shared<Lease>(nullptr);assert(!missing->held());missing->release();
    std::vector<std::thread> threads;
    for(unsigned n=0;n<16;++n){threads.emplace_back([state]{
        for(unsigned cycle=0;cycle<10000;++cycle){auto ticket=std::make_shared<Lease>(state);assert(state->pending()<=MaxPending);ticket->release();ticket->release();}
    });}
    for(auto &thread:threads){thread.join();}assert(state->pending()==0);
    auto shared=std::make_shared<Lease>(state);threads.clear();
    for(unsigned n=0;n<16;++n){threads.emplace_back([shared]{shared->release();});}
    for(auto &thread:threads){thread.join();}assert(state->pending()==0);
    puts("Supervisor ensure admission passed: eight-slot refusal/recovery, retained leases with explicit/scope/exception retirement, 100k lifecycles, per-instance isolation, 160k concurrent attempts and concurrent duplicate release; zero final charges.");
}
