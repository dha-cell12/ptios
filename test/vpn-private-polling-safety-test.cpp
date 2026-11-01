#include "../shared/TLinkVPNPrivatePolling.h"
#include "../shared/TLinkHelperSocketIO.h"
#include <cassert>
#include <cstdio>
#include <limits>
using namespace TLinkVPNPrivatePolling;
static void boundaries(){
    for(unsigned n=0;n<100000;++n){
        const uint64_t start=uint64_t(n)*100003;
        Window window(start,5);assert(window.remaining(start)==5000);
        assert(window.remaining(start+4999)==1);assert(!window.remaining(start+5000));
        assert(!window.remaining(start));
    }
    for(double value:{-std::numeric_limits<double>::infinity(),-10.0,0.0,4.0,5.0,std::numeric_limits<double>::quiet_NaN()}){
        Window window(100,value);assert(window.remaining(100)==5000);
    }
    for(double value:{30.0,31.0,std::numeric_limits<double>::infinity()}){Window window(100,value);assert(window.remaining(100)==30000);}
    Window fractional(100,5.125);assert(fractional.remaining(100)==5125);
    Window failed(UINT64_MAX,5),overflow(UINT64_MAX-4999,5),edge(UINT64_MAX-5000,5);
    assert(!failed.remaining(UINT64_MAX)&&!overflow.remaining(UINT64_MAX-4999));assert(edge.remaining(UINT64_MAX-5000)==5000);
    assert(!edge.remaining(UINT64_MAX));
    Window regression(100,5);assert(regression.remaining(200)==4900);assert(!regression.remaining(199));assert(!regression.remaining(201));
}
static void waits(){
    for(unsigned early=1;early<=100;++early){
        uint64_t tick=100;Window window(tick,5);unsigned calls=0,probes=0;
        while(waitNext(window,[&]{return tick;},[&](unsigned ms){assert(ms<=100);++calls;tick+=std::min(ms,early);return true;}))++probes;
        assert(tick==5100&&probes==49&&calls>=50); // Expiry has no last probe.
    }
    uint64_t tick=100;Window work(tick,5);unsigned probes=0;
    while(waitNext(work,[&]{return tick;},[&](unsigned ms){tick+=ms;return true;})){++probes;tick+=230;}
    assert(tick==5100&&probes==15); // Snapshot work consumes the same window.
    tick=100;Window action(tick,5);tick+=4900;
    assert(!waitNext(action,[&]{return tick;},[&](unsigned ms){assert(ms==100);tick+=ms;return true;}));
    tick=100;Window oversleep(tick,5);
    assert(!waitNext(oversleep,[&]{return tick;},[&](unsigned){tick+=6000;return true;}));
    tick=100;Window fault(tick,5);assert(!waitNext(fault,[&]{return tick;},[](unsigned){return false;}));
    Window regressed(100,5);tick=100;
    assert(!waitNext(regressed,[&]{return tick;},[&](unsigned){tick=99;return true;}));
    tick=100;Window finalPartial(tick,5);tick=5055;
    assert(!waitNext(finalPartial,[&]{return tick;},[&](unsigned ms){assert(ms==45);tick+=ms;return true;}));
    // A target discovered by an overlong probe is refused by the caller's check.
    tick=100;Window probe(tick,5);assert(waitNext(probe,[&]{return tick;},[&](unsigned ms){tick+=ms;return true;}));
    tick+=5000;assert(!probe.remaining(tick));
}
int main(){boundaries();waits();puts("Private VPN polling core passed: 100k windows, timeout/clock/overflow bounds, interrupted/early/failing waits, consumed action/probe time, oversleep and no post-expiry probe.");}
