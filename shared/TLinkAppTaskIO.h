#ifndef TLINK_APP_TASK_IO_H
#define TLINK_APP_TASK_IO_H
#include "TLinkVPNBrokerClientIO.h"
#include <cmath>
#include <vector>
namespace TLinkAppTaskIO {
enum : size_t {MaxResponse=1024*1024};
enum class Stage {None,Connect,Send,Read};
struct Reply {Stage stage;TLinkHelperIO::Result result;std::vector<uint8_t> bytes;};
static inline int timeoutMs(double seconds){
    if(!std::isfinite(seconds))return 0;
    if(seconds<=0)return 5000;
    if(seconds>=30)return 30000;
    return static_cast<int>(std::ceil(seconds*1000));
}
static inline TLinkVPNBrokerIngress::Window window(uint64_t now,double seconds){
    TLinkVPNBrokerIngress::Window value(now);value.deadline=TLinkHelperIO::Deadline(now,timeoutMs(seconds));return value;
}
static inline int nativeError(TLinkHelperIO::Result result){
    if(result.error)return result.error;
    if(result.code==TLinkHelperIO::Code::Timeout)return ETIMEDOUT;
    if(result.code==TLinkHelperIO::Code::TooLarge)return EMSGSIZE;
    return 0;
}
static inline Reply request(const TLinkHelperIO::Ops &io,const TLinkVPNBrokerClientIO::ConnectOps &connectOps,
    int fd,const uint8_t *command,size_t length,bool readReply,const TLinkVPNBrokerIngress::Window &budget){
    auto result=TLinkVPNBrokerClientIO::connect(io,connectOps,fd,budget);
    if(!result.ok())return {Stage::Connect,result,{}};
    result=TLinkHelperIO::writeBytes(io,fd,command,length,budget.deadline);
    if(!result.ok())return {Stage::Send,result,{}};
    if(!readReply)return {Stage::None,{TLinkHelperIO::Code::Ok},{}};
    std::vector<uint8_t> bytes;uint8_t chunk[2048];
    while(bytes.size()<MaxResponse){
        size_t count=0;
        result=TLinkVPNBrokerIngress::readChunk(io,fd,chunk,std::min(sizeof(chunk),MaxResponse-bytes.size()),budget,count);
        if(!result.ok())return {Stage::Read,result,{}};
        if(!count)return bytes.empty()?Reply{Stage::Read,{TLinkHelperIO::Code::Empty},{}}:Reply{Stage::None,{TLinkHelperIO::Code::Ok},std::move(bytes)};
        bytes.insert(bytes.end(),chunk,chunk+count);
        if(std::find(chunk,chunk+count,uint8_t('\n'))!=chunk+count)return {Stage::None,{TLinkHelperIO::Code::Ok},std::move(bytes)};
    }
    return {Stage::Read,{TLinkHelperIO::Code::TooLarge},{}};
}
}
#endif
