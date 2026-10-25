#include "../shared/TLinkHelperConfigSnapshot.h"
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
int main(){
    TLinkHelperConfigMemo memo;TLinkHelperConfigIdentity base;
    assert(!memo.matches(base));memo.publish(base);assert(memo.matches(base));
    for(unsigned n=0;n<100000;++n){
        base.device=n%17;base.inode=n;base.size=n*3;base.modifiedSeconds=n/100;base.modifiedNanos=n%100;base.changedSeconds=n/10;base.changedNanos=n%10;base.mode=n%8;base.uid=n%5;base.gid=n%7;
        memo.publish(base);assert(memo.matches(base));
        for(unsigned field=0;field<10;++field){
            auto other=base;switch(field){case 0:++other.device;break;case 1:++other.inode;break;case 2:++other.size;break;case 3:++other.modifiedSeconds;break;case 4:++other.modifiedNanos;break;case 5:++other.changedSeconds;break;case 6:++other.changedNanos;break;case 7:++other.mode;break;case 8:++other.uid;break;default:++other.gid;break;}
            assert(!memo.matches(other));
        }
        memo.invalidate();assert(!memo.matches(base));
    }
    std::mutex owner;std::vector<std::thread> clients;
    for(unsigned t=0;t<8;++t)clients.emplace_back([&,t]{for(unsigned n=0;n<10000;++n){std::lock_guard<std::mutex> guard(owner);TLinkHelperConfigIdentity key;key.inode=t*10000+n;memo.publish(key);assert(memo.matches(key));memo.invalidate();assert(!memo.matches(key));}});
    for(auto &thread:clients)thread.join();assert(TLinkHelperConfigMaxBytes==1024*1024);
    puts("Helper config identity passed: 100k metadata/invalidation cases, all ten identity fields and 8 x 10k serialized publication lifecycles.");
}
