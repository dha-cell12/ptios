#import <Foundation/Foundation.h>
#include "license-reload-fixture.h"
#include "../shared/TLinkSupervisorTaskIO.h"
#include <cstdio>
#include <stdexcept>
#include <fcntl.h>
#include <sys/time.h>
static ReloadFixture fixture;
static unsigned opens=0,closes=0,readFault=0;
static bool socketFailure=false,prepareFailure=false;
static int fixtureSocket(int domain,int type,int protocol){
    if(socketFailure)return -1;
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
    auto ops=fixture.ops();ops.receive=[](void *p,int fd,uint8_t *bytes,size_t size,int &error)->ptrdiff_t{
        if(readFault==1)[NSException raise:@"SupervisorTaskFixture" format:@"read"];
        if(readFault==2)throw std::runtime_error("read");
        return static_cast<ReloadFixture *>(p)->ops().receive(p,fd,bytes,size,error);
    };return ops;
}
@interface TaskHarness:NSObject
- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)seconds;
@end
@implementation TaskHarness
#include "SupervisorTaskUnderTest.inc"
@end
// The complete frozen method gets ordinary POSIX provider substitutions only.
static int legacyOptions(int fd,int level,int option,const void *value,socklen_t size){
    (void)fd;assert(level==SOL_SOCKET&&(option==SO_RCVTIMEO||option==SO_SNDTIMEO));
    assert(size==sizeof(timeval)&&static_cast<const timeval *>(value)->tv_sec>0);return 0;
}
static int legacyConnect(int fd,const sockaddr *address,socklen_t size){
    (void)fd;assert(size==sizeof(sockaddr_in));const auto *endpoint=reinterpret_cast<const sockaddr_in *>(address);
    assert(endpoint->sin_family==AF_INET&&ntohs(endpoint->sin_port)==6000);
    if(fixture.connectError){errno=fixture.connectError;return -1;}return 0;
}
static ssize_t legacySend(int fd,const void *bytes,size_t size,int flags){
    (void)flags;int error=0;const auto ops=fixture.ops();
    const auto count=ops.send(ops.context,fd,static_cast<const uint8_t *>(bytes),size,error);if(count<0)errno=error;return count;
}
static ssize_t legacyReceive(int fd,void *bytes,size_t size,int flags){
    (void)flags;int error=0;const auto ops=fixture.ops();
    const auto count=ops.receive(ops.context,fd,static_cast<uint8_t *>(bytes),size,error);if(count<0)errno=error;return count;
}
@interface LegacyTaskHarness:TaskHarness
@end
@implementation LegacyTaskHarness
#define socket fixtureSocket
#define close fixtureClose
#define setsockopt legacyOptions
#define connect legacyConnect
#define send legacySend
#define recv legacyReceive
#include "SupervisorTaskLegacy.inc"
#undef recv
#undef send
#undef connect
#undef setsockopt
#undef close
#undef socket
@end
static void reset(){assert(opens==closes);fixture=ReloadFixture{};socketFailure=prepareFailure=false;readFault=0;}
static NSString *call(NSString *line,int seconds=2,bool legacy=false){
    TaskHarness *owner=legacy?[LegacyTaskHarness new]:[TaskHarness new];
    NSString *result=[owner sendLocalTaskLineLocked:line timeout:seconds];assert(opens==closes);return result;
}
static void parityCases(){
    unichar nul=0;NSString *zero=[NSString stringWithCharacters:&nul length:1];
    NSArray *lines=@[@"97",@"60\n",@"96\r\n",@"",@"Ứng dụng 测试 😀",[@"97" stringByAppendingString:zero]];
    for(NSString *line in lines){
        for(NSString *wire in @[@"0;;ok\r\n",@"-1;;denied\r\n",@" 0;;Ứng dụng 测试 😀\r\n",@"0;;EOF",@"",[@"0;;before" stringByAppendingString:zero]]){
            @autoreleasepool{
                NSData *data=[wire dataUsingEncoding:NSUTF8StringEncoding];
                reset();fixture.response.assign(static_cast<const char *>(data.bytes),data.length);
                NSString *expected=call(line,2,true);const std::string command=fixture.sent;
                reset();fixture.response.assign(static_cast<const char *>(data.bytes),data.length);
                NSString *actual=call(line);assert((actual==expected||[actual isEqual:expected])&&fixture.sent==command);
            }
        }
    }
    reset();fixture.response=std::string(1,char(0xff))+"\n";assert(!call(@"97"));
    reset();assert(!call(nil)&&fixture.sent.empty());
}
static void failureCases(){
    reset();socketFailure=true;assert(!call(@"97"));
    reset();prepareFailure=true;assert(!call(@"97"));
    reset();fixture.connectCost=2000;assert(!call(@"97")&&fixture.sent.empty());
    reset();fixture.connectError=ECONNREFUSED;assert(!call(@"97"));
    reset();fixture.sendError=EPIPE;assert(!call(@"97"));
    reset();fixture.readError=EIO;assert(!call(@"97"));
    reset();fixture.chunk=1;fixture.readCost=400;assert(!call(@"97")&&fixture.tick==2100);
    reset();fixture.block=true;assert(!call(@"97",1)&&fixture.tick==1100);
    reset();fixture.response=std::string(65536,'x');assert(!call(@"97"));
    reset();fixture.response=std::string(65535,'x')+"\n";assert([call(@"97") length]==65536);
    for(unsigned kind=1;kind<=2;++kind){
        reset();readFault=kind;bool caught=false;
        @try{try{(void)call(@"97");}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){(void)exception;caught=kind==1;}
        assert(caught&&opens==closes);
    }
}
static void posixCase(){
    int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
    TLinkHelperIO::Socket client(pair[0]),peer(pair[1]);assert(client.prepare().ok()&&peer.prepare().ok());
    const char response[]="0;;real\r\n";assert(::send(peer.fd(),response,sizeof(response)-1,0)==ssize_t(sizeof(response)-1));
    const auto base=TLinkHelperIO::posixOps();const auto budget=TLinkSupervisorTaskIO::window(TLinkHelperIO::nowMs(),2);
    TLinkVPNBrokerClientIO::BoundedOps bounded(base,budget);
    TLinkVPNBrokerClientIO::ConnectOps connected{nullptr,[](void *,int,int &){return 0;},[](void *,int,int &){return 0;}};
    const uint8_t command[]="97\n";
    const auto reply=TLinkSupervisorTaskIO::request(bounded.ops(),connected,client.fd(),command,sizeof(command)-1,budget);assert(reply.ok);
    char bytes[16];const ssize_t count=::recv(peer.fd(),bytes,sizeof(bytes),0);assert(count==3&&std::string(bytes,size_t(count))=="97\n");
}
int main(){@autoreleasepool{
    parityCases();failureCases();posixCase();reset();
    puts("Supervisor task Foundation passed: actual/frozen healthy commands/replies/UTF8/NUL/EOF, descriptor flags, setup/connect/write/read/trickle/cap refusal, NS/C++ unwind and real nonblocking POSIX framing. No installed daemon contacted; device qualification pending.");
}return 0;}
