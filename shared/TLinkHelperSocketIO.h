#ifndef TLINK_HELPER_SOCKET_IO_H
#define TLINK_HELPER_SOCKET_IO_H
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#endif
#if !defined(_WIN32)
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <cstring>
#endif
namespace TLinkHelperIO {
static const size_t MaxFrameBytes=1024*1024;
static const int ServerTimeoutMs=1000;
// Darwin peers share the kernel continuous clock, including time spent asleep.
static inline uint64_t nowMs(){
#if defined(__APPLE__)
    static const mach_timebase_info_data_t scale=[] {mach_timebase_info_data_t value{};if(mach_timebase_info(&value)!=KERN_SUCCESS)value={};return value;}();
    if(!scale.numer||!scale.denom)return UINT64_MAX; // fail closed, never change clock domains
    const __uint128_t ms=static_cast<__uint128_t>(mach_continuous_time())*scale.numer/(static_cast<uint64_t>(scale.denom)*1000000);
    return ms>UINT64_MAX?UINT64_MAX:static_cast<uint64_t>(ms);
#else
    return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
#endif
}
struct Deadline {
    uint64_t end=0;bool valid=false;
    Deadline(uint64_t now,int timeout){if(timeout<=0)return;valid=true;const uint64_t span=static_cast<uint64_t>(timeout>30000?30000:timeout);end=now>UINT64_MAX-span?UINT64_MAX:now+span;}
    int remaining(uint64_t now)const{return !valid||now>=end?0:static_cast<int>(std::min<uint64_t>(end-now,30000));}
};
enum class Code {Ok,InvalidTimeout,Timeout,Setup,Connect,Read,Write,TooLarge,Empty};
struct Result {Code code;int error=0;bool ok()const{return code==Code::Ok;}};
struct Ops {
    void *context;
    uint64_t (*now)(void *);
    int (*wait)(void *,int,bool,int,int &);
    ptrdiff_t (*receive)(void *,int,uint8_t *,size_t,int &);
    ptrdiff_t (*send)(void *,int,const uint8_t *,size_t,int &);
};
static inline bool wouldBlock(int error){return error==EAGAIN||error==EWOULDBLOCK;}
static inline Result waitReady(const Ops &ops,int fd,bool writing,const Deadline &deadline){
    if(!deadline.valid)return {Code::InvalidTimeout};
    for(;;){
        const int remaining=deadline.remaining(ops.now(ops.context));if(!remaining)return {Code::Timeout};
        int error=0;const int ready=ops.wait(ops.context,fd,writing,remaining,error);
        if(!deadline.remaining(ops.now(ops.context)))return {Code::Timeout};
        if(ready>0)return {Code::Ok};if(ready==0)return {Code::Timeout};
        if(error!=EINTR)return {writing?Code::Write:Code::Read,error};
    }
}
static inline Result writeBytes(const Ops &ops,int fd,const uint8_t *bytes,size_t length,const Deadline &deadline){
    if(!deadline.valid)return {Code::InvalidTimeout};
    while(length){
        if(!deadline.remaining(ops.now(ops.context)))return {Code::Timeout};
        int error=0;const ptrdiff_t count=ops.send(ops.context,fd,bytes,length,error);
        if(count>0){if(static_cast<size_t>(count)>length)return {Code::Write,EIO};bytes+=count;length-=static_cast<size_t>(count);continue;}
        if(count==0)return {Code::Write,EPIPE};if(error==EINTR)continue;
        if(!wouldBlock(error))return {Code::Write,error};
        const Result ready=waitReady(ops,fd,true,deadline);if(!ready.ok())return ready;
    }
    return deadline.remaining(ops.now(ops.context))?Result{Code::Ok}:Result{Code::Timeout};
}
static inline Result writeFrame(const Ops &ops,int fd,const uint8_t *bytes,size_t length,const Deadline &deadline){
    if(length>MaxFrameBytes)return {Code::TooLarge};
    Result result=writeBytes(ops,fd,bytes,length,deadline);if(!result.ok())return result;
    static const uint8_t newline='\n';return writeBytes(ops,fd,&newline,1,deadline);
}
static inline Result readFrame(const Ops &ops,int fd,std::vector<uint8_t> &frame,const Deadline &deadline){
    frame.clear();if(!deadline.valid)return {Code::InvalidTimeout};
    uint8_t buffer[4096];
    for(;;){
        if(!deadline.remaining(ops.now(ops.context)))return {Code::Timeout};
        int error=0;const ptrdiff_t count=ops.receive(ops.context,fd,buffer,sizeof(buffer),error);
        if(!deadline.remaining(ops.now(ops.context)))return {Code::Timeout};
        if(count>0){
            if(static_cast<size_t>(count)>sizeof(buffer))return {Code::Read,EIO};
            const auto end=buffer+count;const auto newline=std::find(buffer,end,uint8_t('\n'));
            const size_t length=static_cast<size_t>(newline-buffer);
            if(length>MaxFrameBytes-frame.size())return {Code::TooLarge};
            frame.insert(frame.end(),buffer,newline);
            if(newline!=end)return frame.empty()?Result{Code::Empty}:Result{Code::Ok};
            continue;
        }
        // Preserve the legacy one-command EOF frame. Timeouts never complete a prefix.
        if(count==0)return frame.empty()?Result{Code::Empty}:Result{Code::Ok};
        if(error==EINTR)continue;if(!wouldBlock(error))return {Code::Read,error};
        const Result ready=waitReady(ops,fd,false,deadline);if(!ready.ok())return ready;
    }
}
#if !defined(_WIN32)
class Socket {
    int fd_;
public:
    explicit Socket(int fd):fd_(fd){}
    ~Socket(){close();}
    Socket(const Socket &)=delete;Socket &operator=(const Socket &)=delete;
    int fd()const{return fd_;}
    int release(){const int fd=fd_;fd_=-1;return fd;}
    void close(){if(fd_>=0){const int fd=fd_;fd_=-1;::close(fd);}}
    Result prepare(){
        if(fd_<0)return {Code::Setup,EBADF};
        const int flags=::fcntl(fd_,F_GETFL,0),descriptor=::fcntl(fd_,F_GETFD,0);
        if(flags<0||descriptor<0||::fcntl(fd_,F_SETFL,flags|O_NONBLOCK)<0||::fcntl(fd_,F_SETFD,descriptor|FD_CLOEXEC)<0)return {Code::Setup,errno};
#ifdef SO_NOSIGPIPE
        const int yes=1;if(::setsockopt(fd_,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes))<0)return {Code::Setup,errno};
#endif
        return {Code::Ok};
    }
};
static inline int posixWait(void *,int fd,bool writing,int timeout,int &error){
    pollfd item{fd,static_cast<short>(writing?POLLOUT:POLLIN),0};const int count=::poll(&item,1,timeout);
    if(count<0){error=errno;return -1;}if(count==0)return 0;
    if(item.revents&POLLNVAL){error=EBADF;return -1;}
    // HUP/ERR must reach recv/send/SO_ERROR so buffered bytes and EOF remain observable.
    return 1;
}
static inline ptrdiff_t posixReceive(void *,int fd,uint8_t *bytes,size_t length,int &error){const auto count=::recv(fd,bytes,length,0);if(count<0)error=errno;return count;}
static inline ptrdiff_t posixSend(void *,int fd,const uint8_t *bytes,size_t length,int &error){
    int flags=0;
#ifdef MSG_NOSIGNAL
    flags|=MSG_NOSIGNAL;
#endif
    const auto count=::send(fd,bytes,length,flags);if(count<0)error=errno;return count;
}
static inline Ops posixOps(){return {nullptr,[](void *){return nowMs();},posixWait,posixReceive,posixSend};}
static inline Result connectUnix(Socket &socket,const char *path,const Deadline &deadline){
    if(!deadline.valid)return {Code::InvalidTimeout};if(!deadline.remaining(nowMs()))return {Code::Timeout};
    sockaddr_un address{};address.sun_family=AF_UNIX;
    if(!path||std::strlen(path)>=sizeof(address.sun_path))return {Code::Connect,ENAMETOOLONG};
    std::memcpy(address.sun_path,path,std::strlen(path)+1);
    if(::connect(socket.fd(),reinterpret_cast<sockaddr *>(&address),sizeof(address))==0)return deadline.remaining(nowMs())?Result{Code::Ok}:Result{Code::Timeout};
    const int error=errno;
    if(error!=EINPROGRESS&&error!=EALREADY&&error!=EINTR)return {Code::Connect,error};
    Result ready=waitReady(posixOps(),socket.fd(),true,deadline);if(!ready.ok())return ready.code==Code::Timeout?ready:Result{Code::Connect,ready.error};
    int status=0;socklen_t length=sizeof(status);
    if(::getsockopt(socket.fd(),SOL_SOCKET,SO_ERROR,&status,&length)!=0)return {Code::Connect,errno};
    if(status)return {Code::Connect,status};
    sockaddr_un peer{};length=sizeof(peer);
    if(::getpeername(socket.fd(),reinterpret_cast<sockaddr *>(&peer),&length)!=0)return {Code::Connect,errno};
    return deadline.remaining(nowMs())?Result{Code::Ok}:Result{Code::Timeout};
}
#endif
} // namespace TLinkHelperIO
#ifdef __OBJC__
#import <Foundation/Foundation.h>
static inline NSString *TLinkHelperIOError(TLinkHelperIO::Result result){
    using C=TLinkHelperIO::Code;
    switch(result.code){case C::Ok:return nil;case C::InvalidTimeout:return @"invalid_timeout";case C::Timeout:return @"io_timeout";
        case C::Setup:return @"socket_setup_failed";case C::Connect:return @"connect_failed";case C::Read:return @"read_failed";
        case C::Write:return @"write_failed";case C::TooLarge:return @"frame_too_large";case C::Empty:return @"empty_frame";}
    return @"socket_io_failed";
}
static inline NSDictionary *TLinkHelperIOFailure(TLinkHelperIO::Result result){return @{@"ok":@(false),@"error":TLinkHelperIOError(result)?:@"socket_io_failed",@"errno":@(result.error)};}
#endif
#endif
