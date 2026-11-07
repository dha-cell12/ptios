#include "../shared/TLinkEventPreparation.h"
#include <limits>
static void eventPreparationCases(){
    uint32_t seed=0x93124;
    for(unsigned trial=0;trial<100000;++trial){
        seed=seed*1664525U+1013904223U;
        const size_t count=seed%257,limit=(seed>>10)%36;
        std::vector<uint64_t> values;
        uint64_t next=(seed>>16)%128;
        for(size_t n=0;n<count;++n){next+=1+(n+trial)%3;values.push_back(next);}
        const uint64_t cursor=trial%7==0?UINT64_MAX:(seed>>8)%1024;
        size_t expected=0;while(expected<count&&values[expected]<=cursor)++expected;
        unsigned probes=0;
        const size_t actual=TLinkEventPreparation::FirstAfter(count,cursor,[&](size_t n){assert(n<count);++probes;return values[n];});
        assert(actual==expected&&probes<=10);
        const size_t reserve=TLinkEventPreparation::Reserve(limit,count-actual,32);
        assert(reserve<=limit&&reserve<=count-actual&&reserve<=32);
        TLinkEventBatchCursor old(cursor,limit),now(cursor,limit);
        std::vector<uint64_t> before,after;
        for(size_t n=0;n<count;++n){const auto action=old.scan(values[n],(n+trial)%4==0);if(action==TLinkEventBatchCursor::Stop)break;if(action==TLinkEventBatchCursor::Select)before.push_back(values[n]);}
        for(size_t n=actual;n<count;++n){const auto action=now.scan(values[n],(n+trial)%4==0);if(action==TLinkEventBatchCursor::Stop)break;if(action==TLinkEventBatchCursor::Select)after.push_back(values[n]);}
        const uint64_t latest=values.empty()?0:values.back();
        assert(before==after&&old.nextCursor(latest)==now.nextCursor(latest)&&old.more==now.more);
        TLinkEventPreparation::ByteCount bytes;size_t total=0;
        for(unsigned n=0;n<16;++n){const size_t length=(trial+n*11)%65537;total+=length;assert(bytes.append(length)&&bytes.size()==total);}
    }
    const size_t maximum=std::numeric_limits<size_t>::max();
    TLinkEventPreparation::ByteCount exact;assert(exact.append(maximum)&&exact.append(0)&&exact.size()==maximum&&!exact.failed());
    assert(!exact.append(1)&&exact.failed()&&exact.size()==maximum&&!exact.append(0));
    size_t probes=0;
    assert(TLinkEventPreparation::FirstAfter(maximum,UINT64_MAX,[&](size_t n){++probes;return uint64_t(n);})==maximum&&probes==1);
    assert(TLinkEventPreparation::Reserve(maximum,maximum,32)==32);
    puts("Event preparation passed: 100k ordered/gapped cursor and frozen pagination oracles, <=10 probes over256 events, new-tail hints, chunk byte counts and sticky SIZE_MAX overflow without buffers.");
}
