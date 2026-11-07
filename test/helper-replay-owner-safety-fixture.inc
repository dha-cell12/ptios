#include "HelperReplayBefore.inc"
#include <memory>
#include <thread>
#include <type_traits>
static void replayOwnerCases(){
    using C=TLinkHelperRPCReplay;using Old=BeforeTLinkHelperRPCReplay;using D=C::Decision;
    static_assert(std::is_const<C::Reply::element_type>::value,"replay snapshots are immutable");
    C::Limits limits;limits.replies=3;limits.bytes=37;limits.replyBytes=37;limits.identities=100;
    Old::Limits oldLimits;oldLimits.replies=limits.replies;oldLimits.bytes=limits.bytes;oldLimits.replyBytes=limits.replyBytes;oldLimits.identities=limits.identities;
    C now(limits);Old old(oldLimits);C::Digest digest{};
    for(unsigned n=0;n<100000;++n){
        if(n%73==0){now.clear();old.clear();}
        const std::string id=std::to_string(n),method=n%2?"tap":"capture";
        const std::string bytes(n%43,char('a'+n%26));
        assert(unsigned(now.begin(id,method,digest).decision)==unsigned(old.begin(id,method,digest).decision));
        assert(now.finish(id,bytes)==old.finish(id,bytes));
        assert(now.bytes()==old.bytes()&&now.replies()==old.replies()&&now.identities()==old.identities()&&now.identityBytes()==old.identityBytes());
        const auto a=now.begin(id,method,digest);const auto b=old.begin(id,method,digest);
        assert(unsigned(a.decision)==unsigned(b.decision));
        if(a.reply){assert(b.reply&&*a.reply==*b.reply);assert(now.begin(id,method,digest).reply.get()==a.reply.get());}
        auto collision=digest;collision[0]=1;
        assert(unsigned(now.begin(id,method,collision).decision)==unsigned(old.begin(id,method,collision).decision));
    }
    for(unsigned n=0;n<10000;++n){
        C cache(limits);assert(cache.begin("held","tap",digest).decision==D::Execute);assert(cache.finish("held","original"));
        auto held=cache.begin("held","tap",digest).reply;std::weak_ptr<const std::string> weak=held;
        for(unsigned j=0;j<6;++j){const std::string id=std::to_string(j);assert(cache.begin(id,"tap",digest).decision==D::Execute);assert(cache.finish(id,std::string(20,'x')));}
        assert(cache.begin("held","tap",digest).decision==D::Unavailable&&*held=="original");
        cache.clear();assert(*held=="original"&&!weak.expired()&&!cache.bytes()&&!cache.identities());
        held.reset();assert(weak.expired());
    }
    C::Reply held;
    {
        C cache;assert(cache.begin("held","tap",digest).decision==D::Execute);assert(cache.finish("held",std::string(4096,'x')));
        held=cache.begin("held","tap",digest).reply;
    }
    std::weak_ptr<const std::string> weak=held;
    std::vector<std::thread> readers;
    for(unsigned n=0;n<8;++n)readers.emplace_back([held]{for(unsigned j=0;j<10000;++j){assert(held->size()==4096&&held->front()=='x'&&held->back()=='x');}});
    held.reset();for(auto &reader:readers){reader.join();}
    assert(weak.expired());
    std::puts("Helper replay owners passed: 100k complete preceding decisions/quota comparisons, 10k held-reader eviction/reset lifecycles, immutable shared snapshots, destroyed cache and 8 x 10k concurrent readers; no final held owners.");
}
