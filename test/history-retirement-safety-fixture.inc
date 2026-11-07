#include "../shared/TLinkHistoryRetirement.h"
#include <vector>
static void historyRetirementPlans(){
    uint32_t seed=0x812abc;
    for(unsigned n=0;n<100000;++n){
        seed=seed*1664525U+1013904223U;
        const size_t count=seed%257,limit=(seed>>16)%97;
        std::vector<size_t> old,retired;
        for(size_t i=0;i<count;++i)old.push_back(i);
        while(old.size()>limit){retired.push_back(old.back());old.pop_back();}
        const TLinkHistoryRetirementPlan plan(count,limit);
        assert(plan.keep==old.size()&&plan.retired==retired.size()&&plan.keep+plan.retired==count);
        assert(plan.hint<=plan.retired&&plan.hint<=limit);
        for(size_t i=0;i<retired.size();++i)assert(plan.index(i)==retired[i]);
        assert(plan.index(plan.retired)==SIZE_MAX);
    }
    const TLinkHistoryRetirementPlan edge(SIZE_MAX,50),zero(0,SIZE_MAX),all(SIZE_MAX,0),none(SIZE_MAX,SIZE_MAX);
    assert(edge.keep==50&&edge.retired==SIZE_MAX-50&&edge.hint==50);
    assert(edge.index(0)==SIZE_MAX-1&&edge.index(edge.retired-1)==50&&edge.index(edge.retired)==SIZE_MAX);
    assert(!zero.keep&&!zero.retired&&!zero.hint&&zero.index(0)==SIZE_MAX);
    assert(all.retired==SIZE_MAX&&!all.hint&&all.index(SIZE_MAX-1)==0&&all.index(SIZE_MAX)==SIZE_MAX);
    assert(none.keep==SIZE_MAX&&!none.retired&&!none.hint);
    puts("History retirement passed: 100k frozen pop-last order/keep/hint oracles, empty/zero/oversize limits and SIZE_MAX subtraction/index boundaries.");
}
