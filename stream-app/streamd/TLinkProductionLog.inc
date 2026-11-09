#include "../../shared/TLinkConsoleLogBudget.h"
#include "../../shared/TLinkScriptLogPolicy.h"
#include "../../shared/TLinkJSFileIO.h"
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
static void POCLogFileFailed(void) {
    uint64_t value=sPOCLogFileFailures.load();
    while(value!=UINT64_MAX&&!sPOCLogFileFailures.compare_exchange_weak(value,value+1)){}
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
static BOOL POCLogWriteData(NSData *data,NSString *path) {
    if(!data||data.length>TLinkScriptLogPolicy::FileBytes)return NO;
    const int fd=::open(path.fileSystemRepresentation,O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_NONBLOCK,0644);
    if(fd<0)return NO;
    BOOL written=NO;
    @try {
        if(::flock(fd,LOCK_EX|LOCK_NB)!=0)return NO;
        struct stat info;
        if(::fstat(fd,&info)!=0||!S_ISREG(info.st_mode)||info.st_nlink!=1||info.st_size<0)return NO;
        if(TLinkScriptLogPolicy::NeedsReset((uint64_t)info.st_size,data.length)&&::ftruncate(fd,0)!=0)return NO;
        const auto result=TLinkJSFileIO::WriteAll((const uint8_t *)data.bytes,data.length,
            [fd](const uint8_t *bytes,size_t count)->int64_t{return ::write(fd,bytes,count);});
        written=!result.error&&!result.zeroWrite&&result.bytes==data.length;
    } @finally {if(::close(fd)!=0)written=NO;}
    return written;
}
static void POCEmitLog(const char *msg,const std::shared_ptr<TLinkConsoleLogBudget> &budget) {
    @autoreleasepool {
        @try {try {NSLog(@"[poc-touch] %s",msg);}catch(...){budget->systemFailed();}}
        @catch(NSException *exception){(void)exception;budget->systemFailed();}
        @try {try {
            // Only the serial log owner uses this formatter.
            static NSDateFormatter *df;static dispatch_once_t once;
            dispatch_once(&once,^{df=[NSDateFormatter new];df.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];df.dateFormat=@"yyyy-MM-dd HH:mm:ss.SSS";});
            NSString *line=[NSString stringWithFormat:@"%@ %s\n",[df stringFromDate:[NSDate date]],msg];
            NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
            if(!data||data.length>TLinkConsoleLogLineBytes||!POCLogWriteData(data,POCLogFilePath()))POCLogFileFailed();
        }catch(...){POCLogFileFailed();}}
        @catch(NSException *exception){(void)exception;POCLogFileFailed();}
    }
}
struct POCLogEntry {
    // Permit dies after the payload, including retained/discarded queue blocks.
    std::shared_ptr<TLinkConsoleLogPermit> permit;
    NSData *bytes;
    POCLogEntry(std::shared_ptr<TLinkConsoleLogPermit> p,NSData *value):permit(std::move(p)),bytes(value){}
};
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
        dispatch_async(queue,^{POCEmitLog((const char *)entry->bytes.bytes,budget);});
        budget->accepted((size_t)count>=sizeof(message));
    }catch(...){if(budget)budget->dropped();else POCLogFileFailed();}}
    @catch(NSException *exception){(void)exception;if(budget)budget->dropped();else POCLogFileFailed();}
    }
}
