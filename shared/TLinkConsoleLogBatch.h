#ifndef TLINK_CONSOLE_LOG_BATCH_H
#define TLINK_CONSOLE_LOG_BATCH_H
#include "TLinkConsoleLogBudget.h"
#include <vector>
static_assert(TLinkConsoleLogMaxPending<=64,"console batch failure mask must cover every admitted entry");

// Include the line that crosses the threshold; rotate before the next line.
template<class Length>
size_t TLinkConsoleLogBatchCount(uint64_t bytes,uint64_t limit,size_t remaining,Length length){
    size_t count=0;
    while(count<remaining&&bytes<=limit){
        const uint64_t next=length(count++);
        bytes=next>UINT64_MAX-bytes?UINT64_MAX:bytes+next;
    }
    return count;
}
static inline uint64_t TLinkConsoleLogBatchMask(size_t begin,size_t count){
    if(!count||begin>=64)return 0;
    count=std::min(count,size_t(64)-begin);
    return (count==64?UINT64_MAX:((uint64_t(1)<<count)-1))<<begin;
}
#endif
