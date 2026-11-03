#include "license-reload-fixture.h"
#include "../shared/TLinkAppTaskIO.h"
#include <limits>
#include <cstdio>
static TLinkAppTaskIO::Reply runApp(ReloadFixture &f,bool read=true,double seconds=2,const std::string &command="76reload\n"){
    const auto base=f.ops();const auto budget=TLinkAppTaskIO::window(f.tick,seconds);
    TLinkVPNBrokerClientIO::BoundedOps bounded(base,budget);
    return TLinkAppTaskIO::request(bounded.ops(),f.connectOps(),1,reinterpret_cast<const uint8_t *>(command.data()),command.size(),read,budget);
}
using Stage=TLinkAppTaskIO::Stage;
int main(){
    for(unsigned n=0;n<100000;++n){
        const double seconds=(n%40000)/1000.0;const int expected=seconds<=0?5000:(seconds>=30?30000:static_cast<int>(std::ceil(seconds*1000)));
        const uint64_t start=uint64_t(n)*30001;const auto budget=TLinkAppTaskIO::window(start,seconds);
        assert(budget.remaining(start)==expected&&!budget.remaining(start+expected));
    }
    assert(TLinkAppTaskIO::timeoutMs(-1)==5000&&TLinkAppTaskIO::timeoutMs(0.0000001)==1);
    for(double value:{std::numeric_limits<double>::infinity(),-std::numeric_limits<double>::infinity(),std::numeric_limits<double>::quiet_NaN()})assert(!TLinkAppTaskIO::timeoutMs(value));
    assert(TLinkAppTaskIO::timeoutMs(std::numeric_limits<double>::max())==30000);
    for(unsigned chunk=1;chunk<=32;++chunk){ReloadFixture f;f.chunk=chunk;f.interrupted=true;auto r=runApp(f);assert(r.stage==Stage::None&&f.sent=="76reload\n"&&std::string(r.bytes.begin(),r.bytes.end())==f.response);}
    {ReloadFixture f;f.block=true;auto r=runApp(f,false);assert(r.stage==Stage::None&&f.offset==0&&f.tick==100&&f.sent=="76reload\n");}
    {ReloadFixture f;f.response="0;;EOF";assert(runApp(f).stage==Stage::None);}
    {ReloadFixture f;f.response="";assert(runApp(f).result.code==TLinkHelperIO::Code::Empty);}
    {ReloadFixture f;f.response=std::string(TLinkAppTaskIO::MaxResponse-1,'x')+"\n";assert(runApp(f).bytes.size()==TLinkAppTaskIO::MaxResponse);}
    {ReloadFixture f;f.response=std::string(TLinkAppTaskIO::MaxResponse+2048,'x');auto r=runApp(f);assert(r.result.code==TLinkHelperIO::Code::TooLarge&&r.bytes.empty()&&f.offset==TLinkAppTaskIO::MaxResponse);}
    {ReloadFixture f;f.connectCost=2000;assert(runApp(f).stage==Stage::Connect&&f.sent.empty());}
    {ReloadFixture f;f.connectError=ECONNREFUSED;assert(runApp(f).stage==Stage::Connect);}
    {ReloadFixture f;f.sendError=EPIPE;assert(runApp(f).stage==Stage::Send);}
    {ReloadFixture f;f.readError=EIO;assert(runApp(f).stage==Stage::Read);}
    {ReloadFixture f;f.block=true;assert(runApp(f).result.code==TLinkHelperIO::Code::Timeout&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.readCost=400;auto r=runApp(f);assert(r.stage==Stage::Read&&r.bytes.empty()&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.connectCost=500;f.sendCost=100;f.readCost=300;assert(runApp(f).stage==Stage::Read);}
    {ReloadFixture f;f.sendCost=2000;assert(runApp(f,false).stage==Stage::Send);}
    {ReloadFixture f;f.tick=UINT64_MAX;assert(runApp(f).stage==Stage::Connect&&f.sent.empty());}
    assert(TLinkAppTaskIO::nativeError({TLinkHelperIO::Code::TooLarge})==EMSGSIZE&&TLinkAppTaskIO::nativeError({TLinkHelperIO::Code::Timeout})==ETIMEDOUT);
    puts("App socket core passed: 100k fractional/default/saturated windows, nonfinite rejection, exact writes, no-read send, LF/EOF/1-MiB cap, partial/fatal/trickle/backpressure and shared phase-time exhaustion.");
}
