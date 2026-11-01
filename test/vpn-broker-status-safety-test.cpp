#include "../shared/TLinkVPNBrokerStatus.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <thread>
using Callback=std::function<void()>;
using Owner=TLinkVPNBrokerStatus<Callback>;
static void deliver(const Owner::Join &joined){auto callbacks=joined.take();for(auto &callback:callbacks){callback();}}
static void lifecycleCases(){
    Owner owner;unsigned calls=0;
    for(unsigned n=0;n<100000;++n){
        auto first=owner.join([&calls]{++calls;},100);assert(first&&first.leader());
        auto second=owner.join([&calls]{++calls;},101);assert(second&&!second.leader()&&second.take().empty());
        auto callbacks=first.take();assert(callbacks.size()==2);for(auto &callback:callbacks){callback();}
        assert(first.take().empty());
    }
    assert(calls==200000);
    std::vector<Owner::Join> held;
    for(unsigned n=0;n<8;++n){held.push_back(owner.join([&calls]{++calls;},100));assert(held.back()&&held.back().leader()==(n==0));}
    assert(!owner.join([]{},100));deliver(held[0]);assert(calls==200008);
    auto fresh=owner.join([]{},100);assert(fresh.leader());held[0].detach();
    auto follower=owner.join([]{},100);assert(!follower.leader());assert(fresh.take().size()==2);
}
static void boundaryCases(){
    Owner owner;assert(!owner.join([]{},UINT64_MAX));
    auto first=owner.join([]{},1000);assert(first.leader());
    assert(!owner.join([]{},999));auto near=owner.join([]{},8999);assert(near&&!near.leader());
    auto expired=owner.join([]{},9000);assert(expired.leader());assert(first.take().size()==2);
    auto later=owner.join([]{},9001);assert(!later.leader());first.detach();assert(expired.take().size()==2);
    auto edge=owner.join([]{},UINT64_MAX-5000);assert(edge.leader());assert(!owner.join([]{},UINT64_MAX));
    assert(!owner.join([]{},UINT64_MAX-1).leader());assert(edge.take().size()==2);
    auto beforeMutation=owner.join([]{},100);owner.invalidate();auto duringMutation=owner.join([]{},101);
    assert(duringMutation.leader());owner.invalidate();auto afterMutation=owner.join([]{},102);assert(afterMutation.leader());
    deliver(beforeMutation);deliver(duringMutation);auto joined=owner.join([]{},103);assert(!joined.leader());assert(afterMutation.take().size()==2);
    auto throwing=owner.join([]{},100);throwing.detach();auto retry=owner.join([]{},100);assert(retry.leader());
    deliver(throwing);assert(!owner.join([]{},100).leader());assert(retry.take().size()==2);
}
struct Reenter {std::function<void()> action;~Reenter(){action();}};
static void ownershipCases(){
    Owner::Join held;unsigned calls=0;
    {Owner owner;held=owner.join([&calls]{++calls;},100);}
    deliver(held);assert(calls==1);
    Owner owner;bool released=false;
    auto marker=std::make_shared<Reenter>();marker->action=[&]{released=true;owner.invalidate();};
    auto first=owner.join([marker]{},100);marker.reset();owner.invalidate();assert(!released);first=Owner::Join{};assert(released);
    released=false;marker=std::make_shared<Reenter>();marker->action=[&]{released=true;owner.invalidate();};
    first=owner.join([marker]{},100);marker.reset();auto callbacks=first.take();callbacks.clear();assert(released);
    for(unsigned n=0;n<8;++n)assert(owner.join([]{},100));
    marker=std::make_shared<Reenter>();marker->action=[&]{released=true;owner.invalidate();};released=false;
    {
        Callback rejected=[marker]{};marker.reset();
        auto denied=owner.join(std::move(rejected),100);assert(!denied);
    }
    // Check after the call expression and moved-from callback have both ended.
    // Parameter destruction timing and moved-from function state vary by implementation.
    assert(released);
}
static void concurrentCases(){
    for(unsigned cycle=0;cycle<256;++cycle){
        Owner owner;std::atomic<unsigned> leaders{0},calls{0};std::vector<Owner::Join> joined(8);std::vector<std::thread> threads;
        for(unsigned n=0;n<8;++n)threads.emplace_back([&owner,&joined,&leaders,&calls,n]{joined[n]=owner.join([&calls]{++calls;},100);assert(joined[n]);if(joined[n].leader())++leaders;});
        for(auto &thread:threads){thread.join();}
        assert(leaders==1);
        Owner::Join leader;for(auto &entry:joined){if(entry.leader())leader=entry;}
        std::thread finish([leader]{deliver(leader);}),duplicate([leader]{deliver(leader);}),invalidate([&owner]{owner.invalidate();});
        finish.join();duplicate.join();invalidate.join();assert(calls==8);
        auto next=owner.join([]{},100);assert(next.leader());leader.detach();assert(!owner.join([]{},100).leader());assert(next.take().size()==2);
    }
}
int main(){lifecycleCases();boundaryCases();ownershipCases();concurrentCases();puts("VPN status core passed: 100k pending-only flights, eight waiters/ninth refusal, eight-second non-renewing join windows, clock/identity/mutation/unwind fences, release outside locks, owner lifetime and 256 concurrent eight-reader/duplicate/invalidation races.");}
