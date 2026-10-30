#ifndef TLINK_VPN_BROKER_INGRESS_H
#define TLINK_VPN_BROKER_INGRESS_H
#include "TLinkHelperSocketIO.h"

namespace TLinkVPNBrokerIngress {
enum : int {TimeoutMs=30000};
struct Window {
    uint64_t acceptedAt;
    TLinkHelperIO::Deadline deadline;
    explicit Window(uint64_t accepted):acceptedAt(accepted),deadline(accepted,TimeoutMs){}
    int remaining(uint64_t now)const{
        return acceptedAt==UINT64_MAX||now<acceptedAt?0:deadline.remaining(now);
    }
};
// One bounded chunk; LF/EOF/cap framing remains with the original caller.
// The receive adapter must be nonblocking. Never accept partial data on faults.
static inline TLinkHelperIO::Result readChunk(
    const TLinkHelperIO::Ops &ops,int fd,uint8_t *bytes,size_t capacity,
    const Window &window,size_t &count)
{
    using namespace TLinkHelperIO;
    count=0;
    if(!bytes||!capacity)return {Code::Read,EINVAL};
    for(;;){
        if(!window.remaining(ops.now(ops.context)))return {Code::Timeout};
        int error=0;
        const ptrdiff_t received=ops.receive(ops.context,fd,bytes,capacity,error);
        if(!window.remaining(ops.now(ops.context)))return {Code::Timeout};
        if(received>=0){
            if(static_cast<size_t>(received)>capacity)return {Code::Read,EIO};
            count=static_cast<size_t>(received);return {Code::Ok};
        }
        if(error==EINTR)continue;
        if(!wouldBlock(error))return {Code::Read,error};
        const Result ready=waitReady(ops,fd,false,window.deadline);
        if(!ready.ok())return ready;
    }
}
#if !defined(_WIN32)
static inline TLinkHelperIO::Ops posixReadOps(){
    auto ops=TLinkHelperIO::posixOps();
    ops.receive=[](void *,int fd,uint8_t *bytes,size_t count,int &error)->ptrdiff_t{
        const ssize_t received=::recv(fd,bytes,count,MSG_DONTWAIT);
        if(received<0)error=errno;
        return received;
    };
    return ops;
}
#endif
}
#endif
