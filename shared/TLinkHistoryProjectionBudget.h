#pragma once
#include <cstddef>
// A retained newest-first prefix answers any request it completely covers.
// Avoid arithmetic on limits: SIZE_MAX remains a valid oversized request.
inline bool TLinkHistoryProjectionSelection(std::size_t total,std::size_t available,
    std::size_t requested,std::size_t &selected){
    selected=0;
    if(!requested||available>total)return false;
    const std::size_t needed=requested<total?requested:total;
    if(needed>available)return false;
    selected=needed;return true;
}
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
