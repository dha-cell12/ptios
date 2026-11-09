#define main HelperSyncOracleMain
#include "helper-console-runtime-test.mm"
#undef main
#include <sys/uio.h>
#include <map>
#include <thread>
#include <atomic>
static unsigned asyncMode=0,barrierFault=0,enqueues=0,vectors=0,joined=0;
static size_t vectorCap=64,shortWrite=SIZE_MAX;
static NSMutableArray *deferred;
static std::map<int,NSString *> descriptorPaths;
static std::atomic<bool> holdSystem{false};
static dispatch_semaphore_t systemEntered,systemRelease;
static dispatch_block_t sinkReentry;
@interface HelperOwnedHandle(AsyncDescriptor)
- (int)fileDescriptor;
@end
@implementation HelperOwnedHandle(AsyncDescriptor)
- (int)fileDescriptor{return faultFor(self.path)&&ioFault==10?-1:self.descriptor;}
@end
static HelperOwnedHandle *HelperAsyncOpen(NSString *path){HelperOwnedHandle *handle=HelperOpen(path);if(handle)descriptorPaths[handle.descriptor]=path;return handle;}
static int64_t HelperAsyncVectors(int fd,const struct iovec *parts,int count){
    ++vectors;const bool fail=faultFor(descriptorPaths[fd]);
    if(fail&&ioFault==2)[NSException raise:@"HelperAsync" format:@"writev"];
    if(fail&&ioFault==3)throw std::runtime_error("writev");
    if(shortWrite==SIZE_MAX&&!(fail&&(ioFault==4||ioFault==5)))return ::writev(fd,parts,count);
    size_t left=fail&&(ioFault==4||ioFault==5)?3:shortWrite;int64_t wrote=0;
    for(int n=0;n<count&&left;++n){const size_t amount=std::min(left,parts[n].iov_len);const ssize_t value=::write(fd,parts[n].iov_base,amount);assert(value>0);wrote+=value;left-=size_t(value);if(size_t(value)<amount)break;}
    if(fail&&ioFault==4)[NSException raise:@"HelperAsync" format:@"partial"];
    if(fail&&ioFault==5)throw std::runtime_error("partial");
    return wrote;
}
static NSMutableData *HelperAsyncJoined(size_t amount){++joined;assert(amount<=1024*1024);return [NSMutableData dataWithCapacity:amount];}
static size_t HelperAsyncVectorLimit(size_t host){return std::min(host,vectorCap);}
static void HelperAsyncEnqueue(dispatch_queue_t queue,dispatch_block_t block){
    ++enqueues;
    if(asyncMode==1)[NSException raise:@"HelperAsync" format:@"enqueue"];
    if(asyncMode==2)throw std::runtime_error("enqueue");
    if(asyncMode==3)return;
    if(asyncMode>=4){[deferred addObject:[block copy]];if(asyncMode==5)[NSException raise:@"HelperAsync" format:@"after copy"];if(asyncMode==6)throw std::runtime_error("after copy");return;}
    dispatch_async(queue,block);
}
static void HelperAsyncBarrier(dispatch_queue_t queue,dispatch_block_t block){
    const unsigned fault=barrierFault;barrierFault=0;
    if(fault==1)[NSException raise:@"HelperAsync" format:@"barrier"];
    if(fault==2)throw std::runtime_error("barrier");
    dispatch_sync(queue,block);
}
static void HelperAsyncSystem(NSString *format,NSString *run,NSString *level,NSString *message){
    if(holdSystem){dispatch_semaphore_signal(systemEntered);assert(dispatch_semaphore_wait(systemRelease,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
    if(sinkReentry){dispatch_block_t block=sinkReentry;sinkReentry=nil;block();}
    HelperSystem(format,run,level,message);
}
#include "HelperConsoleAsyncUnderTest.inc"
#include "HelperConsoleAsyncHook.inc"
using ConsoleOwner=TLinkHelperConsoleAsync::Owner;
static void waitFor(dispatch_semaphore_t value){assert(dispatch_semaphore_wait(value,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);}
@interface HelperAsyncBlockedDescription:NSObject
@property(nonatomic,strong) dispatch_semaphore_t entered;
@property(nonatomic,strong) dispatch_semaphore_t releaseValue;
@end
@implementation HelperAsyncBlockedDescription
- (NSString *)description{dispatch_semaphore_signal(_entered);waitFor(_releaseValue);return @"late formatter";}
@end
class QueueHold {
    dispatch_semaphore_t entered_=dispatch_semaphore_create(0),release_=dispatch_semaphore_create(0);
    bool held_=true;
public:
    QueueHold(){dispatch_semaphore_t entered=entered_,release=release_;dispatch_async(TLinkHelperConsoleAsync::Queue(),^{dispatch_semaphore_signal(entered);waitFor(release);});waitFor(entered_);}
    void release(){if(held_){held_=false;dispatch_semaphore_signal(release_);}}
    ~QueueHold(){release();}
};
static void resetAsync(size_t initial){
    reset(initial);asyncMode=barrierFault=enqueues=vectors=joined=0;vectorCap=64;shortWrite=SIZE_MAX;
    descriptorPaths.clear();assert(deferred.count==0);sinkReentry=nil;
    assert(TLinkHelperConsoleAsync::GlobalBudget()->snapshot().pending==0);
}
static void parityAsyncCases(){
    for(size_t initial:{SIZE_MAX,size_t(0),size_t(524288),size_t(524289)}){
        for(size_t cap:{size_t(1),size_t(2),size_t(64)}){
            @autoreleasepool {
                resetAsync(initial);CurrentHelperConsole *before=[CurrentHelperConsole new];
                for(unsigned n=0;n<64;++n)TLinkHelperConsoleEmit(before,@"run",@"log",[NSString stringWithFormat:@"message %u ảnh 😀",n],runPath,latestPath);
                NSDictionary *expected=trace();const unsigned oldOpens=opens;
                resetAsync(initial);vectorCap=cap;auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);assert(owner);
                {
                    QueueHold held;
                    __attribute__((objc_precise_lifetime)) CurrentHelperConsole *fallback=[CurrentHelperConsole new];JSContext *ctx=[JSContext new];InstallAsync(ctx,fallback,owner,@"run",runPath,latestPath);
                    for(unsigned n=0;n<64;++n)[ctx[@"_tlinkautoLog"] callWithArguments:@[@"log",[NSString stringWithFormat:@"message %u ảnh 😀",n]]];
                    assert(!ctx.exception&&owner->stats().pending==64&&enqueues==1&&systemRows.count==0&&opens==0);
                    held.release();assert(owner->close());
                }
                NSDictionary *actual=trace();if(![expected isEqual:actual])fprintf(stderr,"Helper async parity: initial=%zu cap=%zu expected=%.2048s actual=%.2048s\n",initial,cap,expected.description.UTF8String,actual.description.UTF8String);
                assert([expected isEqual:actual]);const auto stats=owner->stats();assert(stats.accepted==64&&stats.pending==0&&stats.dropped==0&&stats.writeFailures==0&&stats.systemFailures==0);
                if(initial==0){assert(oldOpens==128&&opens==2&&vectors==2*((64+HelperAsyncVectorLimit(TLinkConsoleLogVectorIO::VectorLimit(sysconf(_SC_IOV_MAX)))-1)/HelperAsyncVectorLimit(TLinkConsoleLogVectorIO::VectorLimit(sysconf(_SC_IOV_MAX))))&&joined==0);}
                NSDictionary *diagnostics=TLinkHelperConsoleAsync::Diagnostics(owner);assert([diagnostics[@"accepted"] unsignedIntValue]==64);
            }
        }
    }
}
static void admissionAndTicketCases(){
    resetAsync(0);auto first=TLinkHelperConsoleAsync::Create(runPath,latestPath),second=TLinkHelperConsoleAsync::Create(runPath,latestPath);assert(first&&second);
    {QueueHold held;
        for(unsigned n=0;n<32;++n){first->submit(@"one",@"log",@"one");second->submit(@"two",@"log",@"two");}
        second->submit(@"two",@"log",@"refused");assert(encodes==64&&enqueues==2&&first->stats().pending==32&&second->stats().pending==32&&second->stats().dropped==1);
        held.release();assert(first->close()&&second->close());
    }
    const unsigned encoded=encodes;first->submit(@"old",@"log",@"late");assert(encodes==encoded&&first->stats().dropped==1&&first->stats().pending==0);
    std::shared_ptr<ConsoleOwner> unavailable;NSDictionary *fallback=TLinkHelperConsoleAsync::Diagnostics(unavailable);assert([fallback[@"mode"] isEqual:@"sync_bounded_fallback_v1"]);
    for(unsigned mode=1;mode<=6;++mode){
        resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);asyncMode=mode;
        @autoreleasepool{owner->submit(@"run",@"log",@"first");}
        asyncMode=0;
        if(mode==4){assert(owner->stats().pending==1);assert(owner->close());assert(systemRows.count==1);}
        else {assert(owner->stats().pending==0&&owner->stats().dropped==1);owner->submit(@"run",@"log",@"recovered");assert(owner->close());assert(systemRows.count==1);}
        @autoreleasepool{
            for(id value in [deferred copy]){dispatch_block_t block=(dispatch_block_t)value;block();}
            [deferred removeAllObjects];
        }
        assert(owner->stats().pending==0&&systemRows.count==1&&descriptors.empty());
    }
    resetAsync(0);asyncMode=4;auto abandoned=TLinkHelperConsoleAsync::Create(runPath,latestPath);
    for(unsigned n=0;n<8;++n){abandoned->submit(@"run",@"log",@"abandoned");}assert(abandoned->stats().pending==8);
    @autoreleasepool{[deferred removeAllObjects];}asyncMode=0;
    assert(abandoned->stats().pending==0&&abandoned->stats().dropped==8&&systemRows.count==0);assert(abandoned->close());
}
static void asyncFaultCases(){
    for(unsigned fault=1;fault<=5;++fault){
        resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);encodeFault=fault;
        {QueueHold held;owner->submit(@"run",@"log",@"codec fault");held.release();assert(owner->close());}
        const auto stats=owner->stats();assert(stats.accepted==1&&stats.writeFailures==1&&stats.pending==0&&systemRows.count==1&&opens==0);
    }
    for(unsigned fault=1;fault<=2;++fault){
        resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);dateFault=fault;
        {QueueHold held;owner->submit(@"run",@"log",@"date fault");held.release();assert(owner->close());}
        assert(owner->stats().writeFailures==1&&systemRows.count==1&&opens==0);
        resetAsync(0);auto refused=TLinkHelperConsoleAsync::Create(runPath,latestPath);HelperBadDescription *input=[HelperBadDescription new];input.fault=fault;
        refused->submit(@"run",@"log",(NSString *)input);assert(refused->close());
        assert(refused->stats().accepted==0&&refused->stats().dropped==1&&refused->stats().pending==0&&enqueues==0&&systemRows.count==0);
    }
    resetAsync(0);shortWrite=3;auto partial=TLinkHelperConsoleAsync::Create(runPath,latestPath);
    {QueueHold held;for(unsigned n=0;n<8;++n){partial->submit(@"run",@"log",@"short vector");}held.release();assert(partial->close());}
    assert(partial->stats().writeFailures==0&&partial->stats().pending==0&&vectors>2&&[trace()[@"run"] isEqual:trace()[@"latest"]]);
    for(unsigned fault=1;fault<=10;++fault){
        resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);faultPath=runPath;ioFault=fault;
        {QueueHold held;for(unsigned n=0;n<8;++n)owner->submit(@"run",@"log",@"fault");held.release();assert(owner->close());}
        auto stats=owner->stats();if(stats.pending||stats.writeFailures!=8)fprintf(stderr,"Helper async fault=%u pending=%zu failed=%llu\n",fault,stats.pending,(unsigned long long)stats.writeFailures);
        assert(stats.pending==0&&stats.writeFailures==8&&systemRows.count==8&&[trace()[@"latest"] length]>0);
        if(fault==4||fault==5)assert([trace()[@"run"] length]==3);
    }
    for(unsigned fault=1;fault<=2;++fault){
        resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);systemFault=fault;
        {QueueHold held;for(unsigned n=0;n<8;++n)owner->submit(@"run",@"log",@"system fault");held.release();assert(owner->close());}
        assert(owner->stats().systemFailures==8&&owner->stats().writeFailures==0&&[trace()[@"run"] length]>0&&[trace()[@"latest"] length]>0);
        resetAsync(0);auto failedBarrier=TLinkHelperConsoleAsync::Create(runPath,latestPath);asyncMode=4;failedBarrier->submit(@"run",@"log",@"barrier fallback");asyncMode=0;barrierFault=fault;
        assert(failedBarrier->close()&&failedBarrier->stats().pending==0&&systemRows.count==1);
        @autoreleasepool{[deferred removeAllObjects];}
    }
    resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);
    {QueueHold held;owner->submit(@"run",@"log",[@"x" stringByPaddingToLength:4097 withString:@"x" startingAtIndex:0]);held.release();assert(owner->close());}
    assert(owner->stats().truncated==1&&owner->stats().pending==0);
}
static void blockedAndScopeCases(NSString *root){
    resetAsync(0);auto owner=TLinkHelperConsoleAsync::Create(runPath,latestPath);
    systemEntered=dispatch_semaphore_create(0);systemRelease=dispatch_semaphore_create(0);holdSystem=true;
    owner->submit(@"run",@"log",@"held");waitFor(systemEntered);
    std::atomic<bool> closed{false};std::thread closer([&]{assert(owner->close());closed=true;});
    assert(!closed.load());holdSystem=false;dispatch_semaphore_signal(systemRelease);closer.join();assert(closed&&owner->stats().pending==0);
    resetAsync(0);auto preparing=TLinkHelperConsoleAsync::Create(runPath,latestPath);HelperAsyncBlockedDescription *input=[HelperAsyncBlockedDescription new];
    input.entered=dispatch_semaphore_create(0);input.releaseValue=dispatch_semaphore_create(0);
    std::thread formatter([preparing,input]{@autoreleasepool{preparing->submit(@"run",@"log",(NSString *)input);}});
    waitFor(input.entered);assert(preparing->close()&&preparing->stats().pending==1&&systemRows.count==0);
    dispatch_semaphore_signal(input.releaseValue);formatter.join();assert(preparing->stats().pending==0&&preparing->stats().accepted==0&&preparing->stats().dropped==1&&systemRows.count==0);
    resetAsync(0);auto reentrant=TLinkHelperConsoleAsync::Create(runPath,latestPath);auto refused=std::make_shared<std::atomic<bool>>(false);
    sinkReentry=^{*refused=!reentrant->close();reentrant->submit(@"late",@"log",@"reentry");};
    reentrant->submit(@"run",@"log",@"reentry source");assert(reentrant->close());assert(refused->load()&&reentrant->stats().dropped==1&&reentrant->stats().pending==0);
    NSString *directory=[root stringByAppendingPathComponent:@"_logs"];assert([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    for(unsigned kind=1;kind<=2;++kind){
        NSString *path=[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"00000000-0000-4000-8000-%012u-helper.log",kind]];
        assert([[NSData data] writeToFile:path atomically:YES]);bool caught=false;
        @try {try {
            TLinkConsoleLogRetention::Completion completion(path.fileSystemRepresentation);auto scoped=TLinkHelperConsoleAsync::Create(path,latestPath);TLinkHelperConsoleAsync::CloseScope close(scoped,&completion);
            scoped->submit(@"run",@"log",@"before unwind");
            if(kind==1)[NSException raise:@"HelperAsync" format:@"scope"];
            throw std::runtime_error("scope");
        }catch(const std::runtime_error &){caught=true;}} @catch(NSException *exception){(void)exception;caught=true;}
        TLinkConsoleLogRetention::Detail::FD file(::open(path.fileSystemRepresentation,O_RDONLY));struct stat info;assert(caught&&file.get()>=0&&::fstat(file.get(),&info)==0&&info.st_size>0&&TLinkConsoleLogRetention::Detail::Marked(file.get(),info));
    }
}
int main(int argc,char **argv){
    assert(HelperSyncOracleMain(argc,argv)==0);
    @autoreleasepool{
        deferred=[NSMutableArray array];
        puts("Helper async Foundation: actual JS hook, queued owner and production file vectors versus synchronous oracle");parityAsyncCases();
        puts("Helper async Foundation: process admission, enqueue discard/unwind and stale tickets");admissionAndTicketCases();
        puts("Helper async Foundation: vector/sink faults, barrier fallback and terminal ownership");asyncFaultCases();blockedAndScopeCases([NSString stringWithUTF8String:argv[1]]);
        assert(TLinkHelperConsoleAsync::GlobalBudget()->snapshot().pending==0&&descriptors.empty()&&opens==closes&&fallbackCloses==0);
        puts("Helper async passed: 12 frozen 64-record JS/file/system comparisons, 128-to-2 normal opens/closes with host-clipped writev, process-wide64 admission, discard/unwind/stale tickets, sink/vector/close faults without replay, blocked drain, reentry and unwind-before-completion proof. Actual daemon/device performance remains unqualified.");
    }return 0;
}
