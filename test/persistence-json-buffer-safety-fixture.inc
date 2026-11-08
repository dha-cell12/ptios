#include "persistence-json-buffer-fixture.h"
#include <vector>
#include <limits>
#include <thread>
#include <array>
static void persistenceJSONBufferCases(){
    using namespace TLinkPersistenceJSONStorage;
    using PersistenceStorageFixture::Trace;
    uint32_t state=0x73429abc;
    for(unsigned cycle=0;cycle<100000;++cycle){
        state=state*1664525U+1013904223U;const size_t limit=state%2049;
        Trace trace;Buffer buffer(limit,trace.allocator());std::vector<uint8_t> expected;
        bool failed=false;
        for(unsigned step=0;step<16;++step){
            uint8_t bytes[257];for(size_t n=0;n<sizeof(bytes);++n)bytes[n]=uint8_t(n+cycle+step);
            state=state*1664525U+1013904223U;const size_t count=state%258;
            const bool accepted=!failed&&count<=limit-expected.size();
            const size_t requests=trace.requests;
            assert(buffer.append(bytes,count)==accepted);
            if(accepted)expected.insert(expected.end(),bytes,bytes+count);else{failed=true;assert(trace.requests==requests);}
            assert(buffer.size()==expected.size()&&buffer.size()<=buffer.capacity()&&buffer.capacity()<=limit&&trace.maximum<=limit);
            if(!expected.empty())assert(std::memcmp(buffer.data(),expected.data(),expected.size())==0);
        }
        assert(buffer.seal()==!failed);
        Buffer moved(std::move(buffer));assert(buffer.data()==nullptr&&buffer.capacity()==0);
        assert(moved.size()==expected.size()&&!moved.append(nullptr,0));
        Buffer replacement(8,trace.allocator());const uint8_t byte=7;assert(replacement.append(&byte,1));
        replacement=std::move(moved);assert(moved.data()==nullptr&&moved.capacity()==0);
        replacement.release();replacement.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    // Growth is capped for both real quotas; an exact append needs no rounding past the limit.
    for(size_t cap:{size_t(0),size_t(1),size_t(257),size_t(4U*1024U*1024U),size_t(32U*1024U*1024U)}){
        Trace trace;Buffer buffer(cap,trace.allocator());std::vector<uint8_t> bytes(cap,0x71);
        assert(buffer.append(bytes.data(),cap)&&buffer.size()==cap&&buffer.capacity()==cap&&trace.maximum<=cap);
        const size_t requests=trace.requests;const uint8_t extra=1;
        assert(!buffer.append(&extra,1)&&trace.requests==requests&&buffer.size()==cap);
        buffer.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    for(size_t failedRequest:{size_t(1),size_t(2)}){
        Trace trace;trace.failRequest=failedRequest;Buffer buffer(1024,trace.allocator());uint8_t bytes[257]={};
        if(failedRequest==2)assert(buffer.append(bytes,1));
        const size_t size=buffer.size(),capacity=buffer.capacity();const uint8_t *pointer=buffer.data();
        assert(!buffer.append(bytes,sizeof(bytes))&&buffer.error()==Error::Allocation);
        assert(buffer.data()==pointer&&buffer.size()==size&&buffer.capacity()==capacity&&!buffer.append(bytes,0)&&!buffer.seal());
        buffer.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;Buffer buffer(1024,trace.allocator());uint8_t bytes[257]={};assert(buffer.append(bytes,1));
        const uint8_t *pointer=buffer.data();trace.throwNext=true;bool caught=false;
        try{buffer.append(bytes,sizeof(bytes));}catch(const std::runtime_error &){caught=true;}
        assert(caught&&buffer.data()==pointer&&buffer.size()==1&&buffer.capacity()==256);
        assert(buffer.append(bytes,sizeof(bytes)));buffer.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;Buffer buffer(16,trace.allocator());assert(!buffer.append(nullptr,1)&&buffer.error()==Error::Invalid&&trace.requests==0);
        Buffer huge(16,trace.allocator());const uint8_t byte=0;
        assert(!huge.append(&byte,std::numeric_limits<size_t>::max())&&huge.error()==Error::Limit&&trace.requests==0);
        Buffer invalid(16,Allocator(nullptr,nullptr,nullptr));assert(!invalid.append(&byte,1)&&invalid.error()==Error::Invalid);
    }
    {
        Trace trace;trace.failRequest=1;const size_t limit=std::numeric_limits<size_t>::max();
        Buffer maximum(limit,trace.allocator());const uint8_t byte=0;
        assert(!maximum.append(&byte,limit)&&maximum.error()==Error::Allocation);
        assert(trace.requests==1&&trace.maximum==limit&&maximum.size()==0&&maximum.capacity()==0);
    }
    std::array<std::thread,8> workers;
    for(auto &worker:workers)worker=std::thread([]{
        Trace trace;const uint8_t bytes[]={'[',']'};
        for(unsigned cycle=0;cycle<10000;++cycle){Buffer buffer(4096,trace.allocator());assert(buffer.append(bytes,sizeof(bytes))&&buffer.seal());buffer.release();assert(trace.blocks.empty());}
        assert(trace.allocations==trace.frees);
    });
    for(auto &worker:workers)worker.join();
    puts("Persistence JSON storage passed: 100k independent chunk/content/capacity oracles, exact 4/32-MiB limits, sticky allocation/limit failures, moving allocators, move/replace/seal/release, provider unwind and 8 x 10k isolated owners; zero final blocks.");
}
