#include "license-reload-fixture.h"
#include "../shared/TLinkSupervisorTaskIO.h"
#include <climits>
#include <cstdio>
static TLinkSupervisorTaskIO::Reply runTask(ReloadFixture &f,const std::string &command="97\n",int seconds=2){
    const auto base=f.ops();const auto budget=TLinkSupervisorTaskIO::window(f.tick,seconds);
    TLinkVPNBrokerClientIO::BoundedOps bounded(base,budget);
    return TLinkSupervisorTaskIO::request(bounded.ops(),f.connectOps(),1,
        reinterpret_cast<const uint8_t *>(command.data()),command.size(),budget);
}
int main(){
    for(unsigned n=0;n<100000;++n){
        const uint64_t start=uint64_t(n)*2003;
        for(int seconds:{INT_MIN,-1,0,1,2,29,30,INT_MAX}){
            const int expected=seconds<=0?1000:(seconds>=30?30000:seconds*1000);
            const auto budget=TLinkSupervisorTaskIO::window(start,seconds);
            assert(budget.remaining(start)==expected&&!budget.remaining(start+expected));
        }
    }
    for(const std::string &command:{std::string("60\n"),std::string("97\n"),std::string("96\n"),std::string("\n")}){
        for(unsigned chunk=1;chunk<=32;++chunk){
            ReloadFixture f;f.chunk=chunk;f.interrupted=true;auto reply=runTask(f,command);
            assert(reply.ok&&f.sent==command&&std::string(reply.bytes.begin(),reply.bytes.end())==f.response);
        }
    }
    {ReloadFixture f;f.response="0;;EOF";assert(runTask(f).ok);}
    {ReloadFixture f;f.response="";assert(!runTask(f).ok);}
    {ReloadFixture f;f.response=std::string(65535,'x')+"\n";assert(runTask(f).bytes.size()==65536);}
    for(size_t size:{size_t(65536),size_t(67584)}){
        ReloadFixture f;f.response=std::string(size,'x');auto reply=runTask(f);assert(!reply.ok&&reply.bytes.empty()&&f.offset==65536);
    }
    {ReloadFixture f;f.connectCost=2000;assert(!runTask(f).ok&&f.sent.empty());}
    {ReloadFixture f;f.connectError=ECONNREFUSED;assert(!runTask(f).ok);}
    {ReloadFixture f;f.sendError=EPIPE;assert(!runTask(f).ok);}
    {ReloadFixture f;f.readError=EIO;assert(!runTask(f).ok);}
    {ReloadFixture f;f.block=true;assert(!runTask(f).ok&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.readCost=400;auto reply=runTask(f);assert(!reply.ok&&reply.bytes.empty()&&f.tick==2100);}
    {ReloadFixture f;f.chunk=1;f.connectCost=500;f.sendCost=200;f.readCost=450;assert(!runTask(f).ok&&f.tick==2100);}
    {ReloadFixture f;f.tick=UINT64_MAX;assert(!runTask(f).ok&&f.sent.empty());}
    puts("Supervisor task core passed: 800k timeout plans, exact partial command writes, LF/EOF/64-KiB boundaries, consumed connect/write/read budget, trickle/backpressure/fatal faults and no partial timeout ACK.");
}
