#include "../shared/TLinkLicenseReloadIO.h"
#include <cassert>
#include <cstring>
#include <string>
struct ReloadFixture {
    uint64_t tick=100,connectCost=0,sendCost=0,readCost=0;
    size_t chunk=8191,offset=0;
    int connectError=0,sendError=0,readError=0;
    bool block=false,interrupted=false;
    std::string response="0;;ok\r\n",sent;
    TLinkHelperIO::Ops ops(){return {this,
        [](void *p){return static_cast<ReloadFixture *>(p)->tick;},
        [](void *p,int,bool,int milliseconds,int &){auto &f=*static_cast<ReloadFixture *>(p);assert(milliseconds>0&&milliseconds<=250);f.tick+=milliseconds;return 0;},
        [](void *p,int,uint8_t *bytes,size_t capacity,int &error)->ptrdiff_t{
            auto &f=*static_cast<ReloadFixture *>(p);f.tick+=f.readCost;
            if(f.interrupted){f.interrupted=false;error=EINTR;return -1;}
            if(f.readError||f.block){error=f.block?EAGAIN:f.readError;return -1;}
            const size_t count=std::min(std::min(f.chunk,capacity),f.response.size()-f.offset);
            std::memcpy(bytes,f.response.data()+f.offset,count);f.offset+=count;return static_cast<ptrdiff_t>(count);
        },
        [](void *p,int,const uint8_t *bytes,size_t size,int &error)->ptrdiff_t{
            auto &f=*static_cast<ReloadFixture *>(p);f.tick+=f.sendCost;
            if(f.sendError){error=f.sendError;return -1;}
            const size_t count=std::min(size,f.chunk);f.sent.append(reinterpret_cast<const char *>(bytes),count);return static_cast<ptrdiff_t>(count);
        }};}
    TLinkVPNBrokerClientIO::ConnectOps connectOps(){return {this,
        [](void *p,int,int &error){auto &f=*static_cast<ReloadFixture *>(p);f.tick+=f.connectCost;error=f.connectError;return error?-1:0;},
        [](void *,int,int &){return 0;}};}
};
static inline TLinkLicenseReloadIO::Reply runReload(ReloadFixture &f){
    const auto base=f.ops();const auto window=TLinkLicenseReloadIO::window(f.tick);
    TLinkVPNBrokerClientIO::BoundedOps bounded(base,window);
    return TLinkLicenseReloadIO::request(bounded.ops(),f.connectOps(),1,window);
}
