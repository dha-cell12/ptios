#include "../shared/TLinkHelperRPCReplay.h"
#include <cassert>
#include <cstdio>
#include <limits>
#include <vector>
struct DigestOracle {
    uint64_t hash=1469598103934665603ULL;size_t calls=0,failAt=0;
    static bool update(void *opaque,const uint8_t *bytes,size_t length){
        auto &state=*static_cast<DigestOracle *>(opaque);++state.calls;
        if(state.failAt&&state.calls==state.failAt)return false;
        for(size_t n=0;n<length;++n){state.hash^=bytes[n];state.hash*=1099511628211ULL;}
        return true;
    }
};
static void digestFeedCases(){
    using Feed=TLinkHelperRPCDigestFeed;
    for(unsigned n=0;n<100000;++n){
        std::array<uint8_t,64> input;for(size_t j=0;j<input.size();++j)input[j]=static_cast<uint8_t>(n+j);
        const size_t length=n%64+1,step=n%31+1;Feed feed;DigestOracle actual,expected;
        DigestOracle::update(&expected,input.data(),length);
        for(size_t offset=0;offset<length;){const size_t take=step<length-offset?step:length-offset;assert(feed.append(input.data()+offset,take,DigestOracle::update,&actual));offset+=take;}
        assert(feed.finish());assert(actual.hash==expected.hash);assert(feed.stats().bytes==length&&!feed.stats().failed);
        const size_t calls=actual.calls;assert(!feed.append(input.data(),1,DigestOracle::update,&actual));assert(!feed.finish()&&actual.calls==calls);
    }
    std::vector<uint8_t> input(Feed::MaxBytes,0x5a);Feed exact;DigestOracle actual,expected;
    assert(exact.append(input.data(),input.size(),DigestOracle::update,&actual));DigestOracle::update(&expected,input.data(),input.size());
    assert(exact.stats().bytes==Feed::MaxBytes&&exact.stats().updates==Feed::MaxBytes/Feed::ChunkBytes&&actual.hash==expected.hash);assert(exact.finish());
    Feed overflow;DigestOracle unused;
    assert(!overflow.append(input.data(),std::numeric_limits<size_t>::max(),DigestOracle::update,&unused));assert(overflow.stats().failed&&unused.calls==0&&!overflow.finish());
    Feed extra;assert(extra.append(input.data(),input.size(),DigestOracle::update,&unused));const auto calls=unused.calls;
    assert(!extra.append(input.data(),1,DigestOracle::update,&unused));assert(extra.stats().bytes==Feed::MaxBytes&&unused.calls==calls&&!extra.finish());
    Feed invalid;assert(!invalid.append(nullptr,1,DigestOracle::update,&unused));assert(!invalid.finish());
    Feed noCallback;assert(!noCallback.append(input.data(),1,nullptr,&unused));
    Feed empty;assert(empty.append(nullptr,0,DigestOracle::update,&unused));assert(!empty.finish());
    Feed fault;DigestOracle failing;failing.failAt=2;
    assert(!fault.append(input.data(),Feed::ChunkBytes*3,DigestOracle::update,&failing));
    assert(fault.stats().bytes==Feed::ChunkBytes&&fault.stats().updates==1&&fault.stats().failed&&!fault.finish());
    puts("Helper fingerprint feed passed: 100k chunk partitions, exact 1-MiB/4096-byte update boundaries, SIZE_MAX rejection, failed callback and terminal-state fencing.");
}
int main(){
    digestFeedCases();
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
