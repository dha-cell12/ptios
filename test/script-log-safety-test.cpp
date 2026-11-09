#include "../shared/TLinkScriptLogPolicy.h"
#include "../shared/TLinkConsoleLogBudget.h"
#include <array>
#include <deque>
#include <cassert>
#include <cstdio>
#include "production-log-batch-safety-fixture.inc"
int main(){
    ProductionLogBatchFixture::cases();
    TLinkScriptLogPolicy::Ring ring;std::array<uint64_t,200> slots{};std::deque<uint64_t> old;
    uint32_t state=0x391cef85;
    const auto next=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return state;};
    for(uint64_t n=0;n<100000;++n){
        if(next()%127==0){ring.clear();old.clear();}
        slots[ring.next()]=n;ring.appended();old.push_back(n);if(old.size()>200)old.pop_front();
        assert(ring.count()==old.size());
        for(size_t limit:{size_t(0),size_t(20),size_t(50),size_t(200),SIZE_MAX}){
            const size_t count=ring.tailCount(limit);assert(count==std::min(limit,old.size()));
            for(size_t i=0;i<count;++i)assert(slots[ring.tailIndex(limit,i)]==old[old.size()-count+i]);
        }
    }
    for(size_t boundary:{size_t(0),size_t(1),TLinkScriptLogPolicy::FileBytes-1,TLinkScriptLogPolicy::FileBytes,TLinkScriptLogPolicy::FileBytes+1}){
        for(uint64_t size:{uint64_t(0),uint64_t(1),uint64_t(1048575),uint64_t(1048576),UINT64_MAX}){
            const bool expected=boundary<=1048576&&(size>1048576||size+boundary>1048576);
            assert(TLinkScriptLogPolicy::NeedsReset(size,boundary)==expected);
        }
    }
    std::array<uint16_t,4098> text{};text.fill('x');text[4095]=0xd83d;text[4096]=0xde00;
    assert(TLinkConsoleLogPrefix(text.size(),size_t(4096),[&](size_t i){return text[i];})==4095);
    uint64_t counter=UINT64_MAX-1;TLinkScriptLogPolicy::Increment(counter);TLinkScriptLogPolicy::Increment(counter);assert(counter==UINT64_MAX);
    auto budget=std::make_shared<TLinkConsoleLogBudget>();
    std::array<std::shared_ptr<TLinkConsoleLogPermit>,64> held;
    for(auto &permit:held){permit=TLinkConsoleLogPermit::acquire(budget);assert(permit);}
    assert(!TLinkConsoleLogPermit::acquire(budget)&&budget->snapshot().pending==64);
    for(auto &permit:held){permit.reset();}
    assert(!budget->snapshot().pending);
    puts("Production log core passed: 100k independent FIFO/tail/clear oracles, 20/50/200 and SIZE_MAX tails, exact 1-MiB rotation arithmetic, UTF16 pair boundary, saturating counters and 64/65 admission with zero final charges.");
}
