#include "../shared/TLinkHelperClientAdmission.h"
#include "../shared/TLinkHelperCommandGate.h"
#include <cassert>
#include <cstdio>
#include <set>
#include <thread>
#include <vector>
static std::mutex closeMutex;static std::set<int> closed;
static void closeFake(int fd){std::lock_guard<std::mutex> guard(closeMutex);assert(fd>=0&&closed.insert(fd).second);}
using TLinkHelperIO::Deadline;
using TLinkHelperIO::nowMs;
static void waitGate(TLinkHelperCommandGate &gate,size_t count){
    const Deadline watchdog(nowMs(),5000);
    while(gate.waiters()!=count){assert(watchdog.remaining(nowMs()));std::this_thread::yield();}
}
static void gateCases(){
    TLinkHelperCommandGate gate;
    assert(!gate.acquire(Deadline(0,1)));
    {
        auto holder=gate.acquire(Deadline(nowMs(),10000));assert(holder);
        const Deadline expiry(nowMs(),5);assert(!gate.acquire(expiry)&&!expiry.remaining(nowMs()));
    }
    for(unsigned n=0;n<100000;++n){
        TLinkHelperCommandGate::Cancellation cancellation;gate.cancel(cancellation);
        assert(!gate.acquire(Deadline(nowMs(),10000),&cancellation));
        auto guard=gate.acquire(Deadline(nowMs(),10000));assert(guard&&gate.waiters()==0);
        assert(!gate.acquire(Deadline(0,1)));auto moved=std::move(guard);assert(moved&&!guard);
    }
    for(unsigned round=0;round<64;++round){
        auto holder=gate.acquire(Deadline(nowMs(),10000));assert(holder);
        TLinkHelperCommandGate::Cancellation cancellation;std::vector<std::thread> peers;
        std::thread target([&]{const Deadline deadline(nowMs(),10000);assert(!gate.acquire(deadline,&cancellation));assert(deadline.remaining(nowMs())&&gate.cancelled(cancellation));});
        unsigned count=0;
        for(unsigned n=0;n<3;++n)peers.emplace_back([&]{auto owner=gate.acquire(Deadline(nowMs(),10000));assert(owner);++count;});
        waitGate(gate,4);gate.cancel(cancellation);target.join();
        assert(gate.waiters()==3);gate.cancel(cancellation);holder.unlock();
        for(auto &peer:peers)peer.join();assert(count==3&&gate.waiters()==0);
    }
    for(unsigned n=0;n<1000;++n){
        auto holder=gate.acquire(Deadline(nowMs(),10000));assert(holder);
        TLinkHelperCommandGate::Cancellation cancellation;const Deadline deadline(nowMs(),10000);
        std::thread cancel([&]{gate.cancel(cancellation);});
        assert(!gate.acquire(deadline,&cancellation)&&deadline.remaining(nowMs()));cancel.join();
        assert(gate.cancelled(cancellation)&&gate.waiters()==0);
    }
    {
        TLinkHelperCommandGate::Cancellation cancellation;
        auto owner=gate.acquire(Deadline(nowMs(),10000),&cancellation);assert(owner);
        gate.cancel(cancellation);assert(owner&&gate.cancelled(cancellation)&&!gate.acquire(Deadline(0,1)));
        owner.unlock();auto next=gate.acquire(Deadline(nowMs(),10000));assert(next);
        assert(!gate.acquire(Deadline(nowMs(),10000),&cancellation)); // Cancel does not revoke/release the owner.
    }
    try{auto guard=gate.acquire(Deadline(nowMs(),10000));assert(guard);throw 1;}catch(int){}
    {auto guard=gate.acquire(Deadline(nowMs(),10000));assert(guard);}
    TLinkHelperCommandGate stopped;auto holder=stopped.acquire(Deadline(nowMs(),10000));assert(holder);
    std::vector<std::thread> waiters;
    for(unsigned n=0;n<4;++n)waiters.emplace_back([&]{const Deadline deadline(nowMs(),10000);assert(!stopped.acquire(deadline)&&deadline.remaining(nowMs()));});
    waitGate(stopped,4);stopped.stop();for(auto &waiter:waiters)waiter.join();
    assert(stopped.waiters()==0&&!stopped.acquire(Deadline(nowMs(),10000)));holder.unlock();assert(!stopped.acquire(Deadline(nowMs(),10000)));
    TLinkHelperCommandGate serial;std::vector<std::thread> workers;unsigned count=0;
    for(unsigned t=0;t<8;++t)workers.emplace_back([&]{for(unsigned n=0;n<10000;++n){auto owner=serial.acquire(Deadline(nowMs(),10000));assert(owner);++count;}});
    for(auto &worker:workers)worker.join();assert(count==80000&&serial.waiters()==0);
    puts("Helper command gate passed: 100k guard/pre-cancel lifecycles, targeted cancellation with three unaffected peers, 1000 registration races, move/unwind/stop and 80k serialized transactions.");
}
int main(){
    gateCases();
    TLinkHelperClientAdmission pool;std::vector<std::shared_ptr<TLinkHelperClientAdmission::Lease>> leases;
    for(int fd=0;fd<8;++fd){auto lease=pool.acquire(fd,100+fd,closeFake);assert(lease&&lease->acceptedAt()==uint64_t(100+fd));leases.push_back(lease);}
    assert(!pool.acquire(8,100,closeFake));closeFake(8);assert(pool.stats().active==8&&pool.stats().peak==8);
    auto shared=leases[0];leases.clear();assert(pool.stats().active==1);shared->finish();shared->finish();assert(pool.stats().active==0&&!shared->isOpen());shared.reset();
    for(int fd=100;fd<100100;++fd){auto lease=pool.acquire(fd,200,closeFake);assert(lease);auto copy=lease;
        if(fd%2){assert(lease->takeDescriptor()==fd);assert(copy->takeDescriptor()==-1);closeFake(fd);}
        lease.reset();assert(pool.stats().active==1);copy.reset();assert(pool.stats().active==0);
    }
    pool.stop();assert(!pool.isOpen()&&!pool.acquire(100101,0,closeFake));closeFake(100101);
    TLinkHelperClientAdmission zero(0);assert(!zero.acquire(100102,0,closeFake));closeFake(100102);
    std::shared_ptr<TLinkHelperClientAdmission::Lease> survivor;
    {TLinkHelperClientAdmission temporary;survivor=temporary.acquire(100103,1,closeFake);assert(survivor);}
    assert(survivor->isOpen());survivor.reset();
    TLinkHelperClientAdmission concurrent(4);std::atomic<int> next{200000};std::vector<std::thread> workers;
    for(unsigned t=0;t<8;++t)workers.emplace_back([&]{for(unsigned n=0;n<10000;++n){const int fd=next.fetch_add(1);auto lease=concurrent.acquire(fd,n,closeFake);
        if(!lease){closeFake(fd);continue;}if(n%7==0)std::this_thread::yield();if(n%2==0){const int owned=lease->takeDescriptor();assert(owned==fd);closeFake(owned);}if(n%3==0)lease->finish();}});
    for(auto &worker:workers)worker.join();const auto stats=concurrent.stats();assert(stats.active==0&&stats.peak<=4&&stats.admitted==stats.finished&&stats.admitted+stats.rejected==80000);
    assert(closed.size()==180012);
    puts("Helper client admission passed: exact eight-slot rejection, 100k shared/transfer lifecycles, owner-independent leases, idempotent finish and 8 x 10k concurrent admissions; every descriptor closed once.");
}
