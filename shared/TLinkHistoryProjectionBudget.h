#pragma once
#include <cstddef>
class TLinkHistoryProjectionBudget {
    std::size_t nodes_=0,units_=0;
    bool valid_=true;
public:
    static const std::size_t MaxNodes=4096,MaxUnits=128*1024,MaxDepth=32;
    bool node(std::size_t depth){
        if(!valid_||depth>MaxDepth||nodes_==MaxNodes){valid_=false;return false;}
        ++nodes_;return true;
    }
    bool text(std::size_t units){
        if(!valid_||units>MaxUnits-units_){valid_=false;return false;}
        units_+=units;return true;
    }
    std::size_t remaining()const{return valid_?MaxNodes-nodes_:0;}
    bool valid()const{return valid_;}
};
