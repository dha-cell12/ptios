#include "../shared/TLinkHelperRPCIdentity.h"
#include <cassert>
#include <cstdio>
int main(){
    using I=TLinkHelperRPCIdentity;using E=I::Error;
    for(unsigned n=0;n<100000;++n){
        I expected{"helper-"+std::to_string(n%7),"session-"+std::to_string(n),"request-"+std::to_string(n)};
        auto actual=expected;assert(I::reply(expected,actual)==E::None);
        actual.helper+="x";assert(I::reply(expected,actual)==E::Helper);actual=expected;
        actual.session+="x";assert(I::reply(expected,actual)==E::Session);actual=expected;
        actual.request+="x";assert(I::reply(expected,actual)==E::Request);actual=expected;
        actual.helper.clear();assert(I::reply(expected,actual)==E::Invalid);assert(I::reply(expected,actual,true)==E::None);
        actual.session.clear();assert(I::reply(expected,actual,true)==E::Invalid);
        actual=expected;actual.request.clear();assert(I::reply(expected,actual)==E::Invalid);
        actual=expected;actual.helper=std::string(65,'a');assert(I::reply(expected,actual,true)==E::Invalid);
        actual=expected;actual.session=std::string(65,'a');assert(I::reply(expected,actual)==E::Invalid);
        actual=expected;actual.request=std::string(65,'a');assert(I::reply(expected,actual)==E::Invalid);
    }
    I exact{std::string(64,'h'),std::string(64,'s'),std::string(64,'r')};assert(I::reply(exact,exact)==E::None);
    I nul{"helper",std::string("a\0b",3),"request"};auto prefix=nul;prefix.session="a";assert(I::reply(nul,prefix)==E::Session);assert(I::reply(nul,nul)==E::None);
    puts("Helper identity passed: 100k helper/session/request matches and mismatches, explicit legacy helper omission, empty/64/65-byte fields and embedded NUL identity.");
}
