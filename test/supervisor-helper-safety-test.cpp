#include "../shared/TLinkSupervisorHelper.h"
#include <cassert>
#include <cstdio>
#include <memory>
#include <thread>
#include <vector>
using namespace TLinkSupervisorHelper;
int main(){
    assert(!busy());
    {
        auto lease=std::make_shared<Lease>();assert(lease->held()&&busy());
        std::shared_ptr<void> childState=lease;lease.reset();
        {Lease blocked;assert(!blocked.held()&&busy());}
        childState.reset();assert(!busy());
    }
    std::atomic<unsigned> active{0},successes{0};
    std::vector<std::thread> workers;
    for(unsigned n=0;n<8;++n)workers.emplace_back([&]{
        for(unsigned cycle=0;cycle<10000;++cycle){
            Lease lease;
            if(lease.held()){assert(active.fetch_add(1)==0);++successes;assert(active.fetch_sub(1)==1);}
        }
    });
    for(auto &worker:workers)worker.join();
    assert(!busy()&&active==0&&successes>0);
    puts("Supervisor helper core passed: retained child-lifetime lane, failed admission cannot clear another owner, 80k concurrent leases and zero final charges.");
}
