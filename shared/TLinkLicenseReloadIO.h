#ifndef TLINK_LICENSE_RELOAD_IO_H
#define TLINK_LICENSE_RELOAD_IO_H
#include "TLinkVPNBrokerClientIO.h"
namespace TLinkLicenseReloadIO {
enum class Failure {None,Connect,Send,Read};
struct Reply {Failure failure;std::vector<uint8_t> bytes;};
enum : size_t {MaxResponse=8191};
static inline TLinkVPNBrokerIngress::Window window(uint64_t now){
    TLinkVPNBrokerIngress::Window value(now);
    value.deadline=TLinkHelperIO::Deadline(now,2000);return value;
}
static inline Reply request(const TLinkHelperIO::Ops &io,const TLinkVPNBrokerClientIO::ConnectOps &connectOps,
    int fd,const TLinkVPNBrokerIngress::Window &budget){
    if(!TLinkVPNBrokerClientIO::connect(io,connectOps,fd,budget).ok())return {Failure::Connect,{}};
    static const uint8_t command[]="76reload\r\n";
    if(!TLinkHelperIO::writeBytes(io,fd,command,sizeof(command)-1,budget.deadline).ok())return {Failure::Send,{}};
    std::vector<uint8_t> bytes;uint8_t chunk[1024];
    while(bytes.size()<MaxResponse){
        size_t count=0;
        if(!TLinkVPNBrokerIngress::readChunk(io,fd,chunk,std::min(sizeof(chunk),MaxResponse-bytes.size()),budget,count).ok())return {Failure::Read,{}};
        if(!count)return bytes.empty()?Reply{Failure::Read,{}}:Reply{Failure::None,std::move(bytes)};
        bytes.insert(bytes.end(),chunk,chunk+count);
        if(std::find(chunk,chunk+count,uint8_t('\n'))!=chunk+count)return {Failure::None,std::move(bytes)};
    }
    return {Failure::Read,{}}; // Never decode an unframed capped prefix as success.
}
}
#endif
