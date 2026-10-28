#include "../shared/TLinkConsoleLogBudget.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
int main(){
    static_assert(TLinkConsoleLogMaxPending*TLinkConsoleLogLineBytes==1024*1024,"pending payload bound changed");
    auto budget=std::make_shared<TLinkConsoleLogBudget>();std::vector<std::shared_ptr<TLinkConsoleLogPermit>> held;
    for(size_t n=0;n<TLinkConsoleLogMaxPending;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);assert(permit);held.push_back(permit);}
    assert(!TLinkConsoleLogPermit::acquire(budget)&&budget->snapshot().pending==64&&budget->snapshot().dropped==1);
    held.front()->finish();held.front()->finish();auto replacement=TLinkConsoleLogPermit::acquire(budget);assert(replacement&&budget->snapshot().pending==64);
    held.front()->finish();assert(budget->snapshot().pending==64);held.clear();assert(budget->snapshot().pending==1);replacement.reset();assert(!budget->snapshot().pending);
    assert(!TLinkConsoleLogPermit::acquire(nullptr));
    budget=std::make_shared<TLinkConsoleLogBudget>();
    for(unsigned n=0;n<100000;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);assert(permit);budget->accepted(n%2!=0);if(n%3==0)budget->failed();if(n%2)permit->finish();}
    auto stats=budget->snapshot();assert(stats.accepted==100000&&stats.truncated==50000&&stats.writeFailures==33334&&stats.pending==0);
    budget=std::make_shared<TLinkConsoleLogBudget>();std::vector<std::thread> producers;
    for(unsigned t=0;t<8;++t)producers.emplace_back([budget]{for(unsigned n=0;n<10000;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);if(permit){budget->accepted(false);auto copy=permit;permit->finish();copy->finish();}}});
    for(auto &thread:producers)thread.join();stats=budget->snapshot();assert(stats.pending==0&&stats.accepted+stats.dropped==80000&&stats.peakPending<=64);
    uint32_t seed=0x12345678;
    for(unsigned n=0;n<100000;++n){seed=seed*1664525+1013904223;const size_t length=seed%8192,limit=(seed>>16)%4097;
        std::vector<uint16_t> text(length,uint16_t('x'));if(length>limit&&limit){text[limit-1]=0xd800;text[limit]=n%2?0xdc00:uint16_t('x');}
        const auto count=TLinkConsoleLogPrefix(length,limit,[&text](size_t i){assert(i<text.size());return text[i];});
        size_t want=std::min(length,limit);if(want&&want<length&&text[want-1]>=0xd800&&text[want-1]<=0xdbff&&text[want]>=0xdc00&&text[want]<=0xdfff)--want;
        assert(count==want&&count<=limit&&count<=length);
    }
    puts("Console log core passed: 64-entry/1-MiB reservations, duplicate/stale release, 100k lifecycles, 8 x 10k concurrent admissions and 100k UTF16 prefix boundaries; zero pending charges.");
}
