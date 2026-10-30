#include "../shared/TLinkVPNHelperChild.h"
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <thread>
#include <vector>
using namespace TLinkVPNHelperChild;
struct Fake {
    uint64_t now=100,exitAt=UINT64_MAX;
    unsigned probes=0,terms=0,kills=0,retries=0;
    bool retired=false,missing=false,waitError=false,termExit=false,killExit=false,denySignals=false;
    Ops ops(){return {this,
        [](void *p){return static_cast<Fake *>(p)->now;},
        [](void *p,int pid,int &status,int &error){
            Fake &f=*static_cast<Fake *>(p);assert(pid==42&&!f.retired);++f.probes;
            if(f.missing){f.retired=true;error=ECHILD;return Probe::Missing;}
            if(f.retries){--f.retries;error=EINTR;return Probe::Retry;}
            if(f.waitError){f.waitError=false;error=EINVAL;return Probe::Error;}
            if(f.now>=f.exitAt){f.retired=true;status=73;return Probe::Reaped;}
            return Probe::Running;
        },
        [](void *p,int pid,Signal kind){
            Fake &f=*static_cast<Fake *>(p);assert(pid==42&&!f.retired);
            if(kind==Signal::Term)++f.terms;else ++f.kills;
            if(f.denySignals)return EPERM;
            if((kind==Signal::Term&&f.termExit)||(kind==Signal::Kill&&f.killExit))f.exitAt=f.now+1;
            return 0;
        },
        [](void *p,unsigned ms){assert(ms<=PollMs);static_cast<Fake *>(p)->now+=ms;}};
    }
};
static void cases(){
    {Fake f;f.exitAt=100;Result r=wait(f.ops(),42);assert(r.reason==Reason::Finished&&r.retired&&r.status==73&&f.terms==0&&f.kills==0);}
    {Fake f;f.exitAt=120;f.retries=1;Result r=wait(f.ops(),42,30,10);assert(r.reason==Reason::Finished&&r.retired&&f.now==120&&f.kills==0);}
    {Fake f;f.termExit=true;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::Timeout&&r.retired&&f.terms==1&&f.kills==0&&r.termAttempted);}
    {Fake f;f.killExit=true;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::Timeout&&r.retired&&f.terms==1&&f.kills==1&&r.killAttempted);}
    {Fake f;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::Timeout&&!r.retired&&f.now==170&&f.terms==1&&f.kills==1);}
    {Fake f;f.missing=true;Result r=wait(f.ops(),42);assert(r.reason==Reason::WaitFailed&&r.retired&&f.terms==0&&f.kills==0&&r.error==ECHILD);}
    {Fake f;f.waitError=true;f.killExit=true;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::WaitFailed&&r.retired&&r.error==EINVAL&&f.terms==1&&f.kills==1);}
    {Fake f;f.denySignals=true;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::Timeout&&!r.retired&&r.signalError==EPERM&&f.now==170);}
    {Fake f;f.retries=1000;Result r=wait(f.ops(),42,30,20);assert(r.reason==Reason::Timeout&&!r.retired&&f.terms==0&&f.kills==0&&f.now==170);}
    {Fake f;Result r=wait(f.ops(),0);assert(r.reason==Reason::WaitFailed&&r.retired&&f.probes==0);}
    {Fake f;Result r=wait(f.ops(),-1);assert(r.reason==Reason::WaitFailed&&r.retired&&f.probes==0);}
    {Fake f;Result r=wait(f.ops(),42,0,0);assert(r.reason==Reason::Timeout&&!r.retired&&f.probes==1&&f.kills==0);}
    assert(remaining(10,9,30)==0&&remaining(10,UINT64_MAX,30)==0&&remaining(UINT64_MAX-20,UINT64_MAX-10,30)==20);
    for(unsigned n=0;n<100000;++n){
        Fake f;f.termExit=n%3==0;f.killExit=n%3==1;
        Result r=wait(f.ops(),42,3,2);
        assert(r.reason==Reason::Timeout&&r.retired==(n%3!=2)&&f.terms==1&&f.kills==(n%3==0?0U:1U));
        assert(f.now<=107);
    }
}
static void admission(){
    assert(pending()==0);
    {
        Slot a,b,c,d,excess;assert(a.held()&&b.held()&&c.held()&&d.held()&&!excess.held()&&pending()==4);
    }
    std::vector<std::thread> workers;
    for(unsigned worker=0;worker<8;++worker)workers.emplace_back([]{
        for(unsigned n=0;n<10000;++n){Slot slot;assert(pending()<=MaxChildren);}
    });
    for(auto &worker:workers)worker.join();
    assert(pending()==0);
}
int main(){cases();admission();puts("VPN helper child core passed: exact-PID exits/EINTR/ECHILD/errors, TERM/KILL grace, denied signals, unreaped ownership, 100k deadlines and 80k bounded admission lifecycles.");}
