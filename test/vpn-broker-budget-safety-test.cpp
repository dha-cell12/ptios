#include "../shared/TLinkVPNBrokerBudget.h"
#include <cassert>
#include <cstdio>
#include <string>
#include <vector>
using namespace TLinkHelperIO;
using TLinkVPNBrokerIngress::Window;
using TLinkVPNBrokerBudget::WaitWindow;
struct Output {
    uint64_t time=100,step=0;size_t chunk=SIZE_MAX;std::string bytes;
    unsigned calls=0,waits=0,interrupts=0,blocked=0,pollInterrupts=0;int fault=0;bool stall=false,zero=false;
    static uint64_t now(void *p){return static_cast<Output *>(p)->time;}
    static int wait(void *p,int,bool writing,int budget,int &error){
        auto &s=*static_cast<Output *>(p);assert(writing&&budget>0&&budget<=30000);++s.waits;
        if(s.pollInterrupts){--s.pollInterrupts;++s.time;error=EINTR;return -1;}
        if(s.stall){s.time+=static_cast<uint64_t>(budget);return 0;}return 1;
    }
    static ptrdiff_t receive(void *,int,uint8_t *,size_t,int &){assert(false);return -1;}
    static ptrdiff_t send(void *p,int,const uint8_t *bytes,size_t count,int &error){
        auto &s=*static_cast<Output *>(p);++s.calls;s.time+=s.step;
        if(s.interrupts){--s.interrupts;error=EINTR;return -1;}
        if(s.fault){error=s.fault;return -1;}
        if(s.blocked){--s.blocked;error=EAGAIN;return -1;}
        if(s.stall){error=EWOULDBLOCK;return -1;}if(s.zero)return 0;
        const size_t n=std::min(count,s.chunk);s.bytes.append(reinterpret_cast<const char *>(bytes),n);return static_cast<ptrdiff_t>(n);
    }
    Ops ops(){return {this,now,wait,receive,send};}
};
static Result write(Output &out,const Window &window,const std::string &bytes){return TLinkVPNBrokerBudget::writeResponse(out.ops(),0,reinterpret_cast<const uint8_t *>(bytes.data()),bytes.size(),window);}
int main(){
    for(uint64_t n=0;n<100000;++n){
        const uint64_t start=100+n%31000,now=100+n%40000;const int limit=n%2?8000:24000;
        const WaitWindow budget(Window(100),start,limit);const uint64_t end=std::min<uint64_t>(30100,start+static_cast<uint64_t>(limit));
        const int expected=start>=30100||now<start||now>=end?0:static_cast<int>(end-now);
        assert(budget.remaining(now)==expected);
    }
    assert(!WaitWindow(Window(100),99,8000).remaining(100));
    assert(!WaitWindow(Window(100),100,0).remaining(100)&&!WaitWindow(Window(100),100,-1).remaining(100));
    assert(!WaitWindow(Window(UINT64_MAX),UINT64_MAX,8000).remaining(UINT64_MAX));
    assert(WaitWindow(Window(UINT64_MAX-10),UINT64_MAX-9,24000).remaining(UINT64_MAX-1)==1);
    assert(WaitWindow(Window(100),100,8000).remaining(8000)==100); // Starting work consumes the phase.
    for(size_t chunk:std::vector<size_t>{1,7,4096}){
        Output out;out.chunk=chunk;out.interrupts=3;out.blocked=2;out.pollInterrupts=2;
        const std::string expected(8192,'x');assert(write(out,Window(100),expected).ok()&&out.bytes==expected&&out.waits==4);
    }
    for(uint64_t age:std::vector<uint64_t>{0,29999,30000,40000}){
        Output out;out.time+=age;const Result result=write(out,Window(100),"0;;1\r\n");
        assert(result.ok()==(age<30000));assert(out.calls==(age<30000?1U:0U));
    }
    Output future;future.time=99;assert(write(future,Window(100),"x").code==Code::Timeout&&future.calls==0);
    Output slow;slow.step=1000;slow.chunk=1;assert(write(slow,Window(100),std::string(1000,'x')).code==Code::Timeout&&slow.calls==30&&slow.bytes.size()==30);
    Output stall;stall.time=30090;stall.stall=true;assert(write(stall,Window(100),"x").code==Code::Timeout&&stall.time==30100&&stall.waits==1);
    for(int error:std::vector<int>{EIO,EPIPE,ECONNRESET}){Output out;out.fault=error;const Result result=write(out,Window(100),"x");assert(result.code==Code::Write&&result.error==error&&out.bytes.empty());}
    Output zero;zero.zero=true;assert(write(zero,Window(100),"x").error==EPIPE);
    Output empty;assert(write(empty,Window(100),"").ok()&&empty.calls==0);
    puts("VPN broker budget core passed: 100k outer/8s/24s phase plans, start-time consumption/clock edges, exact partial writes, EINTR/EAGAIN/backpressure/faults and non-renewing output deadline.");
}
