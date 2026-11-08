#include "persistence-json-buffer-fixture.h"
#include <vector>
static void ownedReadBufferCases(){
    using namespace TLinkPersistenceJSONStorage;
    using PersistenceStorageFixture::Trace;
    uint32_t state=0x49a2b671;
    for(unsigned cycle=0;cycle<100000;++cycle){
        state=state*1664525U+1013904223U;const size_t length=state%2049;
        Trace trace;Buffer buffer(length,trace.allocator());std::vector<uint8_t> expected(length);
        assert(buffer.reserveForRead(length)&&buffer.size()==0&&buffer.capacity()==length);
        assert(trace.requests==(length?1U:0U));
        if(length)assert(buffer.writableData()[0]==0xa5&&buffer.writableData()[length-1]==0xa5);
        size_t offset=0;
        while(offset<length){
            state=state*1664525U+1013904223U;const size_t step=1+state%127;
            const size_t count=step<length-offset?step:length-offset;
            for(size_t n=0;n<count;++n)expected[offset+n]=uint8_t(offset+n+cycle);
            std::memcpy(buffer.writableData()+offset,expected.data()+offset,count);
            assert(buffer.commitRead(count));offset+=count;
            assert(buffer.size()==offset&&std::memcmp(buffer.data(),expected.data(),offset)==0);
        }
        assert(buffer.seal()&&!buffer.writableData()&&!buffer.commitRead(0));
        Buffer owner(std::move(buffer));assert(buffer.data()==nullptr&&owner.size()==length);
        owner.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    for(size_t length:{size_t(0),size_t(1),size_t(65537),size_t(4U*1024U*1024U),size_t(32U*1024U*1024U)}){
        Trace trace;Buffer buffer(length,trace.allocator());assert(buffer.reserveForRead(length));
        assert(buffer.capacity()==length&&buffer.size()==0&&trace.maximum<=length);
        assert(buffer.commitRead(length)&&!buffer.commitRead(1)&&buffer.size()==length&&!buffer.seal());
        buffer.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;trace.failRequest=1;Buffer buffer(128,trace.allocator());
        assert(!buffer.reserveForRead(128)&&buffer.error()==Error::Allocation&&!buffer.commitRead(1)&&!buffer.writableData());
        assert(trace.blocks.empty());
    }
    {
        Trace trace;Buffer buffer(64,trace.allocator());trace.throwNext=true;bool caught=false;
        try{buffer.reserveForRead(64);}catch(const std::runtime_error &){caught=true;}
        assert(caught&&buffer.size()==0&&buffer.capacity()==0&&buffer.reserveForRead(64));
        assert(buffer.commitRead(64));buffer.release();assert(trace.blocks.empty()&&trace.allocations==trace.frees);
    }
    {
        Trace trace;Buffer buffer(16,trace.allocator());assert(!buffer.reserveForRead(17)&&trace.requests==0);
        Buffer invalid(16,Allocator(nullptr,nullptr,nullptr));assert(!invalid.reserveForRead(16));
        Buffer partial(16,trace.allocator());assert(partial.reserveForRead(16)&&partial.commitRead(4));
        assert(!partial.reserveForRead(16)&&partial.size()==4);partial.release();assert(trace.blocks.empty());
    }
    puts("Owned read storage passed: 100k poisoned-memory direct-fill/content/commit oracles, exact empty/64-KiB/4-MiB/32-MiB capacity, reserve/commit overflow, partial/move/seal, allocation refusal and provider unwind; zero final blocks.");
}
