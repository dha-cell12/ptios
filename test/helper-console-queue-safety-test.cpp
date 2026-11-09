#include "../shared/TLinkHelperConsoleQueue.h"
#include "../shared/TLinkConsoleLogBudget.h"
#include <cassert>
#include <functional>
#include <thread>
#include <vector>
#include <stdexcept>
#include <cstdio>
static std::atomic<unsigned> live{0},maximum{0};
struct Payload {
    std::shared_ptr<TLinkConsoleLogBudget> global,run;
    Payload(std::shared_ptr<TLinkConsoleLogBudget> g,std::shared_ptr<TLinkConsoleLogBudget> r):global(std::move(g)),run(std::move(r)){
        const unsigned now=++live;unsigned old=maximum.load();while(old<now&&!maximum.compare_exchange_weak(old,now)){}
    }
    ~Payload(){assert(global->snapshot().pending&&run->snapshot().pending);--live;}
};
struct Entry {
    std::shared_ptr<TLinkConsoleLogPermit> global,run;
    std::unique_ptr<Payload> payload;
    unsigned id;
    std::function<void()> retirement;
    Entry(std::shared_ptr<TLinkConsoleLogBudget> g,std::shared_ptr<TLinkConsoleLogBudget> r,unsigned value):id(value){
        run=TLinkConsoleLogPermit::acquire(r);if(!run)return;
        global=TLinkConsoleLogPermit::acquire(g);if(!global){run.reset();return;}
        payload.reset(new Payload(std::move(g),std::move(r)));
    }
    ~Entry(){if(retirement)retirement();}
};
using State=TLinkHelperConsoleQueue::State<Entry,4>;
static void lifecycleCases(){
    auto global=std::make_shared<TLinkConsoleLogBudget>(),run=std::make_shared<TLinkConsoleLogBudget>();
    for(unsigned n=0;n<100000;++n){
        State state;uint64_t token=0;
        for(unsigned j=0;j<4;++j){
            auto entry=std::make_shared<Entry>(global,run,j);assert(entry->payload);
            auto registration=state.insert(entry);assert(registration);
            if(j==0){assert(registration.schedule());token=registration.token();}else assert(!registration.schedule());
            registration.commit();
        }
        auto refused=std::make_shared<Entry>(global,run,9);{auto registration=state.insert(refused);assert(!registration);}refused.reset();
        assert(state.snapshot().pending==4&&global->snapshot().pending==4);
        assert(state.take(token+1).count==0&&state.abandon(token+1).count==0);
        if(n%2)state.close();
        auto batch=n%3?state.take(token):state.abandon(token);assert(batch.count==4);
        for(unsigned j=0;j<4;++j)assert(batch.entries[j]->id==j);
        auto retained=batch.entries[0];for(auto &entry:batch.entries){entry.reset();}assert(global->snapshot().pending==1);
        retained.reset();assert(global->snapshot().pending==0&&run->snapshot().pending==0&&live==0);
        state.take(token);assert(!state.snapshot().scheduled);
    }
    State edge(UINT64_MAX-1);auto value=std::make_shared<Entry>(global,run,1);
    {auto r=edge.insert(value);assert(r&&r.token()==UINT64_MAX);r.commit();}
    {auto batch=edge.take(UINT64_MAX);assert(batch.count==1);}edge.take(UINT64_MAX);value.reset();
    {auto r=edge.insert(std::make_shared<Entry>(global,run,2));assert(!r);}assert(!edge.snapshot().accepting&&global->snapshot().pending==0);
}
static void rollbackAndReentryCases(){
    auto global=std::make_shared<TLinkConsoleLogBudget>(),run=std::make_shared<TLinkConsoleLogBudget>();
    for(unsigned n=0;n<10000;++n){
        State state;bool retired=false;
        auto value=std::make_shared<Entry>(global,run,n);value->retirement=[&]{assert(state.snapshot().pending==0);retired=true;};
        try {auto r=state.insert(value);assert(r);value.reset();throw std::runtime_error("enqueue");}catch(const std::runtime_error &){}
        assert(retired&&global->snapshot().pending==0&&run->snapshot().pending==0&&!state.snapshot().scheduled);
        auto next=std::make_shared<Entry>(global,run,n);uint64_t token;
        {auto r=state.insert(next);token=r.token();r.commit();}next.reset();
        {auto batch=state.take(token);assert(batch.count==1);}state.take(token);
        {auto r=state.insert(std::make_shared<Entry>(global,run,n));assert(r&&r.token()!=token);r.commit();}
        assert(state.abandon(token).count==0&&state.snapshot().pending==1);
        {auto batch=state.abandon(state.snapshot().token);assert(batch.count==1);}
        assert(global->snapshot().pending==0&&run->snapshot().pending==0&&live==0);
    }
}
static void concurrentCases(){
    const unsigned total=8*10000;
    TLinkHelperConsoleQueue::State<Entry> state;
    auto global=std::make_shared<TLinkConsoleLogBudget>(),run=std::make_shared<TLinkConsoleLogBudget>();
    std::vector<std::atomic<unsigned>> seen(total);for(auto &value:seen)value=0;
    std::atomic<unsigned> consumed{0};
    std::thread consumer([&]{
        while(consumed<total){
            const auto status=state.snapshot();if(!status.scheduled){std::this_thread::yield();continue;}
            auto batch=state.take(status.token);
            for(size_t n=0;n<batch.count;++n){assert(seen[batch.entries[n]->id].fetch_add(1)==0);++consumed;}
        }
    });
    std::vector<std::thread> producers;
    for(unsigned worker=0;worker<8;++worker)producers.emplace_back([&,worker]{
        for(unsigned n=0;n<10000;++n){
            for(;;){
                auto entry=std::make_shared<Entry>(global,run,worker*10000+n);if(!entry->payload){std::this_thread::yield();continue;}
                auto registration=state.insert(entry);if(!registration){std::this_thread::yield();continue;}
                registration.commit();break;
            }
        }
    });
    for(auto &thread:producers){thread.join();}
    state.close();consumer.join();state.take(state.snapshot().token);
    for(auto &value:seen)assert(value==1);
    assert(consumed==total&&live==0&&maximum<=64&&global->snapshot().pending==0&&run->snapshot().pending==0&&!state.snapshot().scheduled);
}
int main(){lifecycleCases();rollbackAndReentryCases();concurrentCases();
    puts("Helper console queue passed: 100k FIFO/close/stale/held-payload transactions, UINT64_MAX fence, 10k rollback/reentry cycles and 80k concurrent exactly-once publications; global/run permits retire after payloads, zero final charges.");}
