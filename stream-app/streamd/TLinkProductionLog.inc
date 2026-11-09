#include "../../shared/TLinkConsoleLogBudget.h"
#include "../../shared/TLinkScriptLogPolicy.h"
#include "../../shared/TLinkConsoleLogVectorIO.h"
#include "../../shared/TLinkProductionLogBatch.h"
#include <sys/uio.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>
#include <atomic>
static std::shared_ptr<TLinkConsoleLogBudget> POCLogBudget(void) {
    static auto budget=std::make_shared<TLinkConsoleLogBudget>();return budget;
}
static std::atomic<uint64_t> sPOCLogFileFailures{0};
static void POCLogFileFailed(size_t count=1) {
    uint64_t value=sPOCLogFileFailures.load();
    while(value!=UINT64_MAX){
        const uint64_t next=count>UINT64_MAX-value?UINT64_MAX:value+count;
        if(sPOCLogFileFailures.compare_exchange_weak(value,next))break;
    }
}
POCLogStatistics POCLogGetStatistics(void) {
    const auto state=POCLogBudget()->snapshot();
    POCLogStatistics result{};result.accepted=state.accepted;result.dropped=state.dropped;
    result.truncated=state.truncated;result.systemFailures=state.systemFailures;result.fileFailures=sPOCLogFileFailures.load();result.pending=state.pending;return result;
}
static dispatch_queue_t POCLogQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.tlinkauto.streamd.log",DISPATCH_QUEUE_SERIAL);});return queue;
}
static size_t POCLogVectorLimit(void) {
    static const size_t limit=TLinkConsoleLogVectorIO::VectorLimit(::sysconf(_SC_IOV_MAX));return limit;
}
// Return a conservative count of records affected by a failure. A failed group
// and all later records are retired without replaying any acknowledged prefix.
static NSUInteger POCLogWriteRecords(NSArray<NSData *> *records,NSString *path) {
    const NSUInteger count=records.count;if(!count)return 0;
    if(count>TLinkConsoleLogMaxPending)return count;
    const int fd=::open(path.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_NONBLOCK,0644);
    if(fd<0)return count;
    NSUInteger failed=count;
    @try {
        if(::flock(fd,LOCK_EX|LOCK_NB)!=0)return count;
        struct stat info;
        if(::fstat(fd,&info)!=0||!S_ISREG(info.st_mode)||info.st_nlink!=1||info.st_size<0)return count;
        uint64_t size=(uint64_t)info.st_size;NSUInteger begin=0;
        while(begin<count){
            const auto plan=TLinkProductionLogBatch::Plan(size,TLinkScriptLogPolicy::FileBytes,count-begin,
                [records,begin](size_t index){return (size_t)records[begin+index].length;});
            if(!plan.count){failed=count-begin;break;}
            if(plan.reset){if(::ftruncate(fd,0)!=0){failed=count-begin;break;}size=0;}
            std::array<TLinkConsoleLogVectorIO::Span,TLinkConsoleLogMaxPending> spans{};
            for(size_t index=0;index<plan.count;++index){NSData *data=records[begin+index];spans[index]={(const uint8_t *)data.bytes,data.length};}
            const auto result=TLinkConsoleLogVectorIO::WriteAll(spans.data(),plan.count,POCLogVectorLimit(),
                [fd](const TLinkConsoleLogVectorIO::Span *parts,size_t length)->int64_t {
                    std::array<struct iovec,TLinkConsoleLogMaxPending> vectors{};
                    for(size_t index=0;index<length;++index){vectors[index].iov_base=const_cast<uint8_t *>(parts[index].bytes);vectors[index].iov_len=parts[index].length;}
                    return ::writev(fd,vectors.data(),(int)length);
                });
            if(result.error||result.zeroWrite||result.bytes!=plan.bytes){failed=count-begin;break;}
            size+=plan.bytes;begin+=plan.count;failed=0;
        }
    } @finally {if(::close(fd)!=0)failed=count;}
    return failed;
}
static BOOL POCLogWriteData(NSData *data,NSString *path) {
    if(!data||data.length>TLinkScriptLogPolicy::FileBytes)return NO;
    return POCLogWriteRecords(@[data],path)==0;
}
static NSData *POCPrepareLog(const char *msg,const std::shared_ptr<TLinkConsoleLogBudget> &budget) {
    @autoreleasepool {
        @try {try {NSLog(@"[poc-touch] %s",msg);}catch(...){budget->systemFailed();}}
        @catch(NSException *exception){(void)exception;budget->systemFailed();}
        @try {try {
            // Only the serial log owner uses this formatter.
            static NSDateFormatter *df;static dispatch_once_t once;
            dispatch_once(&once,^{df=[NSDateFormatter new];df.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];df.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS";});
            NSString *line=[NSString stringWithFormat:@"%@ %s\n",[df stringFromDate:[NSDate date]],msg];
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if(data&&data.length<=TLinkConsoleLogLineBytes)return data;
        }catch(...){}}
        @catch(NSException *exception){(void)exception;}
        POCLogFileFailed();return nil;
    }
}
struct POCLogEntry {
    // Permit dies after the payload, including retained/discarded queue blocks.
    std::shared_ptr<TLinkConsoleLogPermit> permit;
    NSData *bytes;
    POCLogEntry(std::shared_ptr<TLinkConsoleLogPermit> p,NSData *value):permit(std::move(p)),bytes(value){}
};
using POCLogRegistry=TLinkProductionLogBatch::Registry<POCLogEntry,TLinkConsoleLogMaxPending>;
static POCLogRegistry &POCLogPending(void){static POCLogRegistry pending;return pending;}
static void POCDrainLog(const std::shared_ptr<POCLogEntry> &anchor,const std::shared_ptr<TLinkConsoleLogBudget> &budget) {
    (void)anchor; // Each admitted GCD block retains its own payload and permit.
    @autoreleasepool {
        auto batch=POCLogPending().take();if(!batch.count)return;
        NSMutableArray<NSData *> *records=nil;
        @try {try {
            records=[NSMutableArray arrayWithCapacity:batch.count];
            if(!records){POCLogFileFailed(batch.count);return;}
            for(size_t index=0;index<batch.count;++index){
                NSData *data=POCPrepareLog((const char *)batch.entries[index]->bytes.bytes,budget);
                if(data)[records addObject:data];
            }
            if(records.count==1){if(!POCLogWriteData(records[0],POCLogFilePath()))POCLogFileFailed();}
            else if(records.count)POCLogFileFailed(POCLogWriteRecords(records,POCLogFilePath()));
        }catch(...){POCLogFileFailed(batch.count);}}
        @catch(NSException *exception){(void)exception;POCLogFileFailed(batch.count);}
    }
}
// Keep the temporary block/capture lifetime within this call so registration
// can distinguish an accepted copy from a discarded submission before unlock.
static void POCScheduleLog(dispatch_queue_t queue,std::shared_ptr<POCLogEntry> entry,std::shared_ptr<TLinkConsoleLogBudget> budget) {
    dispatch_async(queue,^{POCDrainLog(entry,budget);});
}
void POCLogf(const char *fmt, ...) {
    @autoreleasepool {
    std::shared_ptr<TLinkConsoleLogBudget> budget;
    @try {try {
        budget=POCLogBudget();
        auto permit=TLinkConsoleLogPermit::acquire(budget);if(!permit)return;
        char message[TLinkScriptLogPolicy::FormattedBytes]={};
        va_list args;va_start(args,fmt);const int count=vsnprintf(message,sizeof(message),fmt,args);va_end(args);
        if(count<0){budget->dropped();return;}
        NSData *bytes=[NSData dataWithBytes:message length:strlen(message)+1];
        dispatch_queue_t queue=POCLogQueue();if(!bytes||!queue){budget->dropped();return;}
        auto entry=std::make_shared<POCLogEntry>(std::move(permit),bytes);
        auto registration=POCLogPending().insert(entry);
        if(!registration){budget->dropped();return;}
        POCScheduleLog(queue,entry,budget);
        if(entry.use_count()>1)registration.commit();
        // Otherwise rollback weak metadata before the local payload is retired.
        budget->accepted((size_t)count>=sizeof(message));
    }catch(...){if(budget)budget->dropped();else POCLogFileFailed();}}
    @catch(NSException *exception){(void)exception;if(budget)budget->dropped();else POCLogFileFailed();}
    }
}
