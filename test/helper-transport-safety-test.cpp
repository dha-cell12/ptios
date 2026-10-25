#include "../shared/TLinkHelperSocketIO.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
using namespace TLinkHelperIO;
struct Fake {
    uint64_t time=0,tick=0;std::string input,output;size_t offset=0,readChunk=4096,writeChunk=4096;
    unsigned readInterrupts=0,writeInterrupts=0,waitInterrupts=0,blocks=0,waitCalls=0;bool stall=false,zeroWrite=false;
    int readFault=0,writeFault=0;size_t failAfter=SIZE_MAX;
    static uint64_t now(void *p){return static_cast<Fake *>(p)->time;}
    static int wait(void *p,int,bool,int timeout,int &error){auto &s=*static_cast<Fake *>(p);++s.waitCalls;
        if(s.stall){s.time+=static_cast<uint64_t>(timeout);return 0;}
        s.time+=s.tick;if(s.waitInterrupts){--s.waitInterrupts;error=EINTR;return -1;}return 1;}
    static ptrdiff_t receive(void *p,int,uint8_t *data,size_t capacity,int &error){auto &s=*static_cast<Fake *>(p);s.time+=s.tick;
        if(s.readInterrupts){--s.readInterrupts;error=EINTR;return -1;}if(s.readFault){error=s.readFault;return -1;}
        if(s.stall){error=EAGAIN;return -1;}if(s.blocks){--s.blocks;error=EAGAIN;return -1;}
        const size_t n=std::min(std::min(s.readChunk,capacity),s.input.size()-s.offset);
        std::copy(s.input.begin()+s.offset,s.input.begin()+s.offset+n,data);s.offset+=n;return static_cast<ptrdiff_t>(n);}
    static ptrdiff_t send(void *p,int,const uint8_t *data,size_t length,int &error){auto &s=*static_cast<Fake *>(p);s.time+=s.tick;
        if(s.writeInterrupts){--s.writeInterrupts;error=EINTR;return -1;}if(s.writeFault||s.output.size()>=s.failAfter){error=s.writeFault?s.writeFault:EIO;return -1;}
        if(s.stall){error=EAGAIN;return -1;}if(s.blocks){--s.blocks;error=EAGAIN;return -1;}if(s.zeroWrite)return 0;
        const size_t n=std::min(s.writeChunk,length);s.output.append(reinterpret_cast<const char *>(data),n);return static_cast<ptrdiff_t>(n);}
    Ops ops(){return {this,now,wait,receive,send};}
};
static void portableCases(){
    assert(!Deadline(0,0).valid&&!Deadline(0,-1).valid);assert(Deadline(10,INT32_MAX).remaining(10)==30000);
    assert(Deadline(UINT64_MAX-2,10).end==UINT64_MAX);assert(Deadline(0,3).remaining(3)==0);
    std::vector<uint8_t> frame;
    for(unsigned n=0;n<100000;++n){
        Fake io;io.input=std::string(n%64+1,'x')+"\nignored";io.readChunk=n%31+1;io.readInterrupts=n%3;io.blocks=n%2;io.waitInterrupts=n%3;
        assert(readFrame(io.ops(),0,frame,Deadline(0,100)).ok());assert(std::string(frame.begin(),frame.end())==std::string(n%64+1,'x'));
        io.offset=0;io.writeChunk=n%17+1;io.writeInterrupts=n%3;io.blocks=n%2;
        assert(writeFrame(io.ops(),0,frame.data(),frame.size(),Deadline(0,100)).ok());assert(io.output==std::string(n%64+1,'x')+"\n");
    }
    Fake exact;exact.input=std::string(MaxFrameBytes,'x')+"\n";assert(readFrame(exact.ops(),0,frame,Deadline(0,10)).ok());assert(frame.size()==MaxFrameBytes);
    Fake tooLarge;tooLarge.input=std::string(MaxFrameBytes+1,'x')+"\n";assert(readFrame(tooLarge.ops(),0,frame,Deadline(0,10)).code==Code::TooLarge);assert(frame.size()<=MaxFrameBytes);
    Fake eof;eof.input="{}";assert(readFrame(eof.ops(),0,frame,Deadline(0,10)).ok());assert(frame.size()==2);
    Fake empty;assert(readFrame(empty.ops(),0,frame,Deadline(0,10)).code==Code::Empty);
    Fake slow;slow.input=std::string(100,'x');slow.readChunk=1;slow.tick=1;assert(readFrame(slow.ops(),0,frame,Deadline(0,10)).code==Code::Timeout);assert(frame.size()<10);
    Fake interrupted;interrupted.readInterrupts=1000;interrupted.tick=1;assert(readFrame(interrupted.ops(),0,frame,Deadline(0,10)).code==Code::Timeout);
    Fake busy;busy.stall=true;assert(readFrame(busy.ops(),0,frame,Deadline(0,10)).code==Code::Timeout);assert(busy.time==10);
    Fake pollInterrupted;pollInterrupted.blocks=100;pollInterrupted.waitInterrupts=100;pollInterrupted.tick=1;assert(readFrame(pollInterrupted.ops(),0,frame,Deadline(0,10)).code==Code::Timeout);
    Fake readFault;readFault.readFault=EIO;assert(readFrame(readFault.ops(),0,frame,Deadline(0,10)).code==Code::Read);
    const uint8_t data[20]={};Fake output;output.writeChunk=1;output.tick=1;assert(writeFrame(output.ops(),0,data,sizeof(data),Deadline(0,10)).code==Code::Timeout);assert(output.output.size()==10);
    Fake outputBusy;outputBusy.stall=true;assert(writeFrame(outputBusy.ops(),0,data,sizeof(data),Deadline(0,10)).code==Code::Timeout);
    Fake outputFault;outputFault.writeChunk=3;outputFault.failAfter=6;assert(writeFrame(outputFault.ops(),0,data,sizeof(data),Deadline(0,10)).code==Code::Write);assert(outputFault.output.size()==6);
    Fake zero;zero.zeroWrite=true;assert(writeFrame(zero.ops(),0,data,sizeof(data),Deadline(0,10)).error==EPIPE);
    Fake over;assert(writeFrame(over.ops(),0,data,SIZE_MAX,Deadline(0,10)).code==Code::TooLarge);assert(over.output.empty());
    Fake invalid;assert(readFrame(invalid.ops(),0,frame,Deadline(0,0)).code==Code::InvalidTimeout);assert(writeFrame(invalid.ops(),0,data,1,Deadline(0,0)).code==Code::InvalidTimeout);
    puts("Helper transport core passed: 100k partial/EINTR/EAGAIN frame lifecycles, absolute slow-progress deadlines, exact cap/oversize/EOF policy, failed/zero writes and no deadline renewal.");
}
#if !defined(_WIN32)
static void posixCases(){
    int pair[2];assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket sender(pair[0]),receiver(pair[1]);assert(sender.prepare().ok()&&receiver.prepare().ok());
    const uint8_t body[]={'{','}'};assert(writeFrame(posixOps(),sender.fd(),body,sizeof(body),Deadline(nowMs(),1000)).ok());
    std::vector<uint8_t> frame;assert(readFrame(posixOps(),receiver.fd(),frame,Deadline(nowMs(),1000)).ok());assert(frame.size()==2);
    receiver.close();assert(!writeFrame(posixOps(),sender.fd(),body,sizeof(body),Deadline(nowMs(),100)).ok());
    const int closed=sender.fd();sender.close();sender.close();assert(::fcntl(closed,F_GETFD,0)<0&&errno==EBADF);
    assert(::socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);Socket stalled(pair[0]),peer(pair[1]);assert(stalled.prepare().ok()&&peer.prepare().ok());
    int small=4096;assert(::setsockopt(stalled.fd(),SOL_SOCKET,SO_SNDBUF,&small,sizeof(small))==0);std::vector<uint8_t> large(MaxFrameBytes,'x');
    assert(writeFrame(posixOps(),stalled.fd(),large.data(),large.size(),Deadline(nowMs(),50)).code==Code::Timeout);
    assert(readFrame(posixOps(),stalled.fd(),frame,Deadline(nowMs(),20)).code==Code::Timeout);
    char directory[]="/tmp/tlh-XXXXXX";assert(::mkdtemp(directory));const std::string path=std::string(directory)+"/s";
    Socket listener(::socket(AF_UNIX,SOCK_STREAM,0));assert(listener.fd()>=0);sockaddr_un address{};address.sun_family=AF_UNIX;std::copy(path.begin(),path.end(),address.sun_path);
    assert(::bind(listener.fd(),reinterpret_cast<sockaddr *>(&address),sizeof(address))==0&&::listen(listener.fd(),1)==0);
    Socket client(::socket(AF_UNIX,SOCK_STREAM,0));assert(client.prepare().ok());assert(connectUnix(client,path.c_str(),Deadline(nowMs(),1000)).ok());Socket accepted(::accept(listener.fd(),nullptr,nullptr));assert(accepted.fd()>=0);
    Socket missing(::socket(AF_UNIX,SOCK_STREAM,0));assert(missing.prepare().ok());assert(connectUnix(missing,(path+"missing").c_str(),Deadline(nowMs(),100)).code==Code::Connect);
    assert(connectUnix(missing,std::string(sizeof(address.sun_path),'a').c_str(),Deadline(nowMs(),100)).error==ENAMETOOLONG);
    listener.close();assert(::unlink(path.c_str())==0&&::rmdir(directory)==0);
    puts("Helper transport POSIX passed: real nonblocking Unix connect, socketpair frames, peer close without SIGPIPE, backpressure timeout and owned descriptor cleanup.");
}
#endif
int main(){portableCases();
#if !defined(_WIN32)
    posixCases();
#endif
}
