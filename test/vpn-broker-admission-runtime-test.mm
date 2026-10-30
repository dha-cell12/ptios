#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include "../shared/TLinkHelperClientAdmission.h"
#include "../shared/TLinkHelperSocketIO.h"
#include "../shared/TLinkVPNBrokerIngress.h"
#include <cassert>
#include <atomic>
#include <cstdio>
#include <csignal>
#include <stdexcept>
#include <thread>
#include <vector>

using TLinkHelperIO::Socket;
static const NSUInteger kTLinkVPNBrokerMaxRequest=1024;
static const size_t kTLinkVPNBrokerMaxClients=8;
static std::atomic<unsigned> responses{0},leaseCloses{0};
static int acquireFault=0,enqueueFault=0,responseFault=0;
static int reuseSource=-1,reusedDescriptor=-1;
static dispatch_semaphore_t readsEntered;
static std::atomic<bool> signalReads{false};
static std::atomic<bool> fakeTime{false};
static std::atomic<uint64_t> clockMs{0};
static std::atomic<unsigned> ingressReads{0},ingressWaits{0},advanceReadMs{0};
static std::atomic<size_t> readLimit{SIZE_MAX};
static std::atomic<int> readsBeforeFault{-1};
static bool expireDecode=false;
static uint64_t fixtureNow(){return fakeTime.load()?clockMs.load():TLinkHelperIO::nowMs();}
static void fixtureLog(NSString *format,...){(void)format;}
static NSString *fixtureDecode(NSData *data){
    NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(expireDecode)clockMs+=30000;
    return text;
}
static NSString *fixtureResponse(NSString *command){
    ++responses;
    if(responseFault==1)[NSException raise:@"FixtureResponse" format:@"response"];
    if(responseFault==2)throw std::runtime_error("response");
    NSString *clean=[command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [NSString stringWithFormat:@"0;;%@\r\n",clean];
}
static void fixtureClose(int fd){
    ++leaseCloses;assert(::close(fd)==0);
    if(reuseSource>=0){assert(::dup2(reuseSource,fd)==fd);reusedDescriptor=fd;}
}
static std::shared_ptr<TLinkHelperClientAdmission::Lease> fixtureAcquire(
    TLinkHelperClientAdmission &owner,int fd,uint64_t acceptedAt,void (*closer)(int)){
    if(acquireFault==1)[NSException raise:@"FixtureAcquire" format:@"acquire"];
    if(acquireFault==2)throw std::runtime_error("acquire");
    return owner.acquire(fd,acceptedAt,closer);
}
static void fixtureDispatch(dispatch_queue_t queue,dispatch_block_t block){
    if(enqueueFault==1)[NSException raise:@"FixtureEnqueue" format:@"enqueue"];
    if(enqueueFault==2)throw std::runtime_error("enqueue");
    if(enqueueFault==3)return; // Block discarded without invocation.
    dispatch_async(queue,block);
}
static TLinkHelperIO::Ops fixtureReadOps(){
    auto io=TLinkVPNBrokerIngress::posixReadOps();
    io.now=[](void *){return fixtureNow();};
    io.receive=[](void *,int fd,uint8_t *buffer,size_t capacity,int &error)->ptrdiff_t{
        ++ingressReads;
        if(signalReads.load())dispatch_semaphore_signal(readsEntered);
        if(readsBeforeFault.load()==0){error=EIO;return -1;}
        if(readsBeforeFault.load()>0)--readsBeforeFault;
        const auto real=TLinkVPNBrokerIngress::posixReadOps();
        const ptrdiff_t count=real.receive(real.context,fd,buffer,std::min(capacity,readLimit.load()),error);
        clockMs+=advanceReadMs.load();
        return count;
    };
    io.wait=[](void *,int fd,bool writing,int budget,int &error){
        ++ingressWaits;const auto real=TLinkVPNBrokerIngress::posixReadOps();
        return real.wait(real.context,fd,writing,budget,error);
    };
    return io;
}
namespace Current {
#include "VPNBrokerAdmissionUnderTest.inc"
}
namespace Legacy {
#include "VPNBrokerHandlerLegacy.inc"
}
static void pair(int descriptors[2]){assert(::socketpair(AF_UNIX,SOCK_STREAM,0,descriptors)==0);}
static void sendText(int fd,const void *bytes,size_t length){
    const uint8_t *next=static_cast<const uint8_t *>(bytes);
    while(length){const ssize_t n=::send(fd,next,length,0);assert(n>0);next+=n;length-=static_cast<size_t>(n);}
}
static void sendCommand(int fd,NSString *command){NSData *data=[command dataUsingEncoding:NSUTF8StringEncoding];sendText(fd,data.bytes,data.length);}
static NSData *reply(int fd){
    NSMutableData *result=[NSMutableData data];uint8_t buffer[256];
    for(;;){pollfd item{fd,POLLIN,0};assert(::poll(&item,1,5000)>0);const ssize_t n=::recv(fd,buffer,sizeof(buffer),0);if(n<0&&errno==EINTR)continue;if(n<0){assert(errno==ECONNRESET);break;}if(!n)break;[result appendBytes:buffer length:static_cast<NSUInteger>(n)];}
    return result;
}
static void drain(dispatch_queue_t queue,TLinkHelperClientAdmission &owner){dispatch_barrier_sync(queue,^{});assert(owner.stats().active==0);}
static void closed(int fd){errno=0;assert(::fcntl(fd,F_GETFD)==-1&&errno==EBADF);}
static dispatch_queue_t clientQueue(){return dispatch_queue_create("fixture.vpn.clients",DISPATCH_QUEUE_CONCURRENT);}
static void heldQueueCases(){
    TLinkHelperClientAdmission owner(kTLinkVPNBrokerMaxClients);dispatch_queue_t queue=clientQueue();dispatch_suspend(queue);
    std::vector<int> peers,owned;const unsigned before=responses.load(),beforeCloses=leaseCloses.load();
    for(unsigned n=0;n<8;++n){int fd[2];pair(fd);peers.push_back(fd[0]);owned.push_back(fd[1]);sendCommand(fd[0],@"query\r\n");Current::TLinkVPNBrokerEnqueueClient(owner,queue,fd[1]);}
    assert(owner.stats().active==8&&owner.stats().peak==8&&responses==before);
    int extra[2];pair(extra);Socket rejected(extra[0]);Current::TLinkVPNBrokerEnqueueClient(owner,queue,extra[1]);closed(extra[1]);
    assert(reply(rejected.fd()).length==0&&owner.stats().rejected==1&&responses==before);
    dispatch_resume(queue);
    for(int fd:peers){Socket peer(fd);assert([reply(fd) isEqual:[@"0;;query\r\n" dataUsingEncoding:NSUTF8StringEncoding]]);}
    drain(queue,owner);for(int fd:owned)closed(fd);
    assert(responses==before+8&&leaseCloses==beforeCloses+8&&owner.stats().finished==8);
}
static void blockedReaderCases(){
    TLinkHelperClientAdmission owner(8);dispatch_queue_t queue=clientQueue();std::vector<int> peers;
    const unsigned before=responses.load();readsEntered=dispatch_semaphore_create(0);signalReads=true;
    for(unsigned n=0;n<8;++n){int fd[2];pair(fd);peers.push_back(fd[0]);Current::TLinkVPNBrokerEnqueueClient(owner,queue,fd[1]);}
    for(unsigned n=0;n<8;++n)assert(dispatch_semaphore_wait(readsEntered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(owner.stats().active==8&&responses==before);
    int extra[2];pair(extra);Socket rejected(extra[0]);Current::TLinkVPNBrokerEnqueueClient(owner,queue,extra[1]);closed(extra[1]);assert(reply(rejected.fd()).length==0);
    for(int fd:peers)assert(::close(fd)==0);drain(queue,owner);signalReads=false;
    assert(responses==before&&owner.stats().rejected==1&&owner.stats().finished==8);
}
static void parserParityCases(){
    NSArray<NSData *> *requests=@[
        [@"query\r\n" dataUsingEncoding:NSUTF8StringEncoding],[@"connect\r\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@"disconnect\r\n" dataUsingEncoding:NSUTF8StringEncoding],[@"diagnostics\r\n" dataUsingEncoding:NSUTF8StringEncoding],
        [@" \tquery\n" dataUsingEncoding:NSUTF8StringEncoding],[@"query" dataUsingEncoding:NSUTF8StringEncoding],
        [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding],[NSData data],
        [NSData dataWithBytes:"\xff\n" length:2],[NSData dataWithBytes:"qu\0ery\n" length:7],
        [@"query\nextra" dataUsingEncoding:NSUTF8StringEncoding],
        [NSMutableData dataWithLength:1024],[NSMutableData dataWithLength:1025]];
    TLinkHelperClientAdmission owner(8);dispatch_queue_t queue=clientQueue();
    for(unsigned cycle=0;cycle<16;++cycle)for(NSData *request in requests){@autoreleasepool{
        int a[2],b[2];pair(a);pair(b);Socket oldPeer(a[0]),newPeer(b[0]);
        sendText(a[0],request.bytes,request.length);sendText(b[0],request.bytes,request.length);
        assert(::shutdown(a[0],SHUT_WR)==0&&::shutdown(b[0],SHUT_WR)==0);
        const int legacyFD=a[1];
        dispatch_async(queue,^{@autoreleasepool{Legacy::TLinkVPNBrokerHandleClient(legacyFD);}});
        Current::TLinkVPNBrokerEnqueueClient(owner,queue,b[1]);
        assert([reply(a[0]) isEqual:reply(b[0])]);drain(queue,owner);closed(a[1]);closed(b[1]);
    }}
}
static void faultCases(){
    dispatch_queue_t queue=clientQueue();
    for(unsigned kind=0;kind<7;++kind){
        TLinkHelperClientAdmission owner(8);int fd[2];pair(fd);Socket peer(fd[0]);sendCommand(fd[0],@"query\n");
        acquireFault=kind<2?static_cast<int>(kind+1):0;enqueueFault=kind>=2&&kind<5?static_cast<int>(kind-1):0;responseFault=kind>=5?static_cast<int>(kind-4):0;
        Current::TLinkVPNBrokerEnqueueClient(owner,queue,fd[1]);drain(queue,owner);closed(fd[1]);
        assert(reply(fd[0]).length==0);
        const auto stats=owner.stats();assert(stats.admitted==(kind<2?0U:1U)&&stats.finished==stats.admitted);
        acquireFault=enqueueFault=responseFault=0;
        int retry[2];pair(retry);Socket retryPeer(retry[0]);sendCommand(retry[0],@"query\n");
        Current::TLinkVPNBrokerEnqueueClient(owner,queue,retry[1]);assert(reply(retry[0]).length>0);drain(queue,owner);closed(retry[1]);
    }
    TLinkHelperClientAdmission stopped(8);dispatch_suspend(queue);int fd[2];pair(fd);Socket peer(fd[0]);sendCommand(fd[0],@"query\n");
    const unsigned before=responses.load();Current::TLinkVPNBrokerEnqueueClient(stopped,queue,fd[1]);stopped.stop();dispatch_resume(queue);
    assert(reply(fd[0]).length==0);drain(queue,stopped);assert(responses==before);closed(fd[1]);
}
static void ownerAndReuseCases(){
    dispatch_queue_t queue=clientQueue();dispatch_suspend(queue);int fd[2];pair(fd);Socket peer(fd[0]);sendCommand(fd[0],@"query\n");
    {TLinkHelperClientAdmission temporary(8);Current::TLinkVPNBrokerEnqueueClient(temporary,queue,fd[1]);assert(temporary.stats().active==1);}
    dispatch_resume(queue);assert(reply(fd[0]).length>0);dispatch_barrier_sync(queue,^{});closed(fd[1]);
    // Reuse the just-closed descriptor inside the lease's closer. A second close
    // when the block/lease is destroyed would invalidate this independent file.
    TLinkHelperClientAdmission owner(8);reuseSource=::open("/dev/null",O_RDONLY);assert(reuseSource>=0);
    int next[2];pair(next);Socket nextPeer(next[0]);sendCommand(next[0],@"query\n");
    Current::TLinkVPNBrokerEnqueueClient(owner,queue,next[1]);assert(reply(next[0]).length>0);drain(queue,owner);
    assert(reusedDescriptor==next[1]&&::fcntl(reusedDescriptor,F_GETFD)>=0);
    assert(::close(reusedDescriptor)==0&&::close(reuseSource)==0);reuseSource=reusedDescriptor=-1;
}
static void concurrentCases(){
    TLinkHelperClientAdmission owner(8);dispatch_queue_t queue=clientQueue();const unsigned beforeCloses=leaseCloses.load(),beforeResponses=responses.load();
    std::vector<std::thread> producers;
    for(unsigned thread=0;thread<8;++thread)producers.emplace_back([&owner,queue]{@autoreleasepool{
        for(unsigned n=0;n<1000;++n){int fd[2];pair(fd);sendCommand(fd[0],@"query\n");Current::TLinkVPNBrokerEnqueueClient(owner,queue,fd[1]);assert(::close(fd[0])==0);}
    }});
    for(std::thread &producer:producers)producer.join();drain(queue,owner);
    const auto stats=owner.stats();assert(stats.admitted+stats.rejected==8000&&stats.finished==stats.admitted&&stats.peak<=8);
    assert(leaseCloses==beforeCloses+stats.finished&&responses==beforeResponses+stats.admitted);
}
static void ingressCases(){
    TLinkHelperClientAdmission owner(8);dispatch_queue_t queue=clientQueue();fakeTime=true;
    for(unsigned kind=0;kind<3;++kind){
        clockMs=kind==2?UINT64_MAX:100;dispatch_suspend(queue);int fd[2];pair(fd);Socket peer(fd[0]);sendCommand(fd[0],@"query\n");
        const unsigned before=responses.load(),reads=ingressReads.load();
        Current::TLinkVPNBrokerEnqueueClient(owner,queue,fd[1]);
        if(kind==0)clockMs=30100;if(kind==1)clockMs=99;
        dispatch_resume(queue);assert(reply(fd[0]).length==0);drain(queue,owner);closed(fd[1]);
        assert(responses==before&&ingressReads==reads);
    }
    // Real nonblocking recv followed by real poll with only one millisecond left.
    clockMs=100;dispatch_suspend(queue);int empty[2];pair(empty);Socket emptyPeer(empty[0]);
    const unsigned before=responses.load(),reads=ingressReads.load(),waits=ingressWaits.load();
    Current::TLinkVPNBrokerEnqueueClient(owner,queue,empty[1]);clockMs=30099;dispatch_resume(queue);
    assert(reply(empty[0]).length==0);drain(queue,owner);
    assert(responses==before&&ingressReads==reads+1&&ingressWaits==waits+1);closed(empty[1]);
    // Every byte advances the same deadline. Partial bytes cannot become a task.
    clockMs=100;readLimit=1;advanceReadMs=1000;int drip[2];pair(drip);Socket dripPeer(drip[0]);
    std::vector<uint8_t> payload(1024,'x');sendText(drip[0],payload.data(),payload.size());
    const unsigned dripReads=ingressReads.load();Current::TLinkVPNBrokerEnqueueClient(owner,queue,drip[1]);
    assert(reply(drip[0]).length==0);drain(queue,owner);
    assert(ingressReads==dripReads+30&&responses==before&&clockMs==30100);closed(drip[1]);
    readLimit=SIZE_MAX;advanceReadMs=0;
    // Expiry while preparing the decoded command must also stop dispatch.
    clockMs=100;expireDecode=true;int decode[2];pair(decode);Socket decodePeer(decode[0]);sendCommand(decode[0],@"query\n");
    Current::TLinkVPNBrokerEnqueueClient(owner,queue,decode[1]);assert(reply(decode[0]).length==0);drain(queue,owner);
    assert(responses==before);closed(decode[1]);expireDecode=false;
    clockMs=100;readLimit=2;readsBeforeFault=1;int fault[2];pair(fault);Socket faultPeer(fault[0]);sendCommand(fault[0],@"query\n");
    Current::TLinkVPNBrokerEnqueueClient(owner,queue,fault[1]);assert(reply(fault[0]).length==0);drain(queue,owner);
    assert(responses==before);closed(fault[1]);readLimit=SIZE_MAX;readsBeforeFault=-1;
    // Capacity recovers and a fresh LF/EOF request still follows the old path.
    clockMs=50000;int retry[2];pair(retry);Socket retryPeer(retry[0]);sendCommand(retry[0],@"query\n");
    Current::TLinkVPNBrokerEnqueueClient(owner,queue,retry[1]);assert(reply(retry[0]).length>0);drain(queue,owner);
    assert(responses==before+1);closed(retry[1]);
}
int main(){@autoreleasepool{
    ::signal(SIGPIPE,SIG_IGN);
    fakeTime=true;clockMs=100; // Admission/parity stress is independent of CI scheduling time.
    puts("VPN broker Foundation: actual lease/handler, held and running GCD queues and real sockets; response provider controlled");
    heldQueueCases();blockedReaderCases();parserParityCases();faultCases();ownerAndReuseCases();ingressCases();concurrentCases();
    puts("VPN broker admission/ingress passed: eight slots, ninth rejection, frozen handler parity, exceptions/discard/owner/FD reuse, queued expiry and clock faults, real DONTWAIT/poll, trickled input/decode expiry without dispatch, recovery and 8k concurrent clients. Manager/output/device qualification pending.");
}return 0;}
