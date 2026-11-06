#include "../shared/TLinkAXSnapshotWindow.h"
#include "../shared/TLinkAXSnapshotOutput.h"
#include "../shared/TLinkAXWireOutput.h"
#include "../shared/TLinkAXJSONQuota.h"
#include "../shared/TLinkAXJSONStop.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
#include <initializer_list>
static bool near(double left,double right){return std::fabs(left-right)<1e-8;}
#include "ax-output-safety-fixture.inc"
#include "ax-wire-safety-fixture.inc"
#include "ax-json-quota-safety-fixture.inc"
#include "ax-json-stop-safety-fixture.inc"
int main(){
    outputBudgetCases();wireSizeCases();jsonQuotaCases();jsonStopPolicyCases();
    for(unsigned n=0;n<100000;++n){
        const unsigned milliseconds=100+n%2901;
        const uint64_t start=1000000ULL+static_cast<uint64_t>(n)*10000000ULL;
        const uint64_t span=static_cast<uint64_t>(milliseconds)*1000000ULL;
        TLinkAXSnapshotWindow window(start,milliseconds);
        assert(near(window.remainingSeconds(start,10),milliseconds/1000.0));
        assert(near(window.remainingSeconds(start+span/2,.01),.01));
        assert(window.remainingSeconds(start+span-1,1)>0);
        assert(window.remainingSeconds(start+span,1)==0);
        assert(window.remainingSeconds(start+span+9000000ULL,1)==0);
        assert(near(window.elapsedMilliseconds(start+span+9000000ULL),milliseconds+9.0));
    }
    TLinkAXSnapshotWindow zero(0,100);assert(near(zero.remainingSeconds(0,.5),.1));
    for(unsigned invalid:{0U,99U,3001U,UINT32_MAX}){
        TLinkAXSnapshotWindow window(100,invalid);assert(window.remainingSeconds(100,1)==0&&window.elapsedMilliseconds(100)==0);
    }
    TLinkAXSnapshotWindow overflow(UINT64_MAX-99999999ULL,100);
    assert(overflow.remainingSeconds(UINT64_MAX-99999999ULL,1)==0&&overflow.elapsedMilliseconds(UINT64_MAX)==0);
    TLinkAXSnapshotWindow sentinel(UINT64_MAX,100);assert(sentinel.remainingSeconds(UINT64_MAX,1)==0&&sentinel.elapsedMilliseconds(0)==0);
    TLinkAXSnapshotWindow regression(1000000000ULL,1500);
    assert(near(regression.remainingSeconds(1007000000ULL,2),1.493));
    assert(regression.remainingSeconds(1,1)==0&&regression.remainingSeconds(1008000000ULL,1)==0);
    assert(near(regression.elapsedMilliseconds(1008000000ULL),7));
    TLinkAXSnapshotWindow failedClock(0,100);assert(failedClock.remainingSeconds(UINT64_MAX,1)==0&&failedClock.elapsedMilliseconds(UINT64_MAX)==0);
    TLinkAXSnapshotWindow caps(100,3000);
    assert(caps.remainingSeconds(100,0)==0&&caps.remainingSeconds(100,-1)==0);
    assert(caps.remainingSeconds(100,std::numeric_limits<double>::quiet_NaN())==0);
    assert(near(caps.remainingSeconds(100,std::numeric_limits<double>::infinity()),3));
    TLinkAXSnapshotWindow largeElapsed(0,100);
    const double elapsed=largeElapsed.elapsedMilliseconds(UINT64_MAX-1);
    assert(std::isfinite(elapsed)&&elapsed>0&&elapsed<static_cast<double>(INT64_MAX));
    std::puts("AX snapshot window passed: 100k timeout/remaining/elapsed cases, exact deadline, overshoot, invalid ranges/clock/overflow/regression, stable nonnegative duration and finite output conversion.");
}
