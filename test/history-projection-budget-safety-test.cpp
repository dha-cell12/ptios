#include "../shared/TLinkHistoryProjectionBudget.h"
#include <cassert>
#include <cstdint>
#include <cstdio>
int main(){
    uint32_t random=17;
    for(unsigned round=0;round<100000;++round){
        TLinkHistoryProjectionBudget budget;size_t nodes=0,units=0;bool valid=true;
        for(unsigned step=0;step<48;++step){
            random=random*1664525U+1013904223U;
            const size_t depth=(random>>16)%36,add=random%10000;
            const bool expectedNode=valid&&depth<=32&&nodes<4096;
            if(expectedNode)++nodes;else valid=false;
            assert(budget.node(depth)==expectedNode);
            const bool expectedText=valid&&add<=128*1024-units;
            if(expectedText)units+=add;else valid=false;
            assert(budget.text(add)==expectedText&&budget.valid()==valid);
            assert(budget.remaining()==(valid?4096-nodes:0));
        }
    }
    TLinkHistoryProjectionBudget nodes;for(unsigned n=0;n<4096;++n)assert(nodes.node(32));assert(!nodes.node(0)&&nodes.remaining()==0);
    TLinkHistoryProjectionBudget text;assert(text.text(128*1024)&&text.node(0)&&!text.text(1)&&!text.node(0));
    TLinkHistoryProjectionBudget overflow;assert(!overflow.text(SIZE_MAX)&&!overflow.text(0));
    TLinkHistoryProjectionBudget depth;assert(depth.node(32)&&!depth.node(33)&&!depth.node(0));
    puts("History projection budget passed: 100k independent node/text/depth oracles, sticky refusal, exact 4096 nodes/128-Ki UTF16 units/depth32, SIZE_MAX and zero boundaries; quotas only govern memo eligibility.");
}
