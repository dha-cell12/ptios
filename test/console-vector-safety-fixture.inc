#include "../shared/TLinkConsoleLogVectorIO.h"
#include <stdexcept>
static void consoleVectorCases(){
    using namespace TLinkConsoleLogVectorIO;
    assert(VectorLimit(-1)==1&&VectorLimit(0)==1&&VectorLimit(1)==1&&VectorLimit(INT64_MAX)==64);
    uint32_t random=0xabc123;
    for(unsigned trial=0;trial<100000;++trial){
        random=random*1664525+1013904223;
        const size_t count=random%65,limit=1+(random>>8)%64;
        std::vector<std::vector<uint8_t>> storage(count);
        std::vector<Span> spans;std::vector<uint8_t> expected,actual;
        for(size_t n=0;n<count;++n){
            const size_t length=(random+n*13)%37;
            storage[n].resize(length);
            for(size_t j=0;j<length;++j)storage[n][j]=uint8_t(trial+n+j);
            spans.emplace_back(storage[n].data(),length);
            expected.insert(expected.end(),storage[n].begin(),storage[n].end());
        }
        unsigned calls=0;
        const auto result=WriteAll(spans.data(),spans.size(),limit,[&](const Span *parts,size_t used)->int64_t{
            assert(used>0&&used<=limit);++calls;
            if(calls%7==1){errno=EINTR;return -1;}
            size_t offered=0;for(size_t n=0;n<used;++n)offered+=parts[n].length;
            const size_t written=std::min(offered,size_t(1+(trial+calls)%83));
            size_t left=written;
            for(size_t n=0;n<used&&left;++n){const size_t bytes=std::min(left,parts[n].length);actual.insert(actual.end(),parts[n].bytes,parts[n].bytes+bytes);left-=bytes;}
            assert(!left);return int64_t(written);
        });
        assert(!result.error&&!result.zeroWrite&&result.bytes==expected.size()&&actual==expected);
    }
    std::vector<uint8_t> payload(MaxBytes,42);
    Span span(payload.data(),payload.size());unsigned calls=0;
    auto whole=[&calls](const Span *parts,size_t count)->int64_t{++calls;size_t bytes=0;for(size_t n=0;n<count;++n)bytes+=parts[n].length;return int64_t(bytes);};
    assert(WriteAll(&span,1,64,whole).bytes==MaxBytes&&calls==1);
    Span oversized(payload.data(),MaxBytes+1);calls=0;
    assert(WriteAll(&oversized,1,64,whole).error==EFBIG&&calls==0);
    Span overflow[]={span,Span(payload.data(),SIZE_MAX)};
    assert(WriteAll(overflow,2,64,whole).error==EFBIG&&calls==0);
    assert(WriteAll(nullptr,1,64,whole).error==EFAULT&&calls==0);
    assert(WriteAll(&span,65,64,whole).error==EINVAL&&calls==0);
    Span bad(nullptr,1);assert(WriteAll(&bad,1,64,whole).error==EFAULT&&calls==0);
    assert(WriteAll(nullptr,0,0,whole).bytes==0&&calls==0);
    for(int fault:{0,EIO,EAGAIN}){
        calls=0;
        auto result=WriteAll(&span,1,0,[&](const Span *parts,size_t count)->int64_t{
            assert(count==1);++calls;
            if(calls==1){assert(parts[0].bytes==payload.data());return 17;}
            assert(parts[0].bytes==payload.data()+17&&parts[0].length==payload.size()-17);
            errno=fault;return fault?-1:0;
        });
        assert(calls==2&&result.bytes==17&&result.error==fault&&result.zeroWrite==(fault==0));
    }
    auto result=WriteAll(&span,1,64,[](const Span *,size_t)->int64_t{return int64_t(MaxBytes+1);});
    assert(result.error==EIO&&!result.bytes);
    result=WriteAll(&span,1,64,[](const Span *,size_t)->int64_t{return -1;});
    assert(result.error==EIO&&!result.bytes);
    bool caught=false;
    try{WriteAll(&span,1,64,[](const Span *,size_t)->int64_t{throw std::runtime_error("provider");});}catch(const std::runtime_error &){caught=true;}
    assert(caught);
    puts("Console vector core passed: 100k concatenation/partial/EINTR oracles, 1..64 vectors, empty spans, 1-MiB bounds, invalid/overflow plans, zero/EIO/EAGAIN, over-return and provider unwind without prefix replay.");
}
