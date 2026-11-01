#include "license-reload-fixture.h"
#include <cstdio>
using F=TLinkLicenseReloadIO::Failure;
int main(){
    for(unsigned n=0;n<100000;++n){const uint64_t start=uint64_t(n)*2003;auto w=TLinkLicenseReloadIO::window(start);assert(w.remaining(start)==2000&&!w.remaining(start+2000)&&!w.remaining(start?start-1:UINT64_MAX));}
    for(unsigned chunk=1;chunk<=20;++chunk){ReloadFixture f;f.chunk=chunk;f.interrupted=true;auto r=runReload(f);assert(r.failure==F::None&&f.sent=="76reload\r\n"&&std::string(r.bytes.begin(),r.bytes.end())==f.response);}
    {ReloadFixture f;f.response="0;;EOF";assert(runReload(f).failure==F::None);}
    {ReloadFixture f;f.response="";assert(runReload(f).failure==F::Read);}
    {ReloadFixture f;f.response=std::string(8190,'x')+"\n";assert(runReload(f).bytes.size()==8191);}
    {ReloadFixture f;f.response=std::string(8191,'x');auto r=runReload(f);assert(r.failure==F::Read&&r.bytes.empty());}
    {ReloadFixture f;f.connectCost=2000;assert(runReload(f).failure==F::Connect&&f.sent.empty());}
    {ReloadFixture f;f.connectError=ECONNREFUSED;assert(runReload(f).failure==F::Connect);}
    {ReloadFixture f;f.sendError=EPIPE;assert(runReload(f).failure==F::Send);}
    {ReloadFixture f;f.readError=EIO;assert(runReload(f).failure==F::Read);}
    {ReloadFixture f;f.block=true;assert(runReload(f).failure==F::Read&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.readCost=400;auto r=runReload(f);assert(r.failure==F::Read&&r.bytes.empty()&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.connectCost=500;f.sendCost=100;f.readCost=250;auto r=runReload(f);assert(r.failure==F::Read&&r.bytes.empty());}
    {ReloadFixture f;f.tick=UINT64_MAX;assert(runReload(f).failure==F::Connect&&f.sent.empty());}
    puts("License reload core passed: 100k shared 2s windows, exact partial writes, LF/EOF/cap framing, EINTR/backpressure/fatal errors, consumed phase time and no timeout prefix success.");
}
