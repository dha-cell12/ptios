#pragma once
#include "TLinkConsoleLogBudget.h"
#include <array>
#include <cerrno>

namespace TLinkConsoleLogVectorIO {
static const size_t MaxVectors=TLinkConsoleLogMaxPending;
static const size_t MaxBytes=MaxVectors*TLinkConsoleLogLineBytes;
struct Span {
    const uint8_t *bytes;size_t length;
    Span(const uint8_t *value=nullptr,size_t count=0):bytes(value),length(count){}
};
struct Result {size_t bytes=0;int error=0;bool zeroWrite=false;};
inline size_t VectorLimit(int64_t systemLimit){return systemLimit<=0?1:(systemLimit>=int64_t(MaxVectors)?MaxVectors:size_t(systemLimit));}
inline int Validate(const Span *spans,size_t count,size_t &total){
    total=0;
    if(count>MaxVectors)return EINVAL;
    if(count&&!spans)return EFAULT;
    for(size_t n=0;n<count;++n){
        if(spans[n].length&&!spans[n].bytes)return EFAULT;
        if(spans[n].length>MaxBytes-total)return EFBIG;
        total+=spans[n].length;
    }
    return 0;
}
// A positive short write advances the cursor across complete and partial
// spans. Only an unacknowledged EINTR repeats the same suffix. Errors never
// cause an acknowledged prefix or the complete group to be replayed.
template<class Write>
Result WriteAll(const Span *spans,size_t count,size_t vectorLimit,Write write){
    Result result;size_t total=0;
    result.error=Validate(spans,count,total);if(result.error)return result;
    vectorLimit=std::max(size_t(1),std::min(vectorLimit,MaxVectors));
    size_t index=0,offset=0;
    while(result.bytes<total){
        std::array<Span,MaxVectors> suffix{};size_t used=0,offered=0;
        for(size_t n=index;n<count&&used<vectorLimit;++n){
            const size_t begin=n==index?offset:0,length=spans[n].length-begin;
            if(!length)continue;
            suffix[used++]=Span(spans[n].bytes+begin,length);offered+=length;
        }
        errno=0;const int64_t wrote=write(suffix.data(),used);
        if(wrote<0){if(errno==EINTR)continue;result.error=errno?errno:EIO;return result;}
        if(!wrote){result.zeroWrite=true;return result;}
        if(uint64_t(wrote)>offered){result.error=EIO;return result;}
        size_t remaining=size_t(wrote);result.bytes+=remaining;
        while(index<count){
            const size_t available=spans[index].length-offset;
            const size_t consumed=std::min(available,remaining);
            remaining-=consumed;offset+=consumed;
            if(offset==spans[index].length){++index;offset=0;}
            else break;
            if(!remaining)break;
        }
    }
    return result;
}
}
