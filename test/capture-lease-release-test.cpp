// Compile the actual POSIX release function against a Darwin-style lock model.
// NB upgrades retain SH on conflict; synchronize both decisions before close.
#include "../shared/TLinkCaptureLease.h"
#include <cassert>
#include <cstdio>
#include <condition_variable>
#include <mutex>
#include <thread>
#ifdef _WIN32
enum {LOCK_EX=2,LOCK_NB=4,LOCK_UN=8,AT_FDCWD=-100};
#else
#include <sys/file.h>
#include <fcntl.h>
#endif
struct Kernel {
    static std::mutex mutex;static std::condition_variable changed;
    static bool shared[3],closed[3],paired,sidecar,unlockFails;
    static int exclusive,arrivals,decisions,unlocks,closes,retired,proofReads;
    static void reset(bool pair,bool third=false){
        paired=pair;sidecar=true;unlockFails=false;exclusive=-1;
        arrivals=decisions=unlocks=closes=retired=proofReads=0;
        for(int i=0;i<3;++i){shared[i]=(i<2||third);closed[i]=false;}
    }
};
std::mutex Kernel::mutex;std::condition_variable Kernel::changed;
bool Kernel::shared[3]={},Kernel::closed[3]={},Kernel::paired=false,Kernel::sidecar=true,Kernel::unlockFails=false;
int Kernel::exclusive=-1,Kernel::arrivals=0,Kernel::decisions=0,Kernel::unlocks=0,Kernel::closes=0,Kernel::retired=0,Kernel::proofReads=0;
static int TLinkTestFlock(int fd,int operation){
    std::unique_lock<std::mutex> lock(Kernel::mutex);assert(fd>=0&&fd<3&&!Kernel::closed[fd]);
    if(operation==LOCK_UN){++Kernel::unlocks;if(Kernel::unlockFails)return -1;Kernel::shared[fd]=false;return 0;}
    assert(operation==(LOCK_EX|LOCK_NB));++Kernel::arrivals;Kernel::changed.notify_all();
    if(Kernel::paired)assert(Kernel::changed.wait_for(lock,std::chrono::seconds(10),[]{return Kernel::arrivals>=2;}));
    bool blocked=Kernel::exclusive>=0;
    for(int i=0;i<3;++i)if(i!=fd&&Kernel::shared[i])blocked=true;
    if(!blocked){Kernel::shared[fd]=false;Kernel::exclusive=fd;}
    // Force both old EX attempts to observe the other's retained SH before
    // either thread gets to close. The new UN -> EX path elects one cleaner.
    ++Kernel::decisions;Kernel::changed.notify_all();
    if(Kernel::paired)assert(Kernel::changed.wait_for(lock,std::chrono::seconds(10),[]{return Kernel::decisions>=2;}));
    return blocked?-1:0;
}
static int TLinkTestClose(int fd){
    std::lock_guard<std::mutex> lock(Kernel::mutex);assert(fd>=0&&fd<3&&!Kernel::closed[fd]);
    Kernel::shared[fd]=false;Kernel::closed[fd]=true;if(Kernel::exclusive==fd)Kernel::exclusive=-1;++Kernel::closes;return 0;
}
static TLinkCaptureFileID identity(){TLinkCaptureFileID id;id.device=1;id.inode=77;return id;}
struct ReleaseUnderTest {
    static std::string ownerPath(const std::string &marker){return marker+".owner.v1";}
    static bool readProof(int fd,TLinkCaptureFileID &id){
        std::lock_guard<std::mutex> lock(Kernel::mutex);assert(Kernel::exclusive==fd);++Kernel::proofReads;
        id=identity();return Kernel::sidecar;
    }
    static bool retireAt(int,const char *,const char *,const char *,int fd,TLinkCaptureFileID id){
        std::lock_guard<std::mutex> lock(Kernel::mutex);assert(Kernel::exclusive==fd&&TLinkCaptureSameID(id,identity())&&Kernel::sidecar);
        for(bool shared:Kernel::shared)assert(!shared);
        Kernel::sidecar=false;++Kernel::retired;return true;
    }
#define flock TLinkTestFlock
#define close TLinkTestClose
#include "CaptureReleaseUnderTest.inc"
#undef close
#undef flock
};
static void concurrentRelease(bool activeReader){
    Kernel::reset(true,activeReader);const auto id=identity();
    std::thread first([&]{ReleaseUnderTest::releaseMarker(0,"/fixture.png",id);});
    std::thread second([&]{ReleaseUnderTest::releaseMarker(1,"/fixture.png",id);});first.join();second.join();
    assert(Kernel::closes==2&&Kernel::closed[0]&&Kernel::closed[1]);
}
int main(){
    concurrentRelease(false);
    // A clean error exit also permits a negative probe of the previous release
    // body on Windows without invoking an interactive CRT assertion dialog.
    if(Kernel::sidecar||Kernel::retired!=1){fputs("Concurrent finished holders retained the owner sidecar.\n",stderr);return 1;}
    assert(Kernel::unlocks==2);
    concurrentRelease(true);assert(Kernel::sidecar&&Kernel::retired==0&&Kernel::shared[2]);
    Kernel::paired=false;ReleaseUnderTest::releaseMarker(2,"/fixture.png",identity());
    assert(!Kernel::sidecar&&Kernel::retired==1&&Kernel::closes==3);
    Kernel::reset(false);Kernel::shared[1]=false;auto wrong=identity();++wrong.inode;
    ReleaseUnderTest::releaseMarker(0,"/fixture.png",wrong);assert(Kernel::sidecar&&Kernel::retired==0&&Kernel::closes==1);
    Kernel::reset(false);Kernel::shared[1]=false;Kernel::unlockFails=true;
    ReleaseUnderTest::releaseMarker(0,"/fixture.png",identity());
    assert(Kernel::sidecar&&Kernel::arrivals==0&&Kernel::proofReads==0&&Kernel::closes==1);
    Kernel::reset(false);ReleaseUnderTest::releaseMarker(-1,"/fixture.png",identity());ReleaseUnderTest::releaseMarker(-2,"/fixture.png",identity());
    assert(Kernel::unlocks==0&&Kernel::arrivals==0&&Kernel::closes==0);
    puts("Capture release passed: deterministic retained-SH upgrade race, one exclusive cleaner, active-reader protection, proof mismatch, unlock failure and balanced closes.");
}
