#pragma once
#include <array>
#include <cstddef>
#include <limits>

// Keep only the last Limit separator-delimited UTF16 ranges. The provider
// searches the half-open prefix [0,end), so a trailing separator yields an
// empty final component exactly like a complete split.
template<std::size_t Limit>
class TLinkTextTail {
public:
    struct Range { std::size_t start,length; };
private:
    std::array<Range,Limit> reverse_{};
    std::size_t count_=0;
public:
    template<class FindPrevious>
    static TLinkTextTail Build(std::size_t length,FindPrevious find) {
        TLinkTextTail result;
        std::size_t end=length;
        while(result.count_<Limit) {
            const std::size_t previous=end?find(end):std::numeric_limits<std::size_t>::max();
            const bool found=previous!=std::numeric_limits<std::size_t>::max();
            // A malformed provider cannot produce an out-of-range substring.
            if(found&&previous>=end)return TLinkTextTail();
            const std::size_t start=found?previous+1:0;
            result.reverse_[result.count_++]={start,end-start};
            if(!found)break;
            end=previous;
        }
        return result;
    }
    std::size_t size()const{return count_;}
    Range operator[](std::size_t index)const{return reverse_[count_-1-index];}
};
