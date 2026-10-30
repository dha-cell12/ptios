#ifndef TLINK_VPN_BROKER_CLIENT_IO_H
#define TLINK_VPN_BROKER_CLIENT_IO_H
#include "TLinkVPNBrokerIngress.h"
#if !defined(_WIN32)
#include <arpa/inet.h>
#include <netinet/in.h>
#endif

namespace TLinkVPNBrokerClientIO {
using TLinkVPNBrokerIngress::Window;
using namespace TLinkHelperIO;
// Keep each kernel poll short enough to recheck continuous time after sleep.
// No new deadline is created when bytes arrive or a syscall is interrupted.
class BoundedOps {
    Ops base_;const Window &window_;
    const void *stopContext_;bool (*stopped_)(const void *);
    bool stopped()const{return stopped_&&stopped_(stopContext_);}
    static uint64_t now(void *p){
        auto &self=*static_cast<BoundedOps *>(p);const uint64_t time=self.base_.now(self.base_.context);
        return !self.stopped()&&self.window_.remaining(time)?time:UINT64_MAX;
    }
    static int wait(void *p,int fd,bool writing,int timeout,int &error){
        auto &self=*static_cast<BoundedOps *>(p);const Deadline phase(now(p),timeout);
        for(;;){
            const int left=std::min(phase.remaining(now(p)),self.window_.remaining(self.base_.now(self.base_.context)));
            if(!left)return 0;
            const int ready=self.base_.wait(self.base_.context,fd,writing,std::min(left,250),error);
            if(self.stopped()||!self.window_.remaining(self.base_.now(self.base_.context)))return 0;
            if(ready!=0)return ready;
        }
    }
    static ptrdiff_t receive(void *p,int fd,uint8_t *bytes,size_t count,int &error){
        auto &self=*static_cast<BoundedOps *>(p);if(self.stopped()){error=ECANCELED;return -1;}
        return self.base_.receive(self.base_.context,fd,bytes,count,error);
    }
    static ptrdiff_t send(void *p,int fd,const uint8_t *bytes,size_t count,int &error){
        auto &self=*static_cast<BoundedOps *>(p);if(self.stopped()){error=ECANCELED;return -1;}
        return self.base_.send(self.base_.context,fd,bytes,count,error);
    }
public:
    // Both context and window are borrowed for this synchronous invocation only.
    BoundedOps(Ops base,const Window &window,const void *stopContext=nullptr,bool (*stopped)(const void *)=nullptr)
        :base_(base),window_(window),stopContext_(stopContext),stopped_(stopped){}
    Ops ops(){return {this,now,wait,receive,send};}
};
struct ConnectOps {
    void *context;
    int (*begin)(void *,int,int &);
    int (*finish)(void *,int,int &);
};
static inline Result connect(const Ops &io,const ConnectOps &connectOps,int fd,const Window &window){
    if(!window.remaining(io.now(io.context)))return {Code::Timeout};
    int error=0;const int result=connectOps.begin(connectOps.context,fd,error);
    if(!window.remaining(io.now(io.context)))return {Code::Timeout};
    if(result==0)return {Code::Ok};
    if(error!=EINPROGRESS&&error!=EALREADY&&error!=EINTR)return {Code::Connect,error};
    const Result ready=waitReady(io,fd,true,window.deadline);
    if(!ready.ok())return ready.code==Code::Timeout?ready:Result{Code::Connect,ready.error};
    const int status=connectOps.finish(connectOps.context,fd,error);
    if(!window.remaining(io.now(io.context)))return {Code::Timeout};
    return status==0?Result{Code::Ok}:Result{Code::Connect,error};
}
#if !defined(_WIN32)
static inline ConnectOps posixConnectOps(){
    return {nullptr,
        [](void *,int fd,int &error){
            sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(6014);
            ::inet_pton(AF_INET,"127.0.0.1",&address.sin_addr);
            const int result=::connect(fd,reinterpret_cast<sockaddr *>(&address),sizeof(address));
            if(result<0)error=errno;return result;
        },
        [](void *,int fd,int &error){
            int status=0;socklen_t length=sizeof(status);
            if(::getsockopt(fd,SOL_SOCKET,SO_ERROR,&status,&length)!=0){error=errno;return -1;}
            if(status){error=status;return -1;}
            sockaddr_in peer{};length=sizeof(peer);
            if(::getpeername(fd,reinterpret_cast<sockaddr *>(&peer),&length)!=0){error=errno;return -1;}
            return 0;
        }};
}
#endif
}
#endif
