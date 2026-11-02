#ifndef TLINK_SUPERVISOR_TASK_IO_H
#define TLINK_SUPERVISOR_TASK_IO_H
#include "TLinkVPNBrokerClientIO.h"
#include <vector>
namespace TLinkSupervisorTaskIO {
enum : size_t {MaxResponse=64*1024};
struct Reply {bool ok;std::vector<uint8_t> bytes;};
static inline TLinkVPNBrokerIngress::Window window(uint64_t now,int seconds){
    TLinkVPNBrokerIngress::Window value(now);
    const int milliseconds=seconds<=0?1000:(seconds>=30?30000:seconds*1000);
    value.deadline=TLinkHelperIO::Deadline(now,milliseconds);return value;
}
static inline Reply request(const TLinkHelperIO::Ops &io,const TLinkVPNBrokerClientIO::ConnectOps &connectOps,
    int fd,const uint8_t *command,size_t length,const TLinkVPNBrokerIngress::Window &budget){
    if(!command||!TLinkVPNBrokerClientIO::connect(io,connectOps,fd,budget).ok())return {false,{}};
    if(!TLinkHelperIO::writeBytes(io,fd,command,length,budget.deadline).ok())return {false,{}};
    std::vector<uint8_t> bytes;uint8_t chunk[2048];
    while(bytes.size()<MaxResponse){
        size_t count=0;
        if(!TLinkVPNBrokerIngress::readChunk(io,fd,chunk,std::min(sizeof(chunk),MaxResponse-bytes.size()),budget,count).ok())return {false,{}};
        if(!count)return {!bytes.empty(),std::move(bytes)};
        bytes.insert(bytes.end(),chunk,chunk+count);
        if(std::find(chunk,chunk+count,uint8_t('\n'))!=chunk+count)return {true,std::move(bytes)};
    }
    return {false,{}}; // A capped, unframed prefix must never become a probe ACK.
}
}
#endif
