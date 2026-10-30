#include "../shared/TLinkVPNBrokerOperations.h"
#include <cassert>
#include <cstdio>
#include <stdexcept>
#include <thread>
#include <vector>
using Owner=TLinkVPNBrokerOperations;
using Ticket=std::shared_ptr<Owner::Ticket>;
static void capacityCases(){
    Owner owner;std::vector<Ticket> held;
    for(unsigned n=0;n<8;++n){auto ticket=owner.acquire();assert(ticket&&ticket->start());held.push_back(ticket);}
    assert(owner.stats().active==8&&owner.stats().peak==8&&!owner.acquire());
    for(auto &ticket:held){assert(ticket->returned());assert(!ticket->cancel());}
    assert(!owner.acquire()); // Waiters may have left; backend completions have not.
    Ticket old=held[0];assert(old->complete());auto replacement=owner.acquire();assert(replacement&&replacement->start());
    assert(!old->complete()&&!old->returned()&&!old->cancel()&&owner.stats().active==8);
    assert(replacement->complete()&&owner.stats().active==8);assert(replacement->returned());
    for(size_t n=1;n<held.size();++n)assert(held[n]->complete());
    assert(owner.stats().active==0&&owner.stats().completed==9&&owner.stats().rejected==2);
}
static void lifecycleCases(){
    Owner owner;uint64_t cancelled=0,completed=0;
    for(unsigned n=0;n<100000;++n){
        auto ticket=owner.acquire();assert(ticket&&!ticket->complete()&&!ticket->returned());
        if(n%3==0){if(n%2==0)assert(ticket->cancel());ticket.reset();++cancelled;}
        else{
            assert(ticket->start()&&!ticket->start());
            if(n%2){assert(ticket->complete()&&owner.stats().active==1);assert(ticket->returned());}
            else{assert(ticket->returned()&&owner.stats().active==1);assert(ticket->complete());}
            assert(!ticket->complete()&&!ticket->returned()&&!ticket->cancel());++completed;
        }
        assert(owner.stats().active==0);
    }
    const auto stats=owner.stats();assert(stats.admitted==100000&&stats.cancelled==cancelled&&stats.completed==completed);
    Owner uncertain;
    for(unsigned n=0;n<8;++n){auto ticket=uncertain.acquire();assert(ticket&&ticket->start());{TLinkVPNBrokerStarterScope exited{ticket};}ticket.reset();}
    assert(uncertain.stats().active==8&&!uncertain.acquire()); // Dropped callback is not completion evidence.
    Owner throwing;auto ticket=throwing.acquire();assert(ticket->start());
    try{TLinkVPNBrokerStarterScope scope{ticket};throw std::runtime_error("starter");}catch(const std::runtime_error &){}
    assert(throwing.stats().active==1&&ticket->complete()&&throwing.stats().active==0);
}
static void edgeCases(){
    Owner last(UINT64_MAX-1);auto ticket=last.acquire();assert(ticket&&ticket->start()&&ticket->returned()&&ticket->complete());
    assert(last.stats().active==0&&!last.acquire());Owner exhausted(UINT64_MAX);assert(!exhausted.acquire());
    Ticket survives;{Owner temporary;survives=temporary.acquire();assert(survives->start()&&survives->returned());}
    assert(survives->complete()&&!survives->complete());
}
static void concurrentCases(){
    Owner owner;std::vector<std::thread> workers;
    for(unsigned thread=0;thread<8;++thread)workers.emplace_back([&owner,thread]{
        for(unsigned n=0;n<10000;++n){
            auto ticket=owner.acquire();assert(ticket&&ticket->start());
            if((n+thread)%2){assert(ticket->complete());assert(ticket->returned());}
            else{assert(ticket->returned());assert(ticket->complete());}
        }
    });
    for(auto &worker:workers)worker.join();
    const auto stats=owner.stats();assert(stats.active==0&&stats.admitted==80000&&stats.completed==80000&&stats.peak<=8&&stats.rejected==0);
    for(unsigned n=0;n<1000;++n){auto ticket=owner.acquire();assert(ticket->start());
        std::thread callback([ticket]{assert(ticket->complete());});std::thread returned([ticket]{assert(ticket->returned());});
        callback.join();returned.join();assert(owner.stats().active==0);
    }
}
static void configuredLimitCases(){
    Owner disabled(0,0);assert(!disabled.acquire()&&disabled.stats().active==0);
    Owner single(0,1);auto first=single.acquire();assert(first&&first->start()&&!single.acquire());
    assert(first->returned()&&!single.acquire());assert(first->complete()&&single.stats().active==0);
    auto next=single.acquire();assert(next&&!first->complete()&&single.stats().active==1);next.reset();
    assert(single.stats().active==0&&single.stats().peak==1);
    Owner clamped(0,SIZE_MAX);std::vector<Ticket> held;
    for(unsigned n=0;n<8;++n){held.push_back(clamped.acquire());assert(held.back());}
    assert(!clamped.acquire()&&clamped.stats().active==8);held.clear();assert(clamped.stats().active==0);
    Owner concurrent(0,1);std::vector<std::thread> workers;
    for(unsigned n=0;n<8;++n)workers.emplace_back([&concurrent]{
        for(unsigned cycle=0;cycle<1000;++cycle){auto ticket=concurrent.acquire();if(!ticket)continue;
            assert(ticket->start()&&ticket->returned()&&ticket->complete());}
    });
    for(auto &worker:workers)worker.join();
    const auto stats=concurrent.stats();assert(stats.active==0&&stats.peak==1&&stats.admitted==stats.completed&&stats.admitted+stats.rejected==8000);
}
int main(){capacityCases();lifecycleCases();edgeCases();concurrentCases();configuredLimitCases();puts("VPN operation admission passed: eight pending slots across waiter timeout, two-phase completion/return, 100k lifecycles, unknown/dropped/throwing starters, stale tokens, identity exhaustion, owner lifetime, 80k concurrent operations, 1000 completion/return races and configurable zero/one/clamped limits with 8k contended single-slot attempts.");}
