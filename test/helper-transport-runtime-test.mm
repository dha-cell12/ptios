#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#import "../pccontrol/jsruntime/TLinkJSHelperClient.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include "../shared/TLinkHelperRPCIdentity.h"
#include "../shared/TLinkHelperSocketIO.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
using namespace TLinkHelperIO;
static NSString *kTLinkJSHelperSocketPath;
#include "HelperTransportClientUnderTest.inc"
@interface FixturePeer : NSObject {
@public std::atomic<unsigned> mode,effects;
}
@property(nonatomic, copy) NSString *helperInstanceId;
- (void)handleClient:(int)client;
- (NSDictionary *)handleEnvelope:(NSDictionary *)request;
- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message;
@end
@implementation FixturePeer
- (instancetype)init {self=[super init];if(self){mode.store(0);effects.store(0);self.helperInstanceId=@"helper";}return self;}
- (NSDictionary *)handleEnvelope:(NSDictionary *)request {
    ++effects;const unsigned action=mode.load();
    if(action==4)[NSException raise:@"FixtureHandler" format:@"handler exception"];
    NSString *command=request[@"command"],*session=[command isEqual:@"start"]?@"session":request[@"sessionId"];
    NSDictionary *payload=@{@"state":@"running",@"activeSessionId":@"session"};
    if(action==3)payload=@{@"huge":[@"" stringByPaddingToLength:MaxFrameBytes withString:@"x" startingAtIndex:0]};
    return [TLinkJSHelperProtocol envelopeWithCommand:command helperInstanceId:action==1?@"replacement":self.helperInstanceId
                                           sessionId:session requestId:action==2?@"wrong":request[@"requestId"] payload:payload];
}
#include "HelperTransportServerUnderTest.inc"
@end
class Listener {
    std::string directory_,path_;Socket socket_;
public:
    Listener():socket_(::socket(AF_UNIX,SOCK_STREAM,0)){
        char directory[]="/tmp/tlp-XXXXXX";assert(::mkdtemp(directory));directory_=directory;path_=directory_+"/s";
        sockaddr_un address{};address.sun_family=AF_UNIX;assert(path_.size()<sizeof(address.sun_path));std::copy(path_.begin(),path_.end(),address.sun_path);
        assert(socket_.fd()>=0&&::bind(socket_.fd(),reinterpret_cast<sockaddr *>(&address),sizeof(address))==0&&::listen(socket_.fd(),8)==0);
        kTLinkJSHelperSocketPath=[NSString stringWithUTF8String:path_.c_str()];
    }
    ~Listener(){socket_.close();assert(::unlink(path_.c_str())==0);assert(::rmdir(directory_.c_str())==0);}
    int accept(){const int fd=::accept(socket_.fd(),nullptr,nullptr);assert(fd>=0);return fd;}
};
static NSData *wireRequest(){return [TLinkJSHelperProtocol serializeEnvelope:[TLinkJSHelperProtocol envelopeWithCommand:@"status" helperInstanceId:nil sessionId:@"session" requestId:@"transport" payload:@{}] error:nil];}
static void clientCases(){
    Listener listener;FixturePeer *peer=[[FixturePeer alloc] init];
    std::thread service([&]{@autoreleasepool{for(unsigned n=0;n<54;++n)[peer handleClient:listener.accept()];}});
    TLinkJSHelperClient *client=[[TLinkJSHelperClient alloc] init];
    NSDictionary *reply=[client startScriptAtPath:@"/script.js" bundlePath:@"/bundle" manifest:@{} timeoutMs:1000];assert([reply[@"ok"] boolValue]);
    for(unsigned n=0;n<50;++n){reply=[client statusForSessionId:@"session" timeoutMs:1000];assert([reply[@"ok"] boolValue]);}
    peer->mode.store(1);reply=[client statusForSessionId:@"session" timeoutMs:1000];assert([reply[@"error"] isEqual:@"helper_instance_mismatch"]);
    peer->mode.store(2);reply=[client statusForSessionId:@"session" timeoutMs:1000];assert([reply[@"error"] isEqual:@"response_request_mismatch"]);
    peer->mode.store(3);reply=[client statusForSessionId:@"session" timeoutMs:1000];assert([reply[@"error"][@"message"] isEqual:@"frame_too_large"]);
    service.join();assert(peer->effects==54);
    reply=[client statusWithTimeoutMs:0];assert([reply[@"error"] isEqual:@"invalid_timeout"]);
    NSString *large=[@"" stringByPaddingToLength:MaxFrameBytes withString:@"x" startingAtIndex:0];
    reply=[client startScriptAtPath:large bundlePath:@"/bundle" manifest:@{} timeoutMs:1000];assert([reply[@"error"] isEqual:@"frame_too_large"]);assert(peer->effects==54);
}
static void clientTimeout(){
    Listener listener;std::thread silent([&]{
        Socket peer(listener.accept());assert(peer.prepare().ok());std::vector<uint8_t> frame;
        assert(readFrame(posixOps(),peer.fd(),frame,Deadline(nowMs(),1000)).ok());
        // No response: client deadline closes its endpoint and wakes this reader.
        assert(readFrame(posixOps(),peer.fd(),frame,Deadline(nowMs(),2000)).code==Code::Empty);
    });
    TLinkJSHelperClient *client=[[TLinkJSHelperClient alloc] init];NSDictionary *reply=[client statusWithTimeoutMs:200];
    assert([reply[@"error"] isEqual:@"io_timeout"]);silent.join();
}
static void serverCases(){
    for(unsigned action=0;action<4;++action){@autoreleasepool {
        int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        FixturePeer *peer=[[FixturePeer alloc] init];if(action==3)peer->mode.store(4);
        std::atomic<bool> caught{false},closed{false};const int accepted=pair[1];
        std::thread service([&]{@autoreleasepool{
            @try{[peer handleClient:accepted];}@catch(NSException *error){(void)error;caught.store(true);}
            closed.store(::fcntl(accepted,F_GETFD,0)<0&&errno==EBADF);
        }});
        NSData *json=wireRequest();const Deadline deadline(nowMs(),2500);
        if(action==0){
            // Valid JSON without LF or EOF must not execute merely because its I/O time expires.
            assert(writeBytes(posixOps(),sender.fd(),static_cast<const uint8_t *>(json.bytes),json.length,deadline).ok());
            service.join();assert(peer->effects==0&&closed.load());
        }else{
            const uint8_t incomplete='{';const uint8_t *bytes=action==2?&incomplete:static_cast<const uint8_t *>(json.bytes);
            const size_t length=action==2?1:json.length;
            assert(writeBytes(posixOps(),sender.fd(),bytes,length,deadline).ok());assert(::shutdown(sender.fd(),SHUT_WR)==0);
            service.join();assert(closed.load());
            if(action==3){assert(caught.load()&&peer->effects==1);}
            else{
                std::vector<uint8_t> frame;assert(readFrame(posixOps(),sender.fd(),frame,deadline).ok());
                NSDictionary *reply=[TLinkJSHelperProtocol deserializeEnvelope:[NSData dataWithBytes:frame.data() length:frame.size()] error:nil];assert(reply);
                if(action==1){assert(peer->effects==1&&![reply[@"command"] isEqual:@"error"]);}
                else{assert(peer->effects==0&&[reply[@"command"] isEqual:@"error"]);}
            }
        }
    }}
}
int main(){@autoreleasepool{clientCases();clientTimeout();serverCases();puts("Helper transport Foundation passed: actual client/server over AF_UNIX, 54 correlated exchanges, restart/request mismatches, oversize errors, silent-peer deadline, no dispatch of timed-out prefixes, EOF compatibility and exception/descriptor cleanup.");}return 0;}
