#import <Foundation/Foundation.h>
#import "../stream-app/app/TLinkSocketClient.h"
#import "LegacySocketClient.h"
#include "license-reload-fixture.h"
#include "../shared/TLinkAppTaskIO.h"
#include <cstdio>
#include <stdexcept>
#include <limits>
#include <fcntl.h>
#include <sys/time.h>
static ReloadFixture fixture;
static unsigned opens=0,closes=0,readFault=0;
static bool socketFailure=false,prepareFailure=false;
static int fixtureSocket(int domain,int type,int protocol){
    if(socketFailure){errno=EACCES;return -1;}
    const int fd=::socket(domain,type,protocol);assert(fd>=0);++opens;return fd;
}
static int fixtureClose(int fd){const int result=::close(fd);assert(result==0);++closes;return result;}
class FixtureSocket {
    int fd_;
public:
    explicit FixtureSocket(int fd):fd_(fd){}
    ~FixtureSocket(){close();}
    int fd()const{return fd_;}
    void close(){if(fd_>=0){fixtureClose(fd_);fd_=-1;}}
    TLinkHelperIO::Result prepare(){
        if(prepareFailure)return {TLinkHelperIO::Code::Setup,EIO};
        TLinkHelperIO::Socket actual(fd_);const auto result=actual.prepare();actual.release();
        assert((::fcntl(fd_,F_GETFL,0)&O_NONBLOCK)&&(::fcntl(fd_,F_GETFD,0)&FD_CLOEXEC));return result;
    }
};
static TLinkHelperIO::Ops fixtureOps(){
    auto ops=fixture.ops();ops.receive=[](void *p,int fd,uint8_t *bytes,size_t count,int &error)->ptrdiff_t{
        if(readFault==1)[NSException raise:@"AppSocketFixture" format:@"read"];
        if(readFault==2)throw std::runtime_error("read");
        return static_cast<ReloadFixture *>(p)->ops().receive(p,fd,bytes,count,error);
    };return ops;
}
#include "AppSocketUnderTest.inc"
static int legacyOptions(int fd,int level,int option,const void *value,socklen_t count){
    (void)fd;assert(level==SOL_SOCKET&&(option==SO_RCVTIMEO||option==SO_SNDTIMEO)&&count==sizeof(timeval));
    const timeval *time=static_cast<const timeval *>(value);assert(time->tv_sec>0||time->tv_usec>0);return 0;
}
static int legacyConnect(int fd,const sockaddr *address,socklen_t count){
    (void)fd;assert(count==sizeof(sockaddr_in));const auto *endpoint=reinterpret_cast<const sockaddr_in *>(address);
    assert(endpoint->sin_family==AF_INET&&ntohs(endpoint->sin_port)==6000);
    if(fixture.connectError){errno=fixture.connectError;return -1;}return 0;
}
static ssize_t legacySend(int fd,const void *bytes,size_t count,int flags){
    (void)flags;int error=0;const auto ops=fixture.ops();
    const auto result=ops.send(ops.context,fd,static_cast<const uint8_t *>(bytes),count,error);errno=error;return result;
}
static ssize_t legacyReceive(int fd,void *bytes,size_t count,int flags){
    (void)flags;int error=0;const auto ops=fixture.ops();
    const auto result=ops.receive(ops.context,fd,static_cast<uint8_t *>(bytes),count,error);errno=error;return result;
}
#define socket fixtureSocket
#define close fixtureClose
#define setsockopt legacyOptions
#define connect legacyConnect
#define send legacySend
#define recv legacyReceive
#include "AppSocketLegacy.inc"
#undef recv
#undef send
#undef connect
#undef setsockopt
#undef close
#undef socket
static void reset(){assert(opens==closes);fixture=ReloadFixture{};socketFailure=prepareFailure=false;readFault=0;errno=0;}
static void response(NSString *text){NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];fixture.response.assign(data.length?static_cast<const char *>(data.bytes):"",data.length);}
static void parityCases(){
    unichar nul=0;NSString *zero=[NSString stringWithCharacters:&nul length:1];
    for(NSString *line in @[@"76reload",@"60\n",@"19path;;script.js\r\n",@"",@"Ứng dụng 测试 😀",[@"97" stringByAppendingString:zero]]){
        for(NSString *wire in @[@"0;;ok\r\n",@"-1;;denied\r\n",@" 0;;Ứng dụng 测试 😀\r\n",@"0;;EOF",@"",[@"0;;before" stringByAppendingString:zero]]){@autoreleasepool{
            reset();response(wire);NSString *expected=[LegacySocketClient sendLineAndRead:line timeout:2.0];const std::string command=fixture.sent;
            reset();response(wire);NSString *actual=[TLinkSocketClient sendLineAndRead:line timeout:2.0];
            assert([expected isEqual:actual]&&fixture.sent==command&&opens==closes);
        }}
        reset();[LegacySocketClient sendLineFireAndForget:line];const std::string expected=fixture.sent;
        reset();fixture.chunk=1;fixture.block=true;[TLinkSocketClient sendLineFireAndForget:line];
        assert(fixture.sent==expected&&fixture.offset==0&&opens==closes);
    }
    for(NSArray<NSString *> *args in @[@[],@[@"reload"],@[@"Ứng dụng",@";;overlap"],@[zero]]){
        reset();NSString *expected=[LegacySocketClient requestTask:76 args:args timeout:2.0];const std::string command=fixture.sent;
        reset();NSString *actual=[TLinkSocketClient requestTask:76 args:args timeout:2.0];
        assert([expected isEqual:actual]&&fixture.sent==command&&opens==closes);
    }
    reset();socketFailure=true;NSString *expected=[LegacySocketClient sendLineAndRead:@"97" timeout:2.0];
    reset();socketFailure=true;assert([expected isEqual:[TLinkSocketClient sendLineAndRead:@"97" timeout:2.0]]);
    reset();fixture.connectError=ECONNREFUSED;expected=[LegacySocketClient sendLineAndRead:@"97" timeout:2.0];
    reset();fixture.connectError=ECONNREFUSED;assert([expected isEqual:[TLinkSocketClient sendLineAndRead:@"97" timeout:2.0]]);
}
static void failureCases(){
    reset();prepareFailure=true;assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] hasPrefix:@"socket() failed"]);
    reset();fixture.sendError=EPIPE;assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] hasPrefix:@"send failed"]);
    reset();fixture.readError=EIO;assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] hasPrefix:@"no response / timeout"]);
    reset();fixture.chunk=1;fixture.readCost=400;assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] hasPrefix:@"no response / timeout"]&&fixture.tick==2100);
    reset();fixture.response=std::string(TLinkAppTaskIO::MaxResponse,'x');assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] hasPrefix:@"no response / timeout"]);
    reset();fixture.response=std::string(TLinkAppTaskIO::MaxResponse-1,'x')+"\n";assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] length]==TLinkAppTaskIO::MaxResponse);
    reset();fixture.response=std::string(1,char(0xff))+"\n";assert([[TLinkSocketClient sendLineAndRead:@"97" timeout:2] isEqualToString:@"non-utf8 response"]);
    reset();const unsigned before=opens;assert([TLinkAppTaskRequest(@"97",std::numeric_limits<double>::quiet_NaN(),YES) isEqualToString:@"invalid timeout"]&&opens==before);
    reset();assert([TLinkAppTaskRequest(nil,2,YES) isEqualToString:@"invalid command"]&&opens==closes);
    for(unsigned kind=1;kind<=2;++kind){
        reset();readFault=kind;bool caught=false;
        @try{try{(void)[TLinkSocketClient sendLineAndRead:@"97" timeout:2];}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){(void)exception;caught=kind==1;}
        assert(caught&&opens==closes);
    }
}
static void posixCases(){
    for(unsigned mode=0;mode<3;++mode){
        int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
        TLinkHelperIO::Socket client(pair[0]),peer(pair[1]);assert(client.prepare().ok()&&peer.prepare().ok());
        if(!mode){const char reply[]="0;;real\r\n";assert(::send(peer.fd(),reply,sizeof(reply)-1,0)==ssize_t(sizeof(reply)-1));}
        const auto base=TLinkHelperIO::posixOps();const auto budget=TLinkAppTaskIO::window(TLinkHelperIO::nowMs(),mode==2?0.02:2);
        TLinkVPNBrokerClientIO::BoundedOps bounded(base,budget);
        TLinkVPNBrokerClientIO::ConnectOps connected{nullptr,[](void *,int,int &){return 0;},[](void *,int,int &){return 0;}};
        const uint8_t command[]="76reload\n";
        const auto result=TLinkAppTaskIO::request(bounded.ops(),connected,client.fd(),command,sizeof(command)-1,mode!=1,budget);
        if(mode==2)assert(result.stage==TLinkAppTaskIO::Stage::Read&&result.result.code==TLinkHelperIO::Code::Timeout);
        else assert(result.stage==TLinkAppTaskIO::Stage::None);
        char bytes[32];const ssize_t count=::recv(peer.fd(),bytes,sizeof(bytes),0);assert(count==9&&std::string(bytes,size_t(count))=="76reload\n");
    }
}
int main(){@autoreleasepool{
    parityCases();failureCases();posixCases();reset();
    puts("App socket Foundation passed: complete current/frozen class API/task codec/wire/UTF8/NUL/error parity, exact fire-and-forget, trickle/cap/fault refusal, scoped flags/NS-C++ unwind and real socketpair reply/no-reply/deadline. No installed daemon contacted; device qualification pending.");
}return 0;}
