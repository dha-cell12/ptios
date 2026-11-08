#include "../shared/TLinkHistoryRecoveryCompare.h"
#include <vector>
#include <stdexcept>
static void historyRecoveryCompareCases(){
    using namespace TLinkHistoryRecoveryCompare;
    uint32_t seed=0x793a12fU;
    for(unsigned cycle=0;cycle<100000;++cycle){
        seed=seed*1664525U+1013904223U;
        const size_t length=seed%1025,quantum=1+(seed%97);
        std::vector<uint8_t> expected(length),actual,storage;
        for(size_t n=0;n<length;++n)expected[n]=uint8_t(n+cycle);
        actual=expected;const bool different=length&&cycle%3;
        if(different)actual[seed%length]^=0x41;
        size_t offset=0,calls=0,allocations=0;bool interrupted=cycle%17==0;
        const Result result=Compare(expected.data(),length,[&](uint8_t *bytes,size_t count){
            ++calls;if(interrupted){interrupted=false;return Read(-1,EINTR);}
            const size_t got=count<quantum?count:quantum;
            std::memcpy(bytes,actual.data()+offset,got);offset+=got;return Read((std::ptrdiff_t)got);
        },[&](size_t size){++allocations;storage.resize(size);return storage.data();});
        assert(result==(different?Result::Different:Result::Exact)&&offset==length);
        assert(allocations==(different?1U:0U));
        if(different)assert(storage==actual);else assert(storage.empty());
        assert(length?calls>0:calls==0);
    }
    for(size_t mismatch:{size_t(0),size_t(65535),size_t(65536),size_t(131088)}){
        std::vector<uint8_t> expected(131089,7),actual=expected,storage;actual[mismatch]=9;
        size_t offset=0,allocations=0,calls=0;
        const Result result=Compare(expected.data(),expected.size(),[&](uint8_t *bytes,size_t count){
            ++calls;std::memcpy(bytes,actual.data()+offset,count);offset+=count;return Read((std::ptrdiff_t)count);
        },[&](size_t length){++allocations;storage.resize(length);return storage.data();});
        assert(result==Result::Different&&storage==actual&&calls==3&&allocations==1);
    }
    const uint8_t expected[]={1,2,3};size_t allocations=0;
    const auto allocate=[&](size_t)->uint8_t*{++allocations;return nullptr;};
    for(unsigned failure=0;failure<4;++failure){
        const Result result=Compare(expected,sizeof(expected),[&](uint8_t *,size_t count){
            if(failure==0)return Read(0);
            if(failure==1)return Read(-1,EIO);
            if(failure==2)return Read((std::ptrdiff_t)(count+1));
            return Read(-1);
        },allocate);
        assert(result==Result::ReadFailed&&allocations==0);
    }
    assert(Compare(nullptr,1,[](uint8_t*,size_t){return Read(0);},allocate)==Result::Invalid);
    assert(Compare(nullptr,0,[](uint8_t*,size_t){assert(false);return Read(0);},allocate)==Result::Exact);
    assert(Compare(expected,3,[](uint8_t *bytes,size_t count){std::memset(bytes,0,count);return Read((std::ptrdiff_t)count);},allocate)==Result::BufferFailed&&allocations==1);
    for(bool allocation:{false,true}){
        bool caught=false;
        try{Compare(expected,3,[&](uint8_t *bytes,size_t count){
            if(!allocation)throw std::runtime_error("read");
            std::memset(bytes,0,count);return Read((std::ptrdiff_t)count);
        },[](size_t)->uint8_t*{throw std::runtime_error("allocation");});}
        catch(const std::runtime_error &){caught=true;}
        assert(caught);
    }
    puts("History recovery compare passed: 100k independent exact/mismatch/short/EINTR cases, three-chunk prefix reconstruction, one lazy allocation, no full-buffer allocation for exact reads, EOF/error/over-return/nil allocation and provider unwind.");
}
