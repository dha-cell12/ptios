#include "../shared/TLinkProductionLogBatch.h"
#include <string>
#include <thread>
#include <stdexcept>
namespace ProductionLogBatchFixture {
static void plans(){
    uint32_t state=0x251cd19a;
    const auto random=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(unsigned n=0;n<100000;++n){
        const size_t limit=1+random()%257,count=random()%65;
        std::vector<std::string> rows;for(size_t i=0;i<count;++i)rows.emplace_back(random()%(limit+1),char('a'+i%26));
        std::string old(random()%(limit*2+1),'x'),now=old;
        for(const auto &row:rows){if(old.size()>limit||row.size()>limit-old.size())old.clear();old+=row;}
        size_t begin=0;
        while(begin<count){
            auto plan=TLinkProductionLogBatch::Plan(now.size(),limit,count-begin,[&](size_t i){return rows[begin+i].size();});
            assert(plan.count&&plan.count<=count-begin&&plan.bytes<=limit);
            if(plan.reset)now.clear();
            const size_t before=now.size();
            for(size_t i=0;i<plan.count;++i)now+=rows[begin+i];
            assert(now.size()==before+plan.bytes&&now.size()<=limit);begin+=plan.count;
        }
        assert(old==now);
    }
    for(uint64_t size:{uint64_t(0),uint64_t(1048576),UINT64_MAX}){
        auto plan=TLinkProductionLogBatch::Plan(size,size_t(1048576),size_t(2),[](size_t){return size_t(524288);});
        assert(plan.count==2&&plan.bytes==1048576&&plan.reset==(size!=0));
    }
    auto invalid=TLinkProductionLogBatch::Plan(0,1,1,[](size_t){return SIZE_MAX;});assert(!invalid.count);
}
struct Item {
    std::shared_ptr<TLinkConsoleLogPermit> permit;
    uint64_t value;
    explicit Item(uint64_t v,std::shared_ptr<TLinkConsoleLogPermit> p=nullptr):permit(std::move(p)),value(v){}
};
static void owners(){
    auto budget=std::make_shared<TLinkConsoleLogBudget>();TLinkProductionLogBatch::Registry<Item,64> queue;
    std::array<std::shared_ptr<Item>,64> blocks{};
    for(size_t i=0;i<blocks.size();++i){
        blocks[i]=std::make_shared<Item>(i,TLinkConsoleLogPermit::acquire(budget));auto token=queue.insert(blocks[i]);assert(token);token.commit();
    }
    assert(budget->snapshot().pending==64);auto extra=std::make_shared<Item>(100);
    {auto rejected=queue.insert(extra);assert(!rejected);}
    for(size_t i=0;i<blocks.size();i+=2)blocks[i].reset();
    auto batch=queue.take();assert(batch.count==32&&budget->snapshot().pending==32);
    for(size_t i=0;i<batch.count;++i)assert(batch.entries[i]->value==i*2+1);
    for(auto &block:blocks){block.reset();}
    assert(budget->snapshot().pending==32);
    for(auto &entry:batch.entries){entry.reset();}
    assert(!budget->snapshot().pending&&queue.take().count==0);
    for(unsigned n=0;n<10000;++n){
        auto item=std::make_shared<Item>(n,TLinkConsoleLogPermit::acquire(budget));
        try{auto rollback=queue.insert(item);assert(rollback);throw std::runtime_error("registration");}catch(const std::runtime_error &){}
        assert(queue.take().count==0);item.reset();assert(!budget->snapshot().pending);
    }
    TLinkProductionLogBatch::Registry<Item,64> concurrent;std::array<std::atomic<unsigned>,8000> seen;
    for(auto &count:seen)count.store(0);
    std::vector<std::thread> producers;
    for(unsigned t=0;t<8;++t){producers.emplace_back([&concurrent,&seen,t]{
        for(unsigned n=0;n<1000;++n){
            auto item=std::make_shared<Item>(t*1000+n);auto token=concurrent.insert(item);assert(token);token.commit();
            auto result=concurrent.take();for(size_t i=0;i<result.count;++i)assert(seen[result.entries[i]->value].fetch_add(1)==0);
        }
    });}
    for(auto &producer:producers)producer.join();
    for(auto &count:seen)assert(count.load()==1);
    assert(concurrent.take().count==0);
}
static void cases(){plans();owners();puts("Production log batch core passed: 100k independent sequential rotation/file-content plans, exact 1-MiB/SIZE_MAX limits, 64-entry weak registry/discard/held-reader accounting, 10k registration unwinds and 8k concurrent exactly-once drains.");}
}
