#import <Foundation/Foundation.h>
#include "../shared/TLinkVPNBrokerClientIO.h"
#include "../shared/TLinkNativeBudget.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <functional>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
namespace Client=TLinkVPNBrokerClientIO;
using namespace TLinkHelperIO;
static uint64_t fixtureTime=100,connectCost=0,sendCost=0,readCost=0;
static bool socketFault=false,prepareFault=false,realPeer=false,pollReady=false;
static int connectFault=0,sendFault=0,readFault=0,throwRead=0;
static size_t responseOffset=0,chunk=SIZE_MAX,faultAfter=SIZE_MAX;
static unsigned opens=0,closes=0,sendCalls=0,receiveCalls=0,waitCalls=0;
static std::set<int> live;
static std::string responseBytes,sentBytes;
static uint16_t peerPort=0;
static std::function<void()> onConnect,onSend,onRead,onPoll,onFinish;
static int fixtureSocket(int domain,int type,int protocol){
    if(socketFault){errno=EMFILE;return -1;}
    const int fd=::socket(domain,type,protocol);assert(fd>=0&&live.insert(fd).second);++opens;return fd;
}
static void fixtureClose(int fd){assert(live.erase(fd)==1);++closes;assert(::close(fd)==0);}
class FixtureSocket {
    int fd_;
public:
    explicit FixtureSocket(int fd):fd_(fd){}
    ~FixtureSocket(){close();}
    Result prepare(){if(prepareFault)return {Code::Setup,EIO};Socket descriptor(fd_);const Result result=descriptor.prepare();descriptor.release();return result;}
    void close(){if(fd_>=0){const int fd=fd_;fd_=-1;fixtureClose(fd);}}
};
static int fixtureConnect(int fd,const sockaddr *address,socklen_t length){
    (void)fd;(void)address;(void)length;fixtureTime+=connectCost;
    if(onConnect)onConnect();
    if(connectFault){errno=connectFault;return -1;}return 0;
}
static ssize_t fixtureSend(int fd,const void *bytes,size_t count,int flags){
    (void)fd;(void)flags;++sendCalls;fixtureTime+=sendCost;
    if(onSend)onSend();
    if(sendFault){errno=sendFault;return -1;}
    const size_t n=std::min(count,chunk);sentBytes.append(static_cast<const char *>(bytes),n);return static_cast<ssize_t>(n);
}
static ssize_t fixtureReceive(int fd,void *bytes,size_t capacity,int flags){
    (void)fd;(void)flags;++receiveCalls;fixtureTime+=readCost;
    if(onRead)onRead();
    if(throwRead==1)[NSException raise:@"ReadFixture" format:@"read"];
    if(throwRead==2)throw std::runtime_error("read");
    if(readFault&&responseOffset>=faultAfter){errno=readFault;return -1;}
    const size_t n=std::min(std::min(capacity,chunk),responseBytes.size()-responseOffset);
    std::memcpy(bytes,responseBytes.data()+responseOffset,n);responseOffset+=n;return static_cast<ssize_t>(n);
}
static Ops fixtureOps(){
    return {nullptr,
        [](void *){return realPeer?nowMs():fixtureTime;},
        [](void *,int fd,bool writing,int timeout,int &error){
            assert(timeout>0&&timeout<=250);++waitCalls;
            if(onPoll)onPoll();
            if(realPeer)return posixWait(nullptr,fd,writing,timeout,error);
            if(pollReady)return 1;
            fixtureTime+=static_cast<uint64_t>(timeout);return 0;
        },
        [](void *,int fd,uint8_t *bytes,size_t count,int &error)->ptrdiff_t{
            if(realPeer)return posixReceive(nullptr,fd,bytes,count,error);
            const ssize_t result=fixtureReceive(fd,bytes,count,0);if(result<0)error=errno;return result;
        },
        [](void *,int fd,const uint8_t *bytes,size_t count,int &error)->ptrdiff_t{
            if(realPeer)return posixSend(nullptr,fd,bytes,count,error);
            const ssize_t result=fixtureSend(fd,bytes,count,0);if(result<0)error=errno;return result;
        }};
}
static Client::ConnectOps fixtureConnectOps(){
    return {nullptr,
        [](void *,int fd,int &error){
            int result;
            if(realPeer){sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(peerPort);address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);result=::connect(fd,reinterpret_cast<sockaddr *>(&address),sizeof(address));}
            else result=fixtureConnect(fd,nullptr,0);
            if(result<0)error=errno;return result;
        },
        [](void *,int fd,int &error){if(onFinish)onFinish();if(realPeer)return Client::posixConnectOps().finish(nullptr,fd,error);return 0;}};
}
namespace Current {
#include "VPNClientUnderTest.inc"
}
namespace Legacy {
#include "VPNClientLegacy.inc"
}
static void reset(const std::string &response){
    assert(live.empty()&&opens==closes);fixtureTime=100;connectCost=sendCost=readCost=0;
    socketFault=prepareFault=realPeer=pollReady=false;connectFault=sendFault=readFault=throwRead=0;
    responseOffset=0;chunk=faultAfter=SIZE_MAX;sendCalls=receiveCalls=waitCalls=0;responseBytes=response;sentBytes.clear();
    onConnect={};onSend={};onRead={};onPoll={};onFinish={};
}
static void same(NSString *a,NSString *b){assert((a==b)||[a isEqualToString:b]);}
static void parityCases(){
    const std::vector<std::string> replies={"0;;1\r\n","0;;0\r\n","0;;\r\n","0;;a;;b\r\n","-1;;vpn_broker_busy\r\n","-1;;denied","bad\n","0;;1",std::string("0;;a\0b\r\n",8),"0;;\xff\n","0;;x\ntrailing",""};
    for(const std::string &reply:replies)for(size_t limit:std::vector<size_t>{1,7,4096})for(NSString *command in @[@"query",@"connect",@"disconnect",@"diagnostics",@"ảnh;测试"]){@autoreleasepool{
        reset(reply);chunk=limit;NSString *oldError=nil;NSString *expected=Legacy::zx_vpnBrokerRequest(command,&oldError);const std::string expectedSend=sentBytes;
        reset(reply);chunk=limit;NSString *error=nil;NSString *actual=Current::zx_vpnBrokerRequest(command,&error);
        same(actual,expected);same(error,oldError);assert(sentBytes==expectedSend&&live.empty()&&opens==closes);
    }}
    reset("0;;1\r\n");NSString *error=@"unchanged";same(Current::zx_vpnBrokerRequest(nil,&error),@"1");same(error,@"unchanged");assert(sentBytes=="\r\n");
}
static void failureCases(){
    reset("0;;1\r\n");socketFault=true;NSString *error=nil;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_socket_failed");
    reset("0;;1\r\n");prepareFault=true;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_socket_failed");assert(live.empty());
    reset("0;;1\r\n");connectFault=ECONNREFUSED;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_unavailable");
    reset("0;;1\r\n");sendFault=EPIPE;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_send_failed");
    reset("0;;1\r\n");chunk=4;faultAfter=4;readFault=ECONNRESET;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_no_response");assert(responseOffset==4&&live.empty());
    reset("0;;1\r\n");connectCost=10000;sendCost=10000;readCost=5000;chunk=4;
    // Two write chunks consume the remaining budget; no response is accepted.
    assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_send_failed");assert(receiveCalls==0);
    reset("0;;1\r\n");chunk=1;readCost=5000;assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_no_response");assert(fixtureTime==30100&&live.empty());
    reset("0;;1\r\n");readFault=EAGAIN;faultAfter=0;assert(!Current::zx_vpnBrokerRequest(@"query",&error));assert(fixtureTime==30100&&waitCalls==120);same(error,@"vpn_broker_no_response");
    for(unsigned kind=1;kind<=2;++kind){reset("0;;1\r\n");throwRead=static_cast<int>(kind);bool caught=false;
        try{@try{(void)Current::zx_vpnBrokerRequest(@"query",&error);}@catch(NSException *exception){(void)exception;caught=true;}}catch(...){caught=true;}
        assert(caught&&live.empty()&&opens==closes);
    }
    // Real EOF and the legacy size cap remain framing boundaries; faults/timeouts do not.
    reset("0;;"+std::string(1024*1024,'x'));chunk=4093;NSString *body=Current::zx_vpnBrokerRequest(@"query",&error);assert(body.length==1024*1024-3&&responseOffset==1024*1024);
    for(unsigned n=0;n<128;++n){reset("0;;1\r\n");same(Current::zx_vpnBrokerRequest(@"query",nullptr),@"1");assert(live.empty());}
}
static void realSocketCase(){
    reset("");realPeer=true;
    const int server=::socket(AF_INET,SOCK_STREAM,0);assert(server>=0);sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(::bind(server,reinterpret_cast<sockaddr *>(&address),sizeof(address))==0&&::listen(server,1)==0);
    socklen_t length=sizeof(address);assert(::getsockname(server,reinterpret_cast<sockaddr *>(&address),&length)==0);peerPort=ntohs(address.sin_port);
    std::thread peer([server]{
        int error=0;assert(posixWait(nullptr,server,false,5000,error)==1);const int fd=::accept(server,nullptr,nullptr);assert(fd>=0);
        Socket owner(fd);assert(owner.prepare().ok());const Ops io=posixOps();const Deadline deadline(nowMs(),5000);
        std::vector<uint8_t> request;assert(readFrame(io,fd,request,deadline).ok());assert(std::string(request.begin(),request.end())=="query\r");
        const std::string reply="0;;1\r\n";assert(writeBytes(io,fd,reinterpret_cast<const uint8_t *>(reply.data()),reply.size(),deadline).ok());
    });
    NSString *error=nil;NSString *result=Current::zx_vpnBrokerRequest(@"query",&error);peer.join();assert(::close(server)==0);
    same(result,@"1");assert(!error&&live.empty()&&opens==closes);realPeer=false;
}
static void callerCases(){
    NSString *error=nil;
    for(unsigned kind=0;kind<3;++kind){
        reset("0;;1\r\n");auto token=std::make_shared<TLinkNativeCancellation>();
        auto budget=std::make_shared<TLinkNativeBudget>(token,kind==1?TLinkNativeNowNs()-1:0,kind==2?1:4096);
        if(kind==0)token->cancel();if(kind==2)assert(!budget->outputAllowed(2));
        const unsigned before=opens;TLinkNativeBudgetScope scope(budget);
        assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_unavailable");
        assert(opens==before&&live.empty()&&sendCalls==0&&receiveCalls==0);
    }
    for(unsigned stage=0;stage<5;++stage){
        reset("0;;1\r\n");auto token=std::make_shared<TLinkNativeCancellation>();
        auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
        auto budget=std::make_shared<TLinkNativeBudget>(0,parent);TLinkNativeBudgetScope scope(budget);
        const auto stop=[token]{token->cancel();};
        if(stage==0)onConnect=stop;
        if(stage==1){connectFault=EINPROGRESS;pollReady=true;onFinish=stop;}
        if(stage==2)onSend=stop;
        if(stage==3)onRead=stop;
        if(stage==4){readFault=EAGAIN;faultAfter=0;onPoll=stop;}
        assert(!Current::zx_vpnBrokerRequest(@"query",&error));
        same(error,stage<2?@"vpn_broker_unavailable":stage==2?@"vpn_broker_send_failed":@"vpn_broker_no_response");
        assert(budget->reason()==TLinkNativeStop::Cancelled&&live.empty()&&opens==closes);
        if(stage<2)assert(sendCalls==0&&receiveCalls==0);
        if(stage==2)assert(sentBytes=="query\r\n"&&receiveCalls==0); // Committed bytes are not replayed or rolled back.
        if(stage==4)assert(waitCalls==1&&fixtureTime==350);
    }
    reset("0;;1\r\n");auto token=std::make_shared<TLinkNativeCancellation>();
    auto parent=std::make_shared<TLinkNativeBudget>(token,0,4096);
    auto child=std::make_shared<TLinkNativeBudget>(0,parent);
    // A nested scope during a provider call must not replace the captured caller.
    std::unique_ptr<TLinkNativeBudgetScope> nested;
    onRead=[token,&nested]{nested.reset(new TLinkNativeBudgetScope(std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,4096)));token->cancel();assert(!TLinkNativeStopped());};
    {TLinkNativeBudgetScope scope(child);assert(!Current::zx_vpnBrokerRequest(@"query",&error));same(error,@"vpn_broker_no_response");assert(!TLinkNativeStopped());nested.reset();assert(TLinkNativeStopped());}
    reset("0;;1\r\n");auto expiredParent=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeNowNs()-1,4096);
    {TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(0,expiredParent));const unsigned before=opens;assert(!Current::zx_vpnBrokerRequest(@"query",&error));assert(opens==before);}
    reset("0;;1\r\n");
    {TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(token,TLinkNativeNowNs()-1,4096,true));same(Current::zx_vpnBrokerRequest(@"query",nullptr),@"1");}
    assert(!TLinkCurrentNativeBudget()&&live.empty());
}
int main(){@autoreleasepool{
    puts("VPN client Foundation: actual/frozen transport, real scoped sockets and controlled time/peer faults");
    parityCases();failureCases();realSocketCase();callerCases();
    puts("VPN client Foundation passed: 180 frozen wire/EOF/Unicode/error cases, exact request/1MiB cap, setup/connect/send/read faults, trickle/deadline/prefix rejection, NS/C++ descriptor unwind, 128 lifecycles and real loopback nonblocking request/reply. IPC isolation/device qualification pending.");
    puts("VPN captured caller Foundation passed: pre-cancel/native deadline/output before socket, parent cancellation during connect/completion/send/read/one poll, exact close and no replay, nested TLS isolation and inherited cleanup policy. Broker operation cancellation remains open.");
}return 0;}
