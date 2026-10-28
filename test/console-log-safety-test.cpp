#include "../shared/TLinkConsoleLogBudget.h"
#include "../shared/TLinkConsoleLogBatch.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
int main(){
    static_assert(TLinkConsoleLogMaxPending*TLinkConsoleLogLineBytes==1024*1024,"pending payload bound changed");
    static_assert(TLinkConsoleLogMaxPending*TLinkConsoleLogEntryBytes==2*1024*1024,"disk/system reservation bound changed");
    static_assert((TLinkConsoleLogMessageUnits+12+TLinkConsoleLogLevelUnits)*sizeof(uint16_t)<=TLinkConsoleLogSystemBytes,"system snapshot prefixes exceed their reservation");
    auto budget=std::make_shared<TLinkConsoleLogBudget>();std::vector<std::shared_ptr<TLinkConsoleLogPermit>> held;
    for(size_t n=0;n<TLinkConsoleLogMaxPending;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);assert(permit);held.push_back(permit);}
    assert(!TLinkConsoleLogPermit::acquire(budget)&&budget->snapshot().pending==64&&budget->snapshot().dropped==1);
    held.front()->finish();held.front()->finish();auto replacement=TLinkConsoleLogPermit::acquire(budget);assert(replacement&&budget->snapshot().pending==64);
    held.front()->finish();assert(budget->snapshot().pending==64);held.clear();assert(budget->snapshot().pending==1);replacement.reset();assert(!budget->snapshot().pending);
    assert(!TLinkConsoleLogPermit::acquire(nullptr));
    budget=std::make_shared<TLinkConsoleLogBudget>();
    for(unsigned n=0;n<100000;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);assert(permit);budget->accepted(n%2!=0);if(n%3==0)budget->failed();if(n%7==0)budget->systemFailed();if(n%2)permit->finish();}
    auto stats=budget->snapshot();assert(stats.accepted==100000&&stats.truncated==50000&&stats.writeFailures==33334&&stats.systemFailures==14286&&stats.pending==0);
    budget=std::make_shared<TLinkConsoleLogBudget>();std::vector<std::thread> producers;
    for(unsigned t=0;t<8;++t)producers.emplace_back([budget]{for(unsigned n=0;n<10000;++n){auto permit=TLinkConsoleLogPermit::acquire(budget);if(permit){budget->accepted(false);budget->systemFailed();auto copy=permit;permit->finish();copy->finish();}}});
    for(auto &thread:producers)thread.join();stats=budget->snapshot();assert(stats.pending==0&&stats.accepted+stats.dropped==80000&&stats.systemFailures==stats.accepted&&stats.peakPending<=64);
    uint32_t seed=0x12345678;
    for(unsigned n=0;n<100000;++n){seed=seed*1664525+1013904223;const size_t length=seed%8192,limit=(seed>>16)%4097;
        std::vector<uint16_t> text(length,uint16_t('x'));if(length>limit&&limit){text[limit-1]=0xd800;text[limit]=n%2?0xdc00:uint16_t('x');}
        const auto count=TLinkConsoleLogPrefix(length,limit,[&text](size_t i){assert(i<text.size());return text[i];});
        size_t want=std::min(length,limit);if(want&&want<length&&text[want-1]>=0xd800&&text[want-1]<=0xdbff&&text[want]>=0xdc00&&text[want]<=0xdfff)--want;
        assert(count==want&&count<=limit&&count<=length);
    }
    const uint64_t threshold=512*1024;
    for(unsigned n=0;n<100000;++n){
        seed=seed*1664525+1013904223;
        const uint64_t initial=n%3==0?threshold:seed%(threshold+32768);
        const size_t total=1+(seed>>16)%64;
        std::vector<uint64_t> lengths(total);
        for(auto &length:lengths){seed=seed*1664525+1013904223;length=1+seed%TLinkConsoleLogLineBytes;}
        // Independent frozen per-line rotation oracle, then actual batch plans.
        std::vector<size_t> expected,actual;
        uint64_t bytes=initial;
        for(size_t i=0;i<total;++i){if(bytes>threshold){expected.clear();bytes=0;}expected.push_back(i);bytes+=lengths[i];}
        uint64_t batchedBytes=initial;
        for(size_t begin=0;begin<total;){
            const bool rotate=batchedBytes>threshold;
            const size_t count=rotate?1:TLinkConsoleLogBatchCount(batchedBytes,threshold,total-begin,[&lengths,begin](size_t i){return lengths[begin+i];});
            assert(count&&count<=total-begin);
            if(rotate){actual.clear();batchedBytes=0;}
            for(size_t i=0;i<count;++i){actual.push_back(begin+i);batchedBytes+=lengths[begin+i];}
            begin+=count;
        }
        assert(actual==expected&&batchedBytes==bytes);
        for(size_t begin=0;begin<total;++begin){const size_t count=total-begin;uint64_t mask=0;
            for(size_t i=begin;i<total;++i)mask|=uint64_t(1)<<i;
            assert(TLinkConsoleLogBatchMask(begin,count)==mask);
        }
    }
    assert(TLinkConsoleLogBatchMask(0,64)==UINT64_MAX&&TLinkConsoleLogBatchMask(64,1)==0&&TLinkConsoleLogBatchMask(0,0)==0);
    assert(TLinkConsoleLogBatchCount(UINT64_MAX-1,UINT64_MAX-1,2,[](size_t){return uint64_t(2);})==1);
    const std::vector<uint64_t> exact{1,1};
    assert(TLinkConsoleLogBatchCount(threshold,threshold,2,[&exact](size_t i){return exact[i];})==1);
    puts("Console log core passed: 64-entry/2-MiB disk+system reservations, failure counters, duplicate/stale release, 100k lifecycles, 8 x 10k concurrent admissions, 100k UTF16 boundaries and 100k exact rotation/mask plans; zero pending charges.");
}
