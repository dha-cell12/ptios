#include "../shared/TLinkConsoleDrainSchedule.h"
#include <cassert>
#include <cstdio>
#include <mutex>
#include <thread>
#include <vector>
#include <atomic>
static void lifecycleCases(){
    TLinkConsoleDrainSchedule schedule;
    uint64_t previous=0;
    for(unsigned n=0;n<100000;++n){
        auto first=schedule.prepare();assert(first&&first.starts&&first.token>previous&&schedule.matches(first.token));
        const auto joined=schedule.prepare();assert(joined&&!joined.starts&&joined.token==first.token);
        schedule.rollback(joined);assert(schedule.matches(first.token));
        if(n%2)schedule.rollback(first);else assert(schedule.retire(first.token));
        assert(schedule.current()==0&&!schedule.retire(first.token));
        const auto next=schedule.prepare();assert(next.starts&&next.token>first.token);
        schedule.rollback(first);assert(schedule.matches(next.token)&&!schedule.retire(first.token));
        assert(schedule.retire(next.token));previous=next.token;
    }
    TLinkConsoleDrainSchedule edge(UINT64_MAX-1);auto last=edge.prepare();assert(last&&last.starts&&last.token==UINT64_MAX);
    const auto join=edge.prepare();assert(join&&!join.starts);edge.rollback(join);assert(edge.matches(last.token));
    assert(edge.retire(last.token));assert(!edge.prepare()&&edge.current()==0);
    TLinkConsoleDrainSchedule rollbackEdge(UINT64_MAX-1);auto rolled=rollbackEdge.prepare();rollbackEdge.rollback(rolled);assert(!rollbackEdge.prepare());
}
static void concurrentCases(){
    TLinkConsoleDrainSchedule schedule;std::mutex mutex;
    std::vector<unsigned> pending;std::vector<unsigned> seen(80000,0);
    std::atomic<unsigned> accepted{0},consumed{0},completed{0};
    std::thread consumer([&]{
        while(completed<8||consumed<accepted){
            std::vector<unsigned> batch;
            {std::lock_guard<std::mutex> lock(mutex);const auto token=schedule.current();
                if(token){if(pending.empty())schedule.retire(token);else batch.swap(pending);}}
            for(unsigned id:batch){assert(seen[id]++==0);++consumed;}
            if(batch.empty())std::this_thread::yield();
        }
    });
    std::vector<std::thread> producers;
    for(unsigned worker=0;worker<8;++worker)producers.emplace_back([&,worker]{
        for(unsigned n=0;n<10000;++n){
            for(;;){
                std::lock_guard<std::mutex> lock(mutex);if(pending.size()==64)continue;
                const auto lease=schedule.prepare();assert(lease);
                pending.push_back(worker*10000+n);++accepted;break;
            }
        }
        ++completed;
    });
    for(auto &producer:producers){producer.join();}consumer.join();
    {std::lock_guard<std::mutex> lock(mutex);assert(pending.empty());schedule.retire(schedule.current());}
    assert(accepted==80000&&consumed==80000&&schedule.current()==0);
    for(unsigned value:seen)assert(value==1);
}
int main(){lifecycleCases();concurrentCases();puts("Root console schedule passed: 100k joins/rollback/retire/stale-job transactions, UINT64_MAX no-wrap fences and 80k concurrent exactly-once publications using the production token planner.");}
