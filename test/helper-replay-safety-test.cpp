#include "../shared/TLinkHelperRPCReplay.h"
#include <cassert>
#include <cstdio>
int main(){
    using C=TLinkHelperRPCReplay;using D=C::Decision;C::Digest digest{};C::Limits limits;
    limits.replies=3;limits.bytes=12;limits.replyBytes=10;limits.identities=6;limits.identityBytes=300;
    C cache(limits);
    assert(cache.begin("","tap",digest).decision==D::Invalid);
    assert(cache.begin(std::string(65,'x'),"tap",digest).decision==D::Invalid);
    assert(cache.begin("1",std::string(129,'x'),digest).decision==D::Invalid);
    assert(cache.begin("1","tap",digest).decision==D::Execute);
    assert(cache.begin("1","tap",digest).decision==D::InFlight);
    assert(cache.begin("1","swipe",digest).decision==D::Collision);
    assert(cache.finish("1","123456"));assert(!cache.finish("1","x"));
    assert(cache.begin("2","tap",digest).decision==D::Execute);assert(cache.finish("2","abcdef"));
    assert(cache.bytes()==12&&cache.replies()==2);
    assert(cache.begin("3","tap",digest).decision==D::Execute);assert(cache.finish("3","z"));
    assert(cache.begin("1","tap",digest).decision==D::Unavailable);
    assert(cache.begin("2","tap",digest).decision==D::Replay);
    assert(*cache.begin("2","tap",digest).reply=="abcdef");
    auto changed=digest;changed[31]=1;assert(cache.begin("1","tap",changed).decision==D::Collision);
    assert(cache.begin("4","tap",digest).decision==D::Execute);assert(!cache.finish("4",std::string(11,'x')));
    assert(cache.begin("4","tap",digest).decision==D::Unavailable);
    assert(cache.begin("5","tap",digest).decision==D::Execute);assert(!cache.finish("5",""));
    assert(cache.begin("6","tap",digest).decision==D::Execute);assert(cache.finish("6","ok"));
    assert(cache.begin("7","tap",digest).decision==D::Capacity);
    assert(cache.begin("2","tap",digest).decision==D::Replay);
    cache.clear();assert(cache.bytes()==0&&cache.identities()==0&&cache.replies()==0&&cache.identityBytes()==0);
    limits.identityBytes=35;C metadata(limits);assert(metadata.begin("1","tap",digest).decision==D::Capacity);
    limits.identityBytes=36;C exact(limits);assert(exact.begin("1","tap",digest).decision==D::Execute);assert(exact.identityBytes()==36);
    assert(exact.begin("2","tap",digest).decision==D::Capacity);
    limits=C::Limits{};limits.replies=0;C noReplies(limits);assert(noReplies.begin("1","tap",digest).decision==D::Execute);assert(!noReplies.finish("1","ok"));assert(noReplies.begin("1","tap",digest).decision==D::Unavailable);
    limits.replies=256;limits.bytes=4*1024*1024;C large(limits);
    for(unsigned n=0;n<256;++n){std::string id=std::to_string(n);assert(large.begin(id,"capture",digest).decision==D::Execute);assert(large.finish(id,std::string(1024*1024,'a')));assert(large.bytes()<=4*1024*1024&&large.replies()<=4);}
    assert(large.bytes()==4*1024*1024);assert(large.identities()==256);
    for(unsigned n=0;n<252;++n)assert(large.begin(std::to_string(n),"capture",digest).decision==D::Unavailable);
    C full;
    for(unsigned n=0;n<8192;++n){auto id=std::to_string(n);assert(full.begin(id,"tap",digest).decision==D::Execute);assert(full.finish(id,"{}"));}
    assert(full.replies()==256);
    assert(full.begin("8192","tap",digest).decision==D::Capacity);
    assert(full.begin("0","tap",digest).decision==D::Unavailable);
    assert(full.begin("8191","tap",digest).decision==D::Replay);
    // Deterministic variable-size FIFO oracle, with collisions and session resets.
    limits=C::Limits{};limits.replies=7;limits.bytes=73;limits.replyBytes=73;limits.identities=100;
    C stress(limits);std::deque<std::pair<std::string,std::string>> oracle;size_t bytes=0;
    for(unsigned n=0;n<100000;++n){
        if(n%100==0){stress.clear();oracle.clear();bytes=0;}
        std::string id=std::to_string(n),reply(n%73+1,char('a'+n%26));
        assert(stress.begin(id,"tap",digest).decision==D::Execute);
        while(!oracle.empty()&&(oracle.size()>=7||reply.size()>73-bytes)){bytes-=oracle.front().second.size();oracle.pop_front();}
        bytes+=reply.size();oracle.emplace_back(id,reply);assert(stress.finish(id,reply));
        assert(stress.bytes()==bytes&&stress.replies()==oracle.size());
        for(const auto &entry:oracle){auto hit=stress.begin(entry.first,"tap",digest);assert(hit.decision==D::Replay&&*hit.reply==entry.second);assert(stress.begin(entry.first,"tap",changed).decision==D::Collision);}
        if(n%100>0){auto old=stress.begin(std::to_string(n-n%100),"tap",digest);assert(old.decision!=D::Execute);}
    }
    puts("Helper replay core passed: 100k FIFO/oracle lifecycles, 4-MiB/256 limits, 8192 identity fence, byte/count eviction, collisions after retirement, pending/oversize failures and session reset.");
}
