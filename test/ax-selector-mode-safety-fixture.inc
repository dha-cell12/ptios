#include "../shared/TLinkAXSelectorMode.h"
static void selectorModeCases(){
    using namespace TLinkAXSelectorMode;
    for(unsigned n=0;n<100000;++n){
        State shared,exact;unsigned sharedChecks=0,exactChecks=0,compares=0;
        const bool eligible=n%2==0;const Kind chosen=n%3==0?Kind::Contains:(n%3==1?Kind::Exact:Kind::Prefix);
        for(unsigned row=0;row<8;++row){
            for(unsigned field:{0U,1U,2U,2U}){
                State &mode=field==1?exact:shared;
                const bool stable=mode.stable([&]{if(field==1)++exactChecks;else ++sharedChecks;return eligible;});assert(stable==eligible);
                if(stable){const Kind want=field==1?Kind::Exact:chosen;
                    assert(mode.kind([&](Kind value){++compares;return value==want;})==want);
                }
            }
        }
        assert(sharedChecks==1&&exactChecks==1);
        const unsigned expected=!eligible?0:(chosen==Kind::Exact?2:3);assert(compares==expected);
    }
    for(unsigned fault=1;fault<=2;++fault){
        State state;unsigned calls=0;bool caught=false;
        try{state.kind([&](Kind){if(++calls==fault)throw std::runtime_error("mode");return false;});}catch(const std::runtime_error &){caught=true;}
        assert(caught&&calls==fault);const unsigned before=calls;
        assert(state.kind([&](Kind value){++calls;return value==Kind::Prefix;})==Kind::Prefix&&calls==before+2);
        assert(state.kind([&](Kind){assert(false);return false;})==Kind::Prefix);
    }
    State classification;bool caught=false;
    try{classification.stable([]()->bool{throw std::runtime_error("class");});}catch(const std::runtime_error &){caught=true;}
    assert(caught&&classification.stable([]{return true;}));
    assert(classification.stable([]{assert(false);return false;}));
    State refusal;assert(!refusal.stable([]{return false;}));assert(!refusal.stable([]{assert(false);return true;}));
    puts("AX selector mode passed: 100k shared/exact and eligibility/contains/prefix plans, lazy reuse, sticky refusal and classification/decode exception retry without partial publication.");
}
