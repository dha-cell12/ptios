#import <Foundation/Foundation.h>
#include "license-reload-fixture.h"
#include <cstdio>
#include <stdexcept>
#include <fcntl.h>
static ReloadFixture fixture;
static unsigned opens=0,closes=0;
static bool socketFailure=false,prepareFailure=false;
static unsigned readFault=0;
static int fixtureSocket(int domain,int type,int protocol){if(socketFailure)return -1;const int fd=::socket(domain,type,protocol);assert(fd>=0);++opens;return fd;}
class FixtureSocket {
    int fd_;
public:
    explicit FixtureSocket(int fd):fd_(fd){}
    ~FixtureSocket(){close();}
    int fd()const{return fd_;}
    void close(){if(fd_>=0){assert(::close(fd_)==0);fd_=-1;++closes;}}
    TLinkHelperIO::Result prepare(){
        if(prepareFailure)return {TLinkHelperIO::Code::Setup,EIO};
        TLinkHelperIO::Socket actual(fd_);const auto result=actual.prepare();actual.release();
        assert((::fcntl(fd_,F_GETFL,0)&O_NONBLOCK)&&(::fcntl(fd_,F_GETFD,0)&FD_CLOEXEC));return result;
    }
};
static TLinkHelperIO::Ops fixtureOps(){
    auto ops=fixture.ops();ops.receive=[](void *p,int fd,uint8_t *bytes,size_t size,int &error)->ptrdiff_t{
        if(readFault==1)[NSException raise:@"ReloadFixture" format:@"read"];
        if(readFault==2)throw std::runtime_error("read");
        return static_cast<ReloadFixture *>(p)->ops().receive(p,fd,bytes,size,error);
    };return ops;
}
#include "LicenseReloadUnderTest.inc"
static void reset(){assert(opens==closes);fixture=ReloadFixture{};socketFailure=prepareFailure=false;readFault=0;}
int main(){@autoreleasepool{
    for(NSString *wire in @[@"0;;ok\r\n",@"-1;;denied\r\n",@" 0;;Ứng dụng 测试 😀\r\n",@"0;;EOF"]){
        for(unsigned chunk=1;chunk<=16;++chunk){reset();NSData *data=[wire dataUsingEncoding:NSUTF8StringEncoding];fixture.response.assign((const char *)data.bytes,data.length);fixture.chunk=chunk;
            NSString *expected=[wire stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            assert([SCLicenseRootfullReloadRequest() isEqual:expected]&&opens==closes&&fixture.sent=="76reload\r\n");}
    }
    reset();socketFailure=true;assert([SCLicenseRootfullReloadRequest() isEqualToString:@"socket_create_failed"]&&opens==closes);
    reset();prepareFailure=true;assert([SCLicenseRootfullReloadRequest() isEqualToString:@"socket_create_failed"]&&opens==closes);
    reset();fixture.connectCost=2000;assert([SCLicenseRootfullReloadRequest() isEqualToString:@"streamd_connect_failed"]&&opens==closes);
    reset();fixture.sendError=EPIPE;assert([SCLicenseRootfullReloadRequest() isEqualToString:@"streamd_send_failed"]&&opens==closes);
    reset();fixture.chunk=1;fixture.readCost=400;assert([SCLicenseRootfullReloadRequest() isEqualToString:@"streamd_no_response"]&&opens==closes);
    reset();fixture.response=std::string(8191,'x');assert([SCLicenseRootfullReloadRequest() isEqualToString:@"streamd_no_response"]&&opens==closes);
    reset();fixture.response=std::string(1,char(0xff))+"\n";assert([SCLicenseRootfullReloadRequest() isEqualToString:@"streamd_invalid_response"]&&opens==closes);
    reset();fixture.response=std::string("0;;before\0after\n",16);assert([SCLicenseRootfullReloadRequest() isEqualToString:@"0;;before"]&&opens==closes);
    for(unsigned kind=1;kind<=2;++kind){reset();readFault=kind;bool caught=false;
        @try{try{(void)SCLicenseRootfullReloadRequest();}catch(const std::runtime_error &){caught=kind==2;}}
        @catch(NSException *exception){(void)exception;caught=kind==1;}
        assert(caught&&opens==closes);
    }
    // Exercise the same transaction core with real nonblocking POSIX endpoints.
    int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
    TLinkHelperIO::Socket client(pair[0]),peer(pair[1]);assert(client.prepare().ok()&&peer.prepare().ok());
    const char response[]="0;;real\r\n";assert(::send(peer.fd(),response,sizeof(response)-1,0)==ssize_t(sizeof(response)-1));
    const auto base=TLinkHelperIO::posixOps();const auto window=TLinkLicenseReloadIO::window(TLinkHelperIO::nowMs());TLinkVPNBrokerClientIO::BoundedOps bounded(base,window);
    TLinkVPNBrokerClientIO::ConnectOps connected{nullptr,[](void *,int,int &){return 0;},[](void *,int,int &){return 0;}};
    auto reply=TLinkLicenseReloadIO::request(bounded.ops(),connected,client.fd(),window);assert(reply.failure==TLinkLicenseReloadIO::Failure::None);
    char command[32];const ssize_t count=::recv(peer.fd(),command,sizeof(command),0);assert(count==10&&std::string(command,size_t(count))=="76reload\r\n");
    reset();puts("License reload Foundation passed: actual adapter/decoder, UTF8/NUL/error replies, phase expiry/caps, real descriptor flags/NS-C++ unwind and nonblocking POSIX framing. Root daemon/device qualification pending.");
}}
