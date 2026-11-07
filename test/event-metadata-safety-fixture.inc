#include "../shared/TLinkEventMetadata.h"
#include <random>
#include <limits>
static std::string fixtureStampText(const TLinkEventMetadata::Stamp &value){
    using Stamp=TLinkEventMetadata::Stamp;
    if(value.kind==Stamp::Kind::Empty)return "empty";
    if(value.kind==Stamp::Kind::Missing)return "absent:"+std::to_string(value.error);
    return std::to_string(value.device)+":"+std::to_string(value.inode)+":"+std::to_string(value.size)+":"+
        std::to_string(value.modifiedSeconds)+":"+std::to_string(value.modifiedNanos)+":"+std::to_string(value.changedSeconds)+":"+std::to_string(value.changedNanos);
}
static void eventMetadataCases(){
    using namespace TLinkEventMetadata;
    std::mt19937 random(9087);
    for(unsigned n=0;n<100000;++n){
        auto first=Stamp::Present((uint64_t(random())<<32)|random(),random(),int64_t(random())-2147483648LL,
            int64_t(random())-2147483648LL,random()%1000000000,int64_t(random())-2147483648LL,random()%1000000000);
        if(n%4==0)first=Stamp::Missing(int(random()%128));
        Stamp cached=first;
        switch(n%11){case 0:cached={};break;case 1:cached=Stamp::Missing(int(random()%128));break;
            case 2:++cached.device;break;case 3:++cached.inode;break;case 4:++cached.size;break;case 5:++cached.modifiedSeconds;break;
            case 6:++cached.modifiedNanos;break;case 7:++cached.changedSeconds;break;case 8:++cached.changedNanos;break;case 9:++cached.error;break;default:break;}
        const bool old=bool(cached)&&fixtureStampText(first)==fixtureStampText(cached);
        assert((first==cached)==old&&(first!=cached)==!old&&first);
        std::u16string text;std::string bytes;
        for(unsigned i=0;i<n%100;++i){char16_t c=char16_t(random()%3?random()%128:random()%65536);text+=c;if(c<=127)bytes+=char(c);else bytes.append("\xc2\x80",2);}
        if(n%10==0){text=u"*";bytes="*";}if(n%13==0){text=u"AbC.09_-";bytes="AbC.09_-";}
        size_t reads=0;const bool valid=TopicValid(text.size(),[&](size_t i){++reads;return text[i];});
        assert(valid==TLinkEventTopicValid(bytes.data(),bytes.size())&&reads<=64);
        const uint64_t mode=random(),uid=random()%504,gid=random()%504,wanted=n%2?0750:0640;
        PermissionPlan plan(mode,uid,gid,wanted,501,501);
        assert(plan.mode==((mode&07777)!=wanted)&&plan.owner==(uid!=501||gid!=501));
    }
    for(int64_t value:{std::numeric_limits<int64_t>::min(),int64_t(-1),int64_t(0),std::numeric_limits<int64_t>::max()}){
        auto first=Stamp::Present(UINT64_MAX,0,value,value,value,value,value),same=first;
        same.error=123;assert(first==same);same.kind=Stamp::Kind::Missing;assert(first!=same);
    }
    assert(!Stamp()&&Stamp::Missing(0)!=Stamp()&&Stamp::Missing(1)!=Stamp::Missing(2));
    for(size_t length:{size_t(1),size_t(63),size_t(64),size_t(65)}){
        std::u16string text(length,u'A');std::string bytes(length,'A');
        assert(TopicValid(length,[&](size_t i){return text[i];})==TLinkEventTopicValid(bytes.data(),bytes.size()));
    }
    for(uint64_t wanted:{uint64_t(0640),uint64_t(0750)}){
        PermissionPlan clean(0100000|wanted,501,501,wanted,501,501),special(0104000|wanted,501,501,wanted,501,501);
        assert(!clean.mode&&!clean.owner&&special.mode&&!special.owner);
    }
    for(size_t length:{size_t(0),size_t(65),SIZE_MAX})assert(!TopicValid(length,[](size_t)->uint16_t{assert(false);return 0;}));
    puts("Event metadata passed: 100k typed/legacy identity comparisons, all seven fields/absence/cache clearing, bounded UTF16/ASCII-wire topic parity and permission plans; signed/uint64 edges and zero over-limit reads.");
}
