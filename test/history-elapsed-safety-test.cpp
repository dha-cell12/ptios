#include "../shared/TLinkRunElapsed.h"
#include <cassert>
#include <cstdio>
#include <deque>
#include <string>
int main(){
    TLinkRunElapsed<4> clock;
    assert(clock.remember("root","run",10000,100));
    assert(clock.duration("root","run",10000,20000,350)==250); // wall jumps forward
    assert(clock.duration("root","run",10000,5000,350)==250); // wall jumps backward
    assert(clock.duration("root","run",10000,10000,350)==250); // paused wall
    assert(clock.duration("other","run",10000,20000,350)==10000);
    assert(clock.duration("root","unknown",10000,5000,350)==0);
    assert(clock.duration("root","run",9999,20000,350)==10001); // changed persisted start
    assert(clock.duration("root","run",10000,12000,99)==2000); // regressed/invalid clock
    assert(clock.duration("root","run",10000,12000,UINT64_MAX)==2000);
    assert(!clock.remember("root","bad",0,UINT64_MAX)&&clock.size()==1);
    assert(clock.remember("root","run",10000,200)&&clock.size()==1);
    assert(clock.duration("root","run",10000,30000,350)==150);
    assert(!clock.remember("root","run",10000,UINT64_MAX)&&clock.size()==0);
    assert(clock.duration("root","run",10000,12000,350)==2000);
    assert(clock.remember("root","run",10000,200));
    clock.forget("other","run");assert(clock.size()==1);clock.forget("root","run");assert(clock.size()==0);
    assert(clock.remember("root","zero",0,0));assert(clock.duration("root","zero",0,5000,0)==0);clock.forget("root","zero");
    assert(clock.remember("root","near-max",0,UINT64_MAX-100));
    assert(clock.duration("root","near-max",0,7,UINT64_MAX-1)==99);clock.forget("root","near-max");
    const std::string longScope(4097,'s'),longID(97,'i');
    assert(!clock.remember(longScope.c_str(),"id",0,0)&&!clock.remember("root",longID.c_str(),0,0));
    assert(!clock.remember(nullptr,"id",0,0)&&!clock.remember("root","",0,0));
    // Independent FIFO oracle: overflow retires oldest optional clocks, never persistence.
    std::deque<std::string> oracle;
    for(unsigned n=0;n<10000;++n){
        const std::string id=std::to_string(n);assert(clock.remember("root",id.c_str(),n,1000+n));
        oracle.push_back(id);if(oracle.size()>4)oracle.pop_front();assert(clock.size()==oracle.size());
        for(unsigned k=n>6?n-6:0;k<=n;++k){
            const std::string key=std::to_string(k);bool tracked=false;for(const auto &item:oracle)if(item==key)tracked=true;
            const uint64_t expected=tracked?20000-k:50000;
            assert(clock.duration("root",key.c_str(),k,k+50000,21000)==expected);
        }
    }
    for(const auto &id:oracle)clock.forget("root",id.c_str());
    assert(clock.size()==0);
    TLinkRunElapsed<> production;
    for(unsigned n=0;n<100000;++n){
        const std::string id=std::to_string(n);assert(production.remember("scope",id.c_str(),5000,100));
        assert(production.duration("scope",id.c_str(),5000,0,1100)==1000);
        production.forget("scope",id.c_str());assert(production.size()==0);
    }
    puts("History elapsed core passed: wall jumps, missing/mismatched scope/start, invalid/regressed/edge clocks, bounded IDs, 10k FIFO/oracle admissions and 100k committed-start/finish lifecycles; zero final entries.");
}
