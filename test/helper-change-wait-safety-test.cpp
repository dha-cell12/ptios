#include "../shared/TLinkHelperRuntimeWait.h"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <thread>
#include <vector>
using TLinkHelperIO::Deadline;
using TLinkHelperIO::nowMs;
using C=TLinkHelperChangeWait::Code;
static void waitCount(TLinkHelperChangeWait &events,size_t count){
    const Deadline watchdog(nowMs(),5000);
    while(events.waiters()!=count){assert(watchdog.remaining(nowMs()));std::this_thread::yield();}
}
static void oracleCases(){
    TLinkHelperChangeWait events;
    for(uint64_t n=0;n<100000;++n){
        const uint64_t cursor=events.sequence();assert(cursor==n+1);
        // Publication between reading status/cursor and registration must return immediately.
        events.publish();const auto result=events.wait(cursor,Deadline(nowMs(),1000));
        assert(result.code==C::Changed&&result.sequence==n+2&&events.waiters()==0);
        const auto ahead=events.wait(n+3,Deadline(nowMs(),1000));assert(ahead.code==C::InvalidCursor);
    }
    const auto initial=events.wait(0,Deadline(nowMs(),1000));assert(initial.code==C::Changed&&initial.sequence==100001);
    const auto timeout=events.wait(events.sequence(),Deadline(0,1));assert(timeout.code==C::Timeout&&events.waiters()==0);
    events.stop();assert(events.wait(events.sequence(),Deadline(nowMs(),1000)).code==C::Stopped);
    const auto stopped=events.sequence();events.publish();assert(events.sequence()==stopped);
}
static void concurrentCases(){
    TLinkHelperChangeWait events;std::vector<std::thread> publishers;
    for(unsigned n=0;n<8;++n)publishers.emplace_back([&]{for(unsigned i=0;i<10000;++i)events.publish();});
    for(auto &thread:publishers)thread.join();assert(events.sequence()==80001);
    for(unsigned round=0;round<16;++round){
        const uint64_t before=events.sequence();std::atomic<unsigned> changed{0};std::vector<std::thread> readers;
        for(unsigned n=0;n<4;++n)readers.emplace_back([&]{const auto result=events.wait(before,Deadline(nowMs(),10000));assert(result.code==C::Changed&&result.sequence==before+1);++changed;});
        waitCount(events,4);assert(events.wait(before,Deadline(nowMs(),1000)).code==C::Busy);
        // An old cursor can still return immediately when the four blocking slots are full.
        assert(events.wait(before-1,Deadline(nowMs(),1000)).code==C::Changed);
        events.publish();for(auto &reader:readers)reader.join();assert(changed==4&&events.waiters()==0);
    }
    std::vector<std::thread> readers;std::atomic<unsigned> stopped{0};const uint64_t before=events.sequence();
    for(unsigned n=0;n<4;++n)readers.emplace_back([&]{assert(events.wait(before,Deadline(nowMs(),10000)).code==C::Stopped);++stopped;});
    waitCount(events,4);events.stop();for(auto &reader:readers)reader.join();assert(stopped==4&&events.waiters()==0);
    TLinkHelperChangeWait quiet;const auto timeout=quiet.wait(quiet.sequence(),Deadline(nowMs(),5));assert(timeout.code==C::Timeout&&quiet.waiters()==0);
}
static void cancellationCases(){
    TLinkHelperChangeWait events;const uint64_t sequence=events.sequence();
    for(unsigned n=0;n<100000;++n){
        TLinkHelperChangeWait::Cancellation cancellation;events.cancel(cancellation);
        assert(events.wait(sequence,Deadline(nowMs(),10000),&cancellation).code==C::Cancelled);
        assert(events.sequence()==sequence&&events.waiters()==0);
    }
    for(unsigned round=0;round<64;++round){
        const uint64_t before=events.sequence();TLinkHelperChangeWait::Cancellation cancellation;
        std::atomic<bool> otherDone{false};
        std::thread target([&]{const auto result=events.wait(before,Deadline(nowMs(),10000),&cancellation);assert(result.code==C::Cancelled&&result.sequence==before);});
        std::thread other([&]{assert(events.wait(before,Deadline(nowMs(),10000)).code==C::Changed);otherDone=true;});
        waitCount(events,2);events.cancel(cancellation);target.join();
        assert(!otherDone&&events.waiters()==1&&events.sequence()==before);
        // Repeated cancellation is harmless and a freed slot is reusable immediately.
        events.cancel(cancellation);assert(events.wait(before,Deadline(0,1)).code==C::Timeout);
        events.publish();other.join();assert(events.waiters()==0);
    }
    for(unsigned round=0;round<1000;++round){
        TLinkHelperChangeWait::Cancellation cancellation;const auto before=events.sequence();
        std::thread cancel([&]{events.cancel(cancellation);});
        assert(events.wait(before,Deadline(nowMs(),10000),&cancellation).code==C::Cancelled);
        cancel.join();assert(events.waiters()==0&&events.sequence()==before);
    }
}
static void recoveryCases(){
    // An independent elapsed-time oracle spans fast faults, full I/O timeouts,
    // oversleep and shorter caller budgets. No episode admits a fourth attempt.
    for(uint64_t n=0;n<100000;++n){
        TLinkHelperStatusRecovery recovery;const uint64_t start=1000+n;
        uint64_t now=start;unsigned attempts=0;const int caller=static_cast<int>(n%600)+1;
        for(unsigned step=0;step<5;++step){
            const int expected=attempts>=3||now>=start+1500?0:static_cast<int>(std::min<uint64_t>(std::min(caller,500),start+1500-now));
            const int budget=recovery.begin(now,caller);assert(budget==expected);if(!budget)break;++attempts;
            now+=n%701;
            const int expectedPause=attempts>=3||now>=start+1500?0:static_cast<int>(std::min<uint64_t>(100,start+1500-now));
            assert(recovery.retryDelay(now)==expectedPause);
            now+=static_cast<uint64_t>(expectedPause)+n%301;
        }
        assert(attempts<=3);recovery.reset();assert(recovery.remaining(now)==0&&!recovery.expired(now));
        assert(recovery.begin(now,500)==500); // Reset is explicit, never on a failed attempt.
    }
    TLinkHelperStatusRecovery bounded;assert(bounded.begin(1000,500)==500);
    assert(bounded.begin(1600,500)==500);assert(bounded.begin(2200,500)==300);
    assert(bounded.retryDelay(2200)==0&&bounded.begin(2300,500)==0);
    TLinkHelperStatusRecovery expiry;assert(expiry.begin(1000,1)==1);
    assert(expiry.retryDelay(2499)==1&&!expiry.expired(2499)&&expiry.expired(2500)&&expiry.begin(2500,500)==0);
    TLinkHelperStatusRecovery overflow;assert(overflow.begin(UINT64_MAX-2,500)==2);
    assert(overflow.remaining(UINT64_MAX)==0&&overflow.begin(UINT64_MAX,500)==0);
    TLinkHelperStatusRecovery stopped;assert(stopped.begin(1000,0)==0&&stopped.begin(1000,-1)==0);
    assert(stopped.begin(2000,500)==500);
    puts("Helper status recovery passed: 100k elapsed/budget/attempt oracle cases, three-attempt ceiling, fixed 1500-ms window, bounded backoff, caller shortening, reset and saturation.");
}
int main(){oracleCases();concurrentCases();cancellationCases();recoveryCases();puts("Helper change wait passed: 100k registration-gap/cursor cases, 80k concurrent publications, four-waiter cap, fan-out, stop/timeout, 100k pre-cancels, targeted wake isolation, 1000 cancel/registration races and zero final waiters.");}
