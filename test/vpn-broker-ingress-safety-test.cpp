#include "../shared/TLinkVPNBrokerIngress.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
using namespace TLinkHelperIO;
using TLinkVPNBrokerIngress::Window;
struct Fake {
    uint64_t time=100,step=0;std::string input;size_t position=0,chunk=256;
    int fault=0;unsigned interrupted=0,readInterrupted=0,blocked=0,reads=0,waits=0;bool stall=false,overshoot=false,badCount=false;
    static uint64_t now(void *p){return static_cast<Fake *>(p)->time;}
    static int wait(void *p,int,bool writing,int budget,int &error){
        auto &s=*static_cast<Fake *>(p);assert(!writing&&budget>0&&budget<=30000);++s.waits;
        if(s.interrupted){--s.interrupted;++s.time;error=EINTR;return -1;}
        if(s.stall){s.time+=static_cast<uint64_t>(budget);return 0;}
        if(s.overshoot){s.time+=30000;return 1;}return 1;
    }
    static ptrdiff_t read(void *p,int,uint8_t *bytes,size_t capacity,int &error){
        auto &s=*static_cast<Fake *>(p);++s.reads;s.time+=s.step;
        if(s.readInterrupted){--s.readInterrupted;error=EINTR;return -1;}
        if(s.fault){error=s.fault;return -1;}
        if(s.blocked){--s.blocked;error=EAGAIN;return -1;}
        if(s.stall){error=EWOULDBLOCK;return -1;}
        if(s.badCount)return static_cast<ptrdiff_t>(capacity+1);
        const size_t count=std::min(std::min(capacity,s.chunk),s.input.size()-s.position);
        if(count)std::memcpy(bytes,s.input.data()+s.position,count);
        s.position+=count;return static_cast<ptrdiff_t>(count);
    }
    static ptrdiff_t write(void *,int,const uint8_t *,size_t,int &){assert(false);return -1;}
    Ops ops(){return {this,now,wait,read,write};}
};
static Result collect(Fake &io,const Window &window,std::vector<uint8_t> &out){
    while(out.size()<1024){uint8_t buffer[256];size_t count=0;
        const Result result=TLinkVPNBrokerIngress::readChunk(io.ops(),0,buffer,std::min<size_t>(sizeof(buffer),1024-out.size()),window,count);
        if(!result.ok())return result;
        if(!count)break;
        out.insert(out.end(),buffer,buffer+count);if(std::memchr(buffer,'\n',count))break;
    }
    return window.remaining(io.time)?Result{Code::Ok}:Result{Code::Timeout};
}
static void normalCases(){
    for(size_t size=0;size<=1100;++size){
        for(size_t chunk:std::vector<size_t>{1,7,256}){
            Fake io;io.input=std::string(size,'x');io.chunk=chunk;std::vector<uint8_t> out;
            assert(collect(io,Window(100),out).ok()&&out.size()==std::min<size_t>(size,1024));
        }
    }
    for(const std::string &input:std::vector<std::string>{"query\r\n","query","a\nb","a\n\n",std::string("q\0x\n",4)}){
        Fake io;io.input=input;std::vector<uint8_t> out;assert(collect(io,Window(100),out).ok());
        assert(std::string(out.begin(),out.end())==input); // Original whole-chunk LF behavior.
    }
    for(uint64_t age=0;age<100000;++age){
        Fake io;io.time=100+age;io.input="query\n";std::vector<uint8_t> out;
        const Result result=collect(io,Window(100),out);
        assert(result.ok()==(age<30000));assert(io.reads==(age<30000?1U:0U));
    }
}
static void faultCases(){
    Fake io;io.input="query\n";io.blocked=8;io.interrupted=3;std::vector<uint8_t> out;
    assert(collect(io,Window(100),out).ok()&&io.waits==11&&io.reads==9);
    Fake interruptions;interruptions.input="query\n";interruptions.readInterrupted=5;out.clear();
    assert(collect(interruptions,Window(100),out).ok()&&interruptions.reads==6&&interruptions.time==100);
    for(int fault:std::vector<int>{EIO,ECONNRESET,EBADF}){
        Fake broken;broken.input="query\n";broken.fault=fault;size_t count=123;uint8_t byte=0;
        const Result result=TLinkVPNBrokerIngress::readChunk(broken.ops(),0,&byte,1,Window(100),count);
        assert(result.code==Code::Read&&result.error==fault&&count==0);
    }
    Fake late;late.input="query\n";late.step=30000;out.clear();assert(collect(late,Window(100),out).code==Code::Timeout&&out.empty());
    Fake empty;empty.step=30000;out.clear();assert(collect(empty,Window(100),out).code==Code::Timeout&&out.empty());
    Fake stalled;stalled.stall=true;out.clear();assert(collect(stalled,Window(100),out).code==Code::Timeout&&stalled.time==30100);
    Fake pollLate;pollLate.blocked=1;pollLate.overshoot=true;out.clear();assert(collect(pollLate,Window(100),out).code==Code::Timeout&&pollLate.reads==1);
    Fake wrong;wrong.badCount=true;size_t count=123;uint8_t buffer[4];
    assert(TLinkVPNBrokerIngress::readChunk(wrong.ops(),0,buffer,sizeof(buffer),Window(100),count).code==Code::Read&&count==0);
    assert(TLinkVPNBrokerIngress::readChunk(wrong.ops(),0,nullptr,1,Window(100),count).code==Code::Read);
    assert(!Window(UINT64_MAX).remaining(UINT64_MAX)&&!Window(100).remaining(99));
    assert(Window(UINT64_MAX-10).remaining(UINT64_MAX-1)==1&&!Window(UINT64_MAX-10).remaining(UINT64_MAX));
    for(unsigned n=0;n<1000;++n){
        Fake drip;drip.input=std::string(1024,'x');drip.chunk=1;drip.step=1000;out.clear();
        assert(collect(drip,Window(100),out).code==Code::Timeout&&drip.time==30100&&out.size()==29&&drip.reads==30);
    }
}
int main(){normalCases();faultCases();puts("VPN broker ingress core passed: 100k queue-age boundaries, unchanged LF/EOF/1024 chunk framing, trickled input without renewal, receive/poll EINTR/EAGAIN/fault/late expiry and invalid clocks.");}
