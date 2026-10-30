#include "../shared/TLinkVPNBrokerClientIO.h"
#include "../shared/TLinkNativeBudget.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>
using namespace TLinkHelperIO;
using TLinkVPNBrokerIngress::Window;
namespace Client=TLinkVPNBrokerClientIO;
struct Peer {
    uint64_t time=100,connectCost=0,finishCost=0,sendCost=0,readCost=0;
    int beginError=0,finishError=0,readError=0,sendError=0,pollError=0;
    unsigned begins=0,finishes=0,waits=0,reads=0,sends=0,emptyPolls=0;
    unsigned readInterrupts=0,sendInterrupts=0,readBlocks=0,sendBlocks=0;
    bool stalled=false,zeroWrite=false,lateReady=false;
    size_t chunk=SIZE_MAX,offset=0;std::string input="0;;1\r\n",output;
    std::function<void()> onWait,onSend,onRead,onConnect,onFinish;
    static uint64_t now(void *p){return static_cast<Peer *>(p)->time;}
    static int wait(void *p,int,bool,int timeout,int &error){
        auto &s=*static_cast<Peer *>(p);assert(timeout>0&&timeout<=250);++s.waits;
        if(s.onWait)s.onWait();
        if(s.pollError){error=s.pollError;s.pollError=0;++s.time;return -1;}
        if(s.lateReady){s.time+=30000;return 1;}
        if(s.stalled||s.emptyPolls){if(s.emptyPolls)--s.emptyPolls;s.time+=static_cast<uint64_t>(timeout);return 0;}
        return 1;
    }
    static ptrdiff_t send(void *p,int,const uint8_t *bytes,size_t count,int &error){
        auto &s=*static_cast<Peer *>(p);++s.sends;s.time+=s.sendCost;
        if(s.onSend)s.onSend();
        if(s.sendInterrupts){--s.sendInterrupts;error=EINTR;return -1;}
        if(s.sendBlocks||s.stalled){if(s.sendBlocks)--s.sendBlocks;error=EAGAIN;return -1;}
        if(s.sendError){error=s.sendError;return -1;}if(s.zeroWrite)return 0;
        const size_t n=std::min(count,s.chunk);s.output.append(reinterpret_cast<const char *>(bytes),n);return static_cast<ptrdiff_t>(n);
    }
    static ptrdiff_t receive(void *p,int,uint8_t *bytes,size_t count,int &error){
        auto &s=*static_cast<Peer *>(p);++s.reads;s.time+=s.readCost;
        if(s.onRead)s.onRead();
        if(s.readInterrupts){--s.readInterrupts;error=EINTR;return -1;}
        if(s.readBlocks||s.stalled){if(s.readBlocks)--s.readBlocks;error=EWOULDBLOCK;return -1;}
        if(s.readError){error=s.readError;return -1;}
        const size_t n=std::min(std::min(count,s.chunk),s.input.size()-s.offset);
        std::memcpy(bytes,s.input.data()+s.offset,n);s.offset+=n;return static_cast<ptrdiff_t>(n);
    }
    static int begin(void *p,int,int &error){auto &s=*static_cast<Peer *>(p);++s.begins;s.time+=s.connectCost;if(s.onConnect)s.onConnect();error=s.beginError;return error?-1:0;}
    static int finish(void *p,int,int &error){auto &s=*static_cast<Peer *>(p);++s.finishes;s.time+=s.finishCost;if(s.onFinish)s.onFinish();error=s.finishError;return error?-1:0;}
    Ops ops(){return {this,now,wait,receive,send};}
    Client::ConnectOps connector(){return {this,begin,finish};}
};
static Result connect(Peer &s,const Window &window){Client::BoundedOps bounded(s.ops(),window);return Client::connect(bounded.ops(),s.connector(),0,window);}
static Result write(Peer &s,const Window &window,const std::string &bytes){Client::BoundedOps bounded(s.ops(),window);return writeBytes(bounded.ops(),0,reinterpret_cast<const uint8_t *>(bytes.data()),bytes.size(),window.deadline);}
static Result read(Peer &s,const Window &window,size_t &count){Client::BoundedOps bounded(s.ops(),window);uint8_t bytes[4096];return TLinkVPNBrokerIngress::readChunk(bounded.ops(),0,bytes,sizeof(bytes),window,count);}
static bool callerStopped(const void *p){const auto &budget=*static_cast<const TLinkNativeBudgetPtr *>(p);return budget&&budget->stopped();}
static void callerCases(){
    auto token=std::make_shared<TLinkNativeCancellation>();
    TLinkNativeBudgetPtr budget=std::make_shared<TLinkNativeBudget>(token,0,1024);
    Peer peer;Window window(100);Client::BoundedOps bounded(peer.ops(),window,&budget,callerStopped);const Ops io=bounded.ops();
    token->cancel();size_t count=77;uint8_t bytes[32]{};
    assert(Client::connect(io,peer.connector(),0,window).code==Code::Timeout&&peer.begins==0);
    assert(writeBytes(io,0,bytes,sizeof(bytes),window.deadline).code==Code::Timeout&&peer.sends==0);
    assert(TLinkVPNBrokerIngress::readChunk(io,0,bytes,sizeof(bytes),window,count).code==Code::Timeout&&count==0&&peer.reads==0);
    int error=0;assert(io.send(io.context,0,bytes,1,error)<0&&error==ECANCELED&&peer.sends==0);
    assert(io.receive(io.context,0,bytes,1,error)<0&&error==ECANCELED&&peer.reads==0);
    for(unsigned stage=0;stage<5;++stage){
        token=std::make_shared<TLinkNativeCancellation>();budget=std::make_shared<TLinkNativeBudget>(token,0,1024);peer=Peer{};
        const auto stop=[token]{token->cancel();};
        if(stage==0)peer.onConnect=stop;
        if(stage==1){peer.beginError=EINPROGRESS;peer.onFinish=stop;}
        if(stage==2)peer.onSend=stop;
        if(stage==3)peer.onRead=stop;
        if(stage==4){peer.stalled=true;peer.onWait=stop;}
        Result result{Code::Ok};
        if(stage<2)result=Client::connect(io,peer.connector(),0,window);
        else if(stage==2)result=writeBytes(io,0,bytes,1,window.deadline);
        else result=TLinkVPNBrokerIngress::readChunk(io,0,bytes,sizeof(bytes),window,count);
        assert(result.code==Code::Timeout&&budget->reason()==TLinkNativeStop::Cancelled);
        if(stage==4)assert(peer.waits==1&&peer.reads==1);
    }
    // Keep clock domains separate: native parent state, not a converted epoch.
    auto parent=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},TLinkNativeNowNs()-1,1024);
    budget=std::make_shared<TLinkNativeBudget>(0,parent);peer=Peer{};
    assert(Client::connect(io,peer.connector(),0,window).code==Code::Timeout&&peer.begins==0);
    budget=std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,1);assert(!budget->outputAllowed(2));
    assert(writeBytes(io,0,bytes,1,window.deadline).code==Code::Timeout&&peer.sends==0);
    // Snapshot parent remains effective even if nested code changes TLS.
    token=std::make_shared<TLinkNativeCancellation>();parent=std::make_shared<TLinkNativeBudget>(token,0,1024);budget=std::make_shared<TLinkNativeBudget>(0,parent);
    {TLinkNativeBudgetScope scope(std::make_shared<TLinkNativeBudget>(std::shared_ptr<TLinkNativeCancellation>{},0,1024));token->cancel();assert(!TLinkNativeStopped()&&callerStopped(&budget));}
    // Existing cleanup policy is inherited rather than overridden by the adapter.
    budget=std::make_shared<TLinkNativeBudget>(token,TLinkNativeNowNs()-1,1024,true);assert(!callerStopped(&budget));
    peer=Peer{};assert(Client::connect(io,peer.connector(),0,window).ok());
    budget.reset();peer=Peer{};assert(Client::connect(io,peer.connector(),0,window).ok());
    for(unsigned n=0;n<1000;++n){
        token=std::make_shared<TLinkNativeCancellation>();budget=std::make_shared<TLinkNativeBudget>(token,0,1024);
        std::thread stop([token]{token->cancel();});
        while(!callerStopped(&budget))std::this_thread::yield();
        stop.join();peer=Peer{};assert(Client::connect(io,peer.connector(),0,window).code==Code::Timeout&&peer.begins==0);
    }
}
int main(){
    for(uint64_t n=0;n<100000;++n){Peer s;s.time=n;const Result result=connect(s,Window(100));assert(result.ok()==(n>=100&&n<30100));assert(s.begins==(result.ok()?1U:0U));}
    for(int error:std::vector<int>{EINPROGRESS,EINTR,EALREADY}){Peer s;s.beginError=error;s.pollError=EINTR;s.emptyPolls=2;assert(connect(s,Window(100)).ok()&&s.finishes==1&&s.waits==4&&s.time==601);}
    Peer refused;refused.beginError=ECONNREFUSED;assert(connect(refused,Window(100)).error==ECONNREFUSED&&refused.waits==0);
    Peer failed;failed.beginError=EINPROGRESS;failed.finishError=ECONNREFUSED;assert(connect(failed,Window(100)).error==ECONNREFUSED&&failed.finishes==1);
    Peer poll;poll.beginError=EINPROGRESS;poll.pollError=EBADF;assert(connect(poll,Window(100)).error==EBADF&&poll.finishes==0);
    Peer pending;pending.beginError=EINPROGRESS;pending.stalled=true;assert(connect(pending,Window(100)).code==Code::Timeout&&pending.waits==120&&pending.finishes==0);
    Peer late;late.connectCost=30000;assert(connect(late,Window(100)).code==Code::Timeout);
    Peer lateFinish;lateFinish.beginError=EINPROGRESS;lateFinish.finishCost=30000;assert(connect(lateFinish,Window(100)).code==Code::Timeout);
    Peer latePoll;latePoll.beginError=EINPROGRESS;latePoll.lateReady=true;assert(connect(latePoll,Window(100)).code==Code::Timeout&&latePoll.finishes==0);
    Peer invalid;invalid.time=UINT64_MAX;assert(connect(invalid,Window(UINT64_MAX)).code==Code::Timeout&&invalid.begins==0);
    Peer edge;edge.time=UINT64_MAX-2;assert(connect(edge,Window(UINT64_MAX-3)).ok());
    const std::string request="query\r\n";
    Peer fragmented;fragmented.chunk=1;fragmented.sendInterrupts=2;fragmented.sendBlocks=2;fragmented.pollError=EINTR;
    assert(write(fragmented,Window(100),request).ok()&&fragmented.output==request);
    size_t count=0;fragmented.readInterrupts=2;fragmented.readBlocks=2;assert(read(fragmented,Window(100),count).ok()&&count==1);
    // The same window includes connect and write; response progress never renews it.
    Peer total;total.connectCost=10000;assert(connect(total,Window(100)).ok());total.sendCost=10000;
    assert(write(total,Window(100),request).ok());total.chunk=1;total.readCost=5000;
    assert(read(total,Window(100),count).ok()&&count==1);assert(read(total,Window(100),count).code==Code::Timeout&&count==0&&total.time==30100);
    for(int error:std::vector<int>{EIO,ECONNRESET}){Peer s;s.readError=error;assert(read(s,Window(100),count).error==error&&count==0);s.sendError=error;assert(write(s,Window(100),request).error==error);}
    Peer eof;eof.input.clear();assert(read(eof,Window(100),count).ok()&&count==0);
    Peer zero;zero.zeroWrite=true;assert(write(zero,Window(100),request).error==EPIPE);
    Peer drip;drip.chunk=1;drip.readCost=10000;assert(read(drip,Window(100),count).ok()&&count==1);assert(read(drip,Window(100),count).ok());assert(read(drip,Window(100),count).code==Code::Timeout&&count==0);
    Peer blocked;blocked.stalled=true;assert(write(blocked,Window(100),request).code==Code::Timeout&&blocked.output.empty()&&blocked.waits==120);
    Peer interrupted;interrupted.readInterrupts=1000;interrupted.readCost=100;assert(read(interrupted,Window(100),count).code==Code::Timeout&&interrupted.reads==300&&count==0);
    callerCases();
    puts("VPN client IO passed: 100k fixed-window plans, nonblocking connect completion/refusal, 250ms poll slices, EINTR/EAGAIN, shared connect/write/read budget, trickle/late rejection and exact writes/EOF/faults.");
    puts("VPN caller stop passed: pre-connect/read/write rejection, in-flight phase/poll cancellation, inherited native deadline/output, captured parent versus nested TLS, cleanup/null policy and 1000 concurrent token publications.");
}
