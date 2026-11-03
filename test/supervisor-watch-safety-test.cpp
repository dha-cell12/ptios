#include "../shared/TLinkSupervisorWatch.h"
#include "supervisor-watch-wait-fixture.h"
#include <cstdio>
#include <initializer_list>
static unsigned interrupts=0,calls=0;
static int terminalError=0;
int main(){
    watchWaitProvider=[](pid_t pid,int *status,int flags)->pid_t{
        assert(pid==42&&flags==0);++calls;
        if(interrupts){--interrupts;errno=EINTR;return -1;}
        *status=7;errno=terminalError;return terminalError?-1:pid;
    };
    for(unsigned n=0;n<100000;++n){
        const uint64_t start=uint64_t(n)*3001;
        for(uint64_t age:{uint64_t(0),uint64_t(1),uint64_t(250),uint64_t(2999),uint64_t(3000),uint64_t(9000)}){
            assert(TLinkSupervisorWatch::remainingMs(start,start+age,3000)==(age>=3000?0:3000-age));
        }
        interrupts=n%8;calls=0;terminalError=0;
        const auto result=runWatcherWait(42);assert(result.pid==42&&result.status==7&&calls==n%8+1);
    }
    for(int error:{ECHILD,EIO}){
        interrupts=3;calls=0;terminalError=error;const auto result=runWatcherWait(42);
        assert(result.pid==-1&&calls==4&&errno==error);
    }
    assert(TLinkSupervisorWatch::remainingMs(UINT64_MAX,100,3000)==3000);
    assert(TLinkSupervisorWatch::remainingMs(100,UINT64_MAX,3000)==3000);
    assert(TLinkSupervisorWatch::remainingMs(100,99,3000)==3000);
    assert(TLinkSupervisorWatch::remainingMs(UINT64_MAX-1000,UINT64_MAX-1,3000)==2001);
    puts("Supervisor watcher core passed: 600k bounded continuous throttle plans, invalid/near-overflow clocks, 100k actual wait-block EINTR/reap lifecycles and terminal ECHILD/EIO without retry.");
}
