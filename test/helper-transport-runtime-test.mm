#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#import "../pccontrol/jsruntime/TLinkJSHelperClient.h"
#import "../pccontrol/jsruntime/TLinkJSHelperProtocol.h"
#include "../shared/TLinkHelperRPCIdentity.h"
#include "../shared/TLinkHelperSocketIO.h"
#include "../shared/TLinkHelperRequestDeadline.h"
#include "../shared/TLinkHelperClientAdmission.h"
#include "../shared/TLinkHelperChangeWait.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <stdexcept>
using namespace TLinkHelperIO;
static NSString *kTLinkJSHelperSocketPath;
#include "HelperTransportClientUnderTest.inc"
@interface FixturePeer : NSObject {
@public std::atomic<unsigned> mode,effects;
    TLinkHelperClientAdmission _clientAdmission;
    std::timed_mutex _clientCommandOwner;
    TLinkHelperChangeWait _statusChanges;
}
@property(nonatomic, copy) NSString *helperInstanceId;
@property(nonatomic, copy) NSString *activeSessionId;
@property(nonatomic, strong) dispatch_queue_t clientQueue;
- (void)publishStatusChange;
- (NSDictionary *)waitForChangeRequest:(NSDictionary *)request deadline:(const TLinkHelperIO::Deadline &)deadline;
- (void)handleClient:(int)client;
- (void)handleClient:(int)client acceptedAt:(uint64_t)acceptedAt;
- (void)enqueueClient:(int)client acceptedAt:(uint64_t)acceptedAt;
- (NSDictionary *)handleEnvelope:(NSDictionary *)request;
- (NSDictionary *)errorEnvelopeForRequest:(NSDictionary *)request message:(NSString *)message;
@end
@implementation FixturePeer
- (instancetype)init {self=[super init];if(self){mode.store(0);effects.store(0);self.helperInstanceId=@"helper";self.activeSessionId=@"session";self.clientQueue=dispatch_queue_create("fixture.helper.clients",DISPATCH_QUEUE_CONCURRENT);}return self;}
- (NSDictionary *)handleEnvelope:(NSDictionary *)request {
    if(![request[@"requestId"] isEqual:@"transport"]){
        bool present=false;uint64_t issued=0,expires=0;
        assert(TLinkHelperReadSenderDeadline(request,present,issued,expires)&&present);
        assert(issued<=nowMs()&&nowMs()<expires);
    }
    ++effects;const unsigned action=mode.load();
    if(action==4)[NSException raise:@"FixtureHandler" format:@"handler exception"];
    if(action==6)throw std::runtime_error("fixture handler exception");
    NSString *command=request[@"command"],*session=[command isEqual:@"start"]?@"session":request[@"sessionId"];
    NSDictionary *payload=@{@"state":@"running",@"activeSessionId":@"session"};
    if(action==3)payload=@{@"huge":[@"" stringByPaddingToLength:MaxFrameBytes withString:@"x" startingAtIndex:0]};
    return [TLinkJSHelperProtocol envelopeWithCommand:command helperInstanceId:action==1?@"replacement":self.helperInstanceId
                                           sessionId:session requestId:action==2?@"wrong":request[@"requestId"] payload:payload];
}
#include "HelperClientAdmissionUnderTest.inc"
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
static void drainClients(FixturePeer *peer){dispatch_barrier_sync(peer.clientQueue, ^{});assert(peer->_clientAdmission.stats().active==0);}
static NSData *deadlineRequest(id window){
    NSMutableDictionary *request=[[TLinkJSHelperProtocol deserializeEnvelope:wireRequest() error:nil] mutableCopy];
    request[@"requestDeadline"]=window;
    // Bypass the serializer's validation to exercise receiver rejection of malformed wire input.
    return [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
}
static void senderDeadlineCases(){
    const uint64_t now=nowMs();assert(now>1000);
    NSArray *malformed=@[
        [NSNull null],@[],@{},
        @{@"clock":@"other",@"issuedMs":@(now),@"expiresMs":@(now+100)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(true),@"expiresMs":@(100)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@"1",@"expiresMs":@(100)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(-1),@"expiresMs":@(100)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(0.5),@"expiresMs":@(100)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(now),@"expiresMs":@(now)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(now),@"expiresMs":@(now+30001)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(UINT64_MAX-1),@"expiresMs":@(UINT64_MAX)},
        @{@"clock":@"mach_continuous_ms_v1",@"issuedMs":@(now),@"expiresMs":@(now+100),@"extra":@(1)}
    ];
    for(id window in malformed){
        NSData *data=deadlineRequest(window);
        NSDictionary *raw=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        assert(![TLinkJSHelperProtocol validateEnvelope:raw error:nil]);
        assert(![TLinkJSHelperProtocol deserializeEnvelope:data error:nil]);
        assert(![TLinkJSHelperProtocol serializeEnvelope:raw error:nil]);
        int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        FixturePeer *peer=[[FixturePeer alloc] init];[peer enqueueClient:pair[1] acceptedAt:nowMs()];
        const Deadline io(nowMs(),2000);assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(data.bytes),data.length,io).ok());
        std::vector<uint8_t> frame;assert(readFrame(posixOps(),sender.fd(),frame,io).ok());
        drainClients(peer);assert(peer->effects==0);
    }
    // Even a newly accepted socket must reject an already-expired or future sender window.
    for(bool future : {false,true}){
        const uint64_t sampled=nowMs();const Deadline wire(future?sampled+60000:sampled-1000,100);
        NSData *data=deadlineRequest(TLinkHelperSenderDeadline(future?sampled+60000:sampled-1000,wire));
        FixturePeer *peer=[[FixturePeer alloc] init];dispatch_suspend(peer.clientQueue);
        int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        [peer enqueueClient:pair[1] acceptedAt:nowMs()];const Deadline io(nowMs(),2000);
        assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(data.bytes),data.length,io).ok());
        dispatch_resume(peer.clientQueue);std::vector<uint8_t> frame;
        assert(readFrame(posixOps(),sender.fd(),frame,io).code==Code::Empty);drainClients(peer);assert(peer->effects==0);
    }
    // Real client times out while its complete command is still in the listen backlog.
    // Accept only after the client returns: a fresh server window must not revive the command.
    {
        Listener listener;TLinkJSHelperClient *client=[[TLinkJSHelperClient alloc] init];
        NSDictionary *reply=[client statusWithTimeoutMs:100];assert([reply[@"error"] isEqual:@"io_timeout"]);
        FixturePeer *peer=[[FixturePeer alloc] init];[peer handleClient:listener.accept()];assert(peer->effects==0);
    }
    // The client has a shorter budget than accept: command-owner wait must use that shorter budget.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];peer->_clientCommandOwner.lock();
        int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        const uint64_t issued=nowMs();const Deadline wire(issued,100);NSData *data=deadlineRequest(TLinkHelperSenderDeadline(issued,wire));
        [peer enqueueClient:pair[1] acceptedAt:issued];const Deadline io(nowMs(),2000);
        assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(data.bytes),data.length,io).ok());
        std::vector<uint8_t> frame;assert(readFrame(posixOps(),sender.fd(),frame,io).code==Code::Empty);
        assert(nowMs()>=wire.end&&peer->effects==0);peer->_clientCommandOwner.unlock();drainClients(peer);assert(peer->effects==0);
    }
    puts("Helper sender deadline Foundation passed: actual client metadata, strict codec/wire rejection, fresh-accept/queued expiry, future-clock rejection, shorter command-owner budget and no late effects; legacy EOF remains covered.");
}
static void waitForReaders(FixturePeer *peer,size_t count){
    const Deadline watchdog(nowMs(),5000);
    while(peer->_statusChanges.waiters()!=count){assert(watchdog.remaining(nowMs()));std::this_thread::yield();}
}
static NSData *changeRequest(uint64_t sequence,int waitMs,NSString *helper,NSString *session,bool withDeadline=true){
    NSMutableDictionary *request=[[TLinkJSHelperProtocol envelopeWithCommand:kTLinkJSHelperCmdWaitForChange helperInstanceId:helper sessionId:session requestId:@"transport"
        payload:@{@"afterSequence":@(sequence),@"waitMs":@(waitMs)}] mutableCopy];
    const uint64_t issued=nowMs();if(withDeadline)request[@"requestDeadline"]=TLinkHelperSenderDeadline(issued,Deadline(issued,1000));
    return [TLinkJSHelperProtocol serializeEnvelope:request error:nil];
}
static int beginRequest(FixturePeer *peer,NSData *json){
    int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
    [peer enqueueClient:pair[1] acceptedAt:nowMs()];
    assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(json.bytes),json.length,Deadline(nowMs(),2000)).ok());
    return sender.release();
}
static NSDictionary *readReply(Socket &sender){
    std::vector<uint8_t> frame;assert(readFrame(posixOps(),sender.fd(),frame,Deadline(nowMs(),2000)).ok());
    NSDictionary *reply=[TLinkJSHelperProtocol deserializeEnvelope:[NSData dataWithBytes:frame.data() length:frame.size()] error:nil];assert(reply);return reply;
}
static void changeWaitCases(){
    // Four sleeping waiters do not own the command lock; the fifth fails without blocking status.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];const uint64_t sequence=peer->_statusChanges.sequence();std::vector<int> waiters;
        for(unsigned n=0;n<4;++n)waiters.push_back(beginRequest(peer,changeRequest(sequence,750,@"helper",@"session")));
        waitForReaders(peer,4);
        Socket busy(beginRequest(peer,changeRequest(sequence,750,@"helper",@"session")));
        NSDictionary *reply=readReply(busy);assert([reply[@"error"][@"message"] isEqual:@"change_wait_busy"]);
        Socket status(beginRequest(peer,wireRequest()));reply=readReply(status);assert([reply[@"command"] isEqual:@"status"]&&peer->effects==1);
        [peer publishStatusChange];
        for(int fd:waiters){Socket sender(fd);reply=readReply(sender);assert([reply[@"payload"][@"changed"] boolValue]);assert([reply[@"payload"][@"sequence"] unsignedLongLongValue]==sequence+1);}
        drainClients(peer);assert(peer->_statusChanges.waiters()==0&&peer->_clientAdmission.stats().peak<=8);
    }
    // A publication before waiter registration is immediately visible, and quiet timeout retains the cursor.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];[peer publishStatusChange];
        Socket old(beginRequest(peer,changeRequest(1,750,@"helper",@"session")));NSDictionary *reply=readReply(old);assert([reply[@"payload"][@"changed"] boolValue]);
        Socket quiet(beginRequest(peer,changeRequest(2,10,@"helper",@"session")));reply=readReply(quiet);assert(![reply[@"payload"][@"changed"] boolValue]&&[reply[@"payload"][@"reason"] isEqual:@"timeout"]);
        drainClients(peer);assert(peer->effects==0&&peer->_statusChanges.waiters()==0);
    }
    // Helper/session identity, cursor, strict payload and deadline presence reject before waiting/effects.
    for(unsigned action=0;action<6;++action){
        FixturePeer *peer=[[FixturePeer alloc] init];NSString *expected=action==0?@"helper_instance_mismatch":action==1?@"session_mismatch":action==2?@"change_cursor_ahead":@"invalid_wait_request";
        NSData *json=changeRequest(action==2?100:1,action==3?751:action==4?0:750,action==0?@"old-helper":@"helper",action==1?@"old-session":@"session",action!=5);
        Socket sender(beginRequest(peer,json));NSDictionary *reply=readReply(sender);assert([reply[@"error"][@"message"] isEqual:expected]);drainClients(peer);assert(peer->effects==0&&peer->_statusChanges.waiters()==0);
    }
    for(id payload in @[@{},@[],[NSNull null],@{@"afterSequence":@(true),@"waitMs":@10},@{@"afterSequence":@1,@"waitMs":@(0.5)},@{@"afterSequence":@1,@"waitMs":@10,@"extra":@1}]){
        FixturePeer *peer=[[FixturePeer alloc] init];
        NSMutableDictionary *request=[[TLinkJSHelperProtocol deserializeEnvelope:changeRequest(1,10,@"helper",@"session") error:nil] mutableCopy];request[@"payload"]=payload;
        Socket sender(beginRequest(peer,[TLinkJSHelperProtocol serializeEnvelope:request error:nil]));NSDictionary *reply=readReply(sender);
        assert([reply[@"error"][@"message"] isEqual:@"invalid_wait_request"]);drainClients(peer);assert(peer->effects==0&&peer->_statusChanges.waiters()==0);
    }
    // Shutdown wakes admitted waiters and returns all client ownership.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];Socket sender(beginRequest(peer,changeRequest(1,750,@"helper",@"session")));waitForReaders(peer,1);
        peer->_statusChanges.stop();NSDictionary *reply=readReply(sender);assert([reply[@"error"][@"message"] isEqual:@"change_wait_stopped"]);drainClients(peer);
    }
    // The public client requires a start-bound helper and correlates its actual wait reply.
    {
        TLinkJSHelperClient *unbound=[[TLinkJSHelperClient alloc] init];NSDictionary *reply=[unbound waitForChangeAfterSequence:1 sessionId:@"session" waitMs:750 timeoutMs:1000];assert([reply[@"error"] isEqual:@"helper_not_bound"]);
        Listener listener;FixturePeer *peer=[[FixturePeer alloc] init];
        std::thread service([&]{@autoreleasepool{
            [peer handleClient:listener.accept()];[peer enqueueClient:listener.accept() acceptedAt:nowMs()];waitForReaders(peer,1);[peer publishStatusChange];drainClients(peer);
        }});
        TLinkJSHelperClient *client=[[TLinkJSHelperClient alloc] init];reply=[client startScriptAtPath:@"/script.js" bundlePath:@"/bundle" manifest:@{} timeoutMs:1000];assert([reply[@"ok"] boolValue]);
        reply=[client waitForChangeAfterSequence:1 sessionId:@"session" waitMs:750 timeoutMs:1000];assert([reply[@"ok"] boolValue]&&[reply[@"response"][@"payload"][@"changed"] boolValue]);service.join();
    }
    puts("Helper change wait Foundation passed: actual public client/codec/socket handler, four waiters and immediate fifth rejection, independent status, registration gap, timeout, helper/session/cursor/deadline gates and stop cleanup.");
}
static void queueCases(){
    // A stalled reader must not delay a different complete request.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];int idle[2],ready[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,idle)==0&&::socketpair(AF_UNIX,SOCK_STREAM,0,ready)==0);
        Socket idleSender(idle[0]),readySender(ready[0]);assert(readySender.prepare().ok());
        [peer enqueueClient:idle[1] acceptedAt:nowMs()];[peer enqueueClient:ready[1] acceptedAt:nowMs()];
        NSData *json=wireRequest();const Deadline deadline(nowMs(),1000);
        assert(writeFrame(posixOps(),readySender.fd(),static_cast<const uint8_t *>(json.bytes),json.length,deadline).ok());
        std::vector<uint8_t> frame;assert(readFrame(posixOps(),readySender.fd(),frame,deadline).ok());assert(peer->effects==1);
        idleSender.close();drainClients(peer);assert(peer->_clientAdmission.stats().finished==2);
    }
    // Include queued callbacks in the eight-client budget; the ninth fd closes immediately.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];dispatch_suspend(peer.clientQueue);std::vector<int> senders;
        const uint64_t now=nowMs(),expired=now>2000?now-2000:0;
        for(unsigned n=0;n<8;++n){int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);senders.push_back(pair[0]);[peer enqueueClient:pair[1] acceptedAt:expired];}
        assert(peer->_clientAdmission.stats().active==8);int rejected[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,rejected)==0);
        [peer enqueueClient:rejected[1] acceptedAt:nowMs()];assert(::fcntl(rejected[1],F_GETFD,0)<0&&errno==EBADF);::close(rejected[0]);
        dispatch_resume(peer.clientQueue);drainClients(peer);const auto stats=peer->_clientAdmission.stats();assert(stats.peak==8&&stats.rejected==1&&peer->effects==0);
        for(int fd:senders)::close(fd);
    }
    // A command waiting for another handler retains its original deadline and cannot run late.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        peer->_clientCommandOwner.lock();[peer enqueueClient:pair[1] acceptedAt:nowMs()];NSData *json=wireRequest();const Deadline deadline(nowMs(),2000);
        assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(json.bytes),json.length,deadline).ok());std::vector<uint8_t> frame;
        assert(readFrame(posixOps(),sender.fd(),frame,deadline).code==Code::Empty);assert(peer->effects==0);
        peer->_clientCommandOwner.unlock();drainClients(peer);assert(peer->effects==0);
    }
    // Stop rejects queued/new work, and exceptions still return the lease.
    {
        FixturePeer *peer=[[FixturePeer alloc] init];int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);
        dispatch_suspend(peer.clientQueue);[peer enqueueClient:pair[1] acceptedAt:nowMs()];peer->_clientAdmission.stop();dispatch_resume(peer.clientQueue);drainClients(peer);assert(peer->effects==0);
        int rejected[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,rejected)==0);[peer enqueueClient:rejected[1] acceptedAt:nowMs()];assert(::fcntl(rejected[1],F_GETFD,0)<0&&errno==EBADF);::close(rejected[0]);
    }
    for(unsigned kind : {4U,6U}) {
        FixturePeer *peer=[[FixturePeer alloc] init];peer->mode.store(kind);int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]);assert(sender.prepare().ok());
        [peer enqueueClient:pair[1] acceptedAt:nowMs()];NSData *json=wireRequest();const Deadline deadline(nowMs(),2000);
        assert(writeFrame(posixOps(),sender.fd(),static_cast<const uint8_t *>(json.bytes),json.length,deadline).ok());std::vector<uint8_t> frame;
        assert(readFrame(posixOps(),sender.fd(),frame,deadline).code==Code::Empty);drainClients(peer);assert(peer->effects==1&&peer->_clientAdmission.stats().finished==1);
    }
    puts("Helper admission Foundation passed: actual concurrent enqueue/leases, stalled-reader isolation, eight queued clients/ninth-fd rejection, accepted-time expiry, serialized command deadline, stopped and exception cleanup.");
}
int main(){@autoreleasepool{clientCases();clientTimeout();serverCases();senderDeadlineCases();changeWaitCases();queueCases();puts("Helper transport Foundation passed: actual client/server over AF_UNIX, 54 correlated exchanges, restart/request mismatches, oversize errors, silent-peer deadline, no dispatch of timed-out prefixes, EOF compatibility and exception/descriptor cleanup.");}return 0;}
