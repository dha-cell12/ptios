#include "../shared/TLinkConsoleLogRetention.h"
#include <cassert>
#include <cstdio>
#include <random>
#include <set>
using namespace TLinkConsoleLogRetention;
static std::string runName(unsigned n,bool helper=false){
    char value[64];std::snprintf(value,sizeof(value),"%08x-0000-4000-8000-%012x%s",n,n,helper?"-helper.log":".log");return value;
}
int main(){
    assert(KeepCompleted==50&&ScanLimit==4096);
    assert(KeepCompletedBytes==25ULL*1024*1024);
    Budget edge(SIZE_MAX,UINT64_MAX);assert(edge.retain(UINT64_MAX)&&!edge.retain(1)&&edge.retain(0)&&edge.bytes()==UINT64_MAX);
    Budget none(0,UINT64_MAX);assert(!none.retain(0));
    for(const auto &name:{"latest.log","latest-helper.log","notes.log","../run.log","00000000-0000-4000-8000-000000000000.log/child"})assert(!RunName(name));
    std::mt19937 random(1945);
    for(unsigned cycle=0;cycle<100000;++cycle){
        std::string name=runName(cycle,cycle%2);assert(RunName(name));
        std::string invalid=name;invalid[cycle%36]=(cycle%2)?'/':'\0';assert(!RunName(invalid));
        std::vector<Candidate> rows;
        const unsigned count=random()%80;
        for(unsigned n=0;n<count;++n){Candidate row;row.name=runName(n);row.identity.modified=int(random()%21)-10;row.identity.modifiedNanos=random()%4;rows.push_back(row);}
        const auto original=rows;NewestFirst(rows);
        std::set<std::string> identities;
        for(std::size_t n=0;n<rows.size();++n){
            assert(identities.insert(rows[n].name).second);
            if(n+1<rows.size()){
                const auto &a=rows[n],&b=rows[n+1];
                assert(a.identity.modified>b.identity.modified||
                    (a.identity.modified==b.identity.modified&&(a.identity.modifiedNanos>b.identity.modifiedNanos||
                    (a.identity.modifiedNanos==b.identity.modifiedNanos&&a.name<b.name))));
            }
        }
        for(const auto &row:original)assert(identities.count(row.name)==1);
        const std::size_t maxCount=random()%65;const uint64_t maxBytes=random()%(25*1024*1024+1);
        Budget budget(maxCount,maxBytes);uint64_t total=0;std::size_t kept=0;
        for(unsigned n=0;n<80;++n){
            const uint64_t size=n%11==0?UINT64_MAX:(n%7==0?0:random()%(8*1024*1024));
            const bool expected=size<=maxBytes&&total+size<=maxBytes&&kept<maxCount;
            assert(budget.retain(size)==expected);
            if(expected){total+=size;++kept;}
            assert(budget.count()==kept&&budget.bytes()==total&&total<=maxBytes);
        }
        Identity identity;identity.device=1;identity.inode=2;identity.size=3;identity.modified=4;identity.modifiedNanos=5;identity.changed=6;identity.changedNanos=7;
        assert(Same(identity,identity));
        identity.device=(uint64_t(random())<<32)|random();identity.inode=(uint64_t(random())<<32)|random();
        const auto proof=Proof(identity);assert(std::memcmp(proof.data(),"TLCLOG1",8)==0);
        uint64_t device=0,inode=0;for(unsigned n=0;n<8;++n){device=device*256+proof[8+n];inode=inode*256+proof[16+n];}
        assert(device==identity.device&&inode==identity.inode);
        for(unsigned field=0;field<7;++field){Identity changed=identity;
            switch(field){case 0:++changed.device;break;case 1:++changed.inode;break;case 2:++changed.size;break;case 3:++changed.modified;break;case 4:++changed.modifiedNanos;break;case 5:++changed.changed;break;default:++changed.changedNanos;}
            assert(!Same(identity,changed));
        }
    }
    puts("Console retention core passed: 100k UUID/order/proof/identity and independent newest-fit byte/count oracles, zero/exact/UINT64_MAX/SIZE_MAX budgets; 50 completed/25-MiB/4096 scan policy.");
}
