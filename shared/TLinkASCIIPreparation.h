#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace TLinkASCIIPreparation {
inline bool Allowed(std::uint16_t value,bool uppercase){
    return (value>='a'&&value<='z')||(uppercase&&value>='A'&&value<='Z')||
        (value>='0'&&value<='9')||value=='-'||value=='_'||value=='.';
}
template<std::size_t Limit,bool Uppercase,bool Replace>
struct Token {
    std::array<std::uint16_t,Limit> values{};
    std::size_t count=0;
    void push(std::uint16_t value){
        if(count>=Limit)return;
        if(Allowed(value,Uppercase))values[count++]=value;
        else if(Replace)values[count++]='_';
    }
};
class Decimal {
    std::uint64_t value_=0;
    bool any_=false,invalid_=false,overflow_=false;
public:
    bool push(std::uint16_t value){
        if(value<'0'||value>'9'){invalid_=true;return false;}
        any_=true;const std::uint64_t digit=value-'0';
        if(!overflow_){
            if(value_>(std::numeric_limits<std::uint64_t>::max()-digit)/10)overflow_=true;
            else value_=value_*10+digit;
        }
        return true;
    }
    bool overflow()const{return overflow_;}
    bool finish(std::uint64_t &value)const{
        if(!any_||invalid_||overflow_)return false;
        value=value_;return true;
    }
};
}
