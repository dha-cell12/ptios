#include "../shared/TLinkASCIIPreparation.h"
#include <random>
#include <cstdlib>
#include <cerrno>
static void asciiPreparationCases(){
    using namespace TLinkASCIIPreparation;
    std::mt19937 random(42);const std::u16string lower=u"abcdefghijklmnopqrstuvwxyz0123456789._-",upper=u"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.";
    for(unsigned n=0;n<100000;++n){
        Token<64,false,false> event;Token<96,true,true> history;std::u16string expectedEvent,expectedHistory;
        const unsigned length=n%257;
        for(unsigned i=0;i<length;++i){const std::uint16_t c=std::uint16_t(random()%65536);event.push(c);history.push(c);
            if(expectedEvent.size()<64&&lower.find(char16_t(c))!=std::u16string::npos)expectedEvent+=char16_t(c);
            if(expectedHistory.size()<96)expectedHistory+=upper.find(char16_t(c))==std::u16string::npos?u'_':char16_t(c);
        }
        assert(event.count==expectedEvent.size()&&history.count==expectedHistory.size());
        for(size_t i=0;i<event.count;++i)assert(event.values[i]==expectedEvent[i]);
        for(size_t i=0;i<history.count;++i)assert(history.values[i]==expectedHistory[i]);
        std::string input=std::to_string((uint64_t(random())<<32)|random());if(n%3==0)input=std::string(n%40,'0')+input;if(n%5==0)input+='0';if(n%7==0)input+='x';
        Decimal number;bool digits=true;for(unsigned char c:input)digits=number.push(c)&&digits;
        bool oldDigits=!input.empty();for(unsigned char c:input)oldDigits=oldDigits&&c>='0'&&c<='9';
        errno=0;char *end=nullptr;const uint64_t expected=std::strtoull(input.c_str(),&end,10);const bool valid=oldDigits&&errno!=ERANGE&&end==input.c_str()+input.size();
        uint64_t value=987;assert(number.finish(value)==valid);if(valid)assert(value==expected);else assert(value==987);
        assert(digits==oldDigits);
    }
    for(const std::string &input:std::vector<std::string>{"","0","18446744073709551615","18446744073709551616","-0","+1","1.0"," 1",std::string("1\0x",3)}){
        Decimal number;for(unsigned char c:input)number.push(c);uint64_t value=999;const bool valid=number.finish(value);
        assert(valid==(input=="0"||input=="18446744073709551615"));if(!valid)assert(value==999);
    }
    Token<0,false,false> empty;empty.push('a');assert(empty.count==0);
    Token<64,false,false> full;for(unsigned n=0;n<1000;++n)full.push('a');assert(full.count==64);
    puts("ASCII preparation passed: 100k event/history UTF16 token oracles and decimal/strtoull cases, exact 64/96 caps, uint64/zero/sign/NUL/overflow and unchanged refused output.");
}
