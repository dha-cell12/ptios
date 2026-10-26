#include "../shared/TLinkHelperChangeWait.h"
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
int main(){oracleCases();concurrentCases();cancellationCases();puts("Helper change wait passed: 100k registration-gap/cursor cases, 80k concurrent publications, four-waiter cap, fan-out, stop/timeout, 100k pre-cancels, targeted wake isolation, 1000 cancel/registration races and zero final waiters.");}
