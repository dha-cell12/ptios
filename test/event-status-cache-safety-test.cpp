#include "../shared/TLinkEventStatusCache.h"
#include <cassert>
#include <cstdio>
#include <vector>
#include <thread>
#include <atomic>
#include <new>
static unsigned allocationFault=0,allocations=0;
static TLinkEventStatusCache::Bytes allocate(std::size_t size){
    ++allocations;if(allocationFault==1)return {};if(allocationFault==2)throw std::bad_alloc();
    return TLinkEventStatusCache::NewBytes(size);
}
static void basicCases(){
    TLinkEventStatusCache cache(256,allocate);uint64_t value=99;
    assert(!cache.lookup(nullptr,0,value)&&value==99);
    for(unsigned n=0;n<100000;++n){
        std::vector<uint8_t> bytes(1+n%256);for(size_t j=0;j<bytes.size();++j)bytes[j]=uint8_t(n+j);
        const auto original=bytes;assert(cache.store(bytes.data(),bytes.size(),n));
        const unsigned before=allocations;
        for(unsigned hit=0;hit<3;++hit){assert(cache.lookup(bytes.data(),bytes.size(),value)&&value==n);}
        assert(allocations==before&&cache.retainedBytes()==bytes.size());
        bytes.back()^=1;assert(!cache.lookup(bytes.data(),bytes.size(),value));
        assert(cache.lookup(original.data(),original.size(),value)&&value==n);
        if(n%2)cache.clear();else assert(!cache.store(nullptr,bytes.size(),n));
        assert(cache.retainedBytes()==0&&!cache.lookup(original.data(),original.size(),value));
    }
    const uint8_t bytes[]={1,2,3};
    for(unsigned fault=1;fault<=2;++fault){
        assert(cache.store(bytes,sizeof(bytes),UINT64_MAX));allocationFault=fault;
        assert(!cache.store(bytes,sizeof(bytes),0));allocationFault=0;
        assert(cache.retainedBytes()==0&&!cache.lookup(bytes,sizeof(bytes),value));
        assert(cache.store(bytes,sizeof(bytes),0)&&cache.lookup(bytes,sizeof(bytes),value)&&value==0);
    }
    TLinkEventStatusCache bounded;std::vector<uint8_t> exact(TLinkEventStatusCache::Limit,7);
    assert(bounded.store(exact.data(),exact.size(),UINT64_MAX)&&bounded.lookup(exact.data(),exact.size(),value)&&value==UINT64_MAX);
    exact.push_back(7);assert(!bounded.store(exact.data(),exact.size(),1)&&bounded.retainedBytes()==0);
    TLinkEventStatusCache zero(0);assert(!zero.store(bytes,sizeof(bytes),1));
    assert(!cache.store(bytes,SIZE_MAX,1)&&cache.retainedBytes()==0);
}
static void concurrentCases(){
    TLinkEventStatusCache cache;std::atomic<unsigned> hits{0};std::vector<std::thread> workers;
    for(unsigned thread=0;thread<8;++thread)workers.emplace_back([&,thread]{
        for(uint64_t n=0;n<10000;++n){
            const uint64_t key=(uint64_t(thread)<<32)|n;
            uint8_t bytes[8];for(unsigned j=0;j<8;++j)bytes[j]=uint8_t(key>>(8*j));
            assert(cache.store(bytes,sizeof(bytes),key));uint64_t value=0;
            if(cache.lookup(bytes,sizeof(bytes),value)){assert(value==key);++hits;}
            if(n%31==0)cache.clear();
        }
    });
    for(auto &worker:workers){worker.join();}cache.clear();assert(cache.retainedBytes()==0);
    // Contention may replace a memo before lookup; it must never return another key's value.
    (void)hits;
}
int main(){basicCases();concurrentCases();puts("Event status memo passed: 100k exact-byte/mutation/clear oracles, 300k allocation-free hits, zero/UINT64_MAX and 2-MiB boundaries, allocation refusal/unwind and 80k concurrent stores with no false-key hits.");}
