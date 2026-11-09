#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
namespace TLinkScriptLogPolicy {
static const std::size_t Entries=200,MessageUnits=4096,FormattedBytes=1024,FileBytes=1024*1024;
class Ring {
    std::size_t head_=0,count_=0;
public:
    std::size_t count()const{return count_;}
    std::size_t next()const{return count_<Entries?count_:head_;}
    void appended(){if(count_<Entries)++count_;else head_=(head_+1)%Entries;}
    std::size_t tailCount(std::size_t limit)const{return std::min(limit,count_);}
    std::size_t tailIndex(std::size_t limit,std::size_t index)const{return (head_+count_-tailCount(limit)+index)%Entries;}
    void clear(){head_=count_=0;}
};
inline void Increment(uint64_t &value){if(value!=std::numeric_limits<uint64_t>::max())++value;}
inline bool NeedsReset(uint64_t size,std::size_t bytes){return bytes<=FileBytes&&size>FileBytes-bytes;}
}
