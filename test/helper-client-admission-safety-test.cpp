#include "../shared/TLinkHelperClientAdmission.h"
#include <cassert>
#include <cstdio>
#include <set>
#include <thread>
#include <vector>
static std::mutex closeMutex;static std::set<int> closed;
static void closeFake(int fd){std::lock_guard<std::mutex> guard(closeMutex);assert(fd>=0&&closed.insert(fd).second);}
int main(){
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
