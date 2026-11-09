#include "TLinkHelperConsoleQueue.h"
#include "TLinkConsoleLogBatch.h"
#include "TLinkConsoleLogVectorIO.h"
#include <sys/uio.h>
#include <unistd.h>
struct TLinkHelperConsoleEntry {
    // Both admission charges retire after every prepared payload reference.
    std::shared_ptr<TLinkConsoleLogPermit> globalPermit,runPermit;
    TLinkHelperConsoleLine line;
    TLinkHelperConsoleEntry(std::shared_ptr<TLinkConsoleLogPermit> global,std::shared_ptr<TLinkConsoleLogPermit> run,TLinkHelperConsoleLine value)
        :globalPermit(std::move(global)),runPermit(std::move(run)),line(std::move(value)){}
};
using TLinkHelperConsoleState=TLinkHelperConsoleQueue::State<TLinkHelperConsoleEntry>;
static size_t TLinkHelperConsoleVectorCapacity(){
    static const size_t capacity=TLinkConsoleLogVectorIO::VectorLimit(sysconf(_SC_IOV_MAX));return capacity;
}
@interface TLinkHelperConsoleBatchSink:NSObject
- (BOOL)appendConsoleData:(NSData *)data toConsolePath:(NSString *)path;
- (BOOL)appendConsoleVectorBatch:(const TLinkHelperConsoleState::Batch &)batch begin:(size_t)begin count:(size_t)count toConsolePath:(NSString *)path;
- (uint64_t)writeConsoleBatch:(const TLinkHelperConsoleState::Batch &)batch toConsolePath:(NSString *)path;
@end
@implementation TLinkHelperConsoleBatchSink
- (BOOL)appendConsoleData:(NSData *)data toConsolePath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 ||
        ![data isKindOfClass:[NSData class]]) {
        return NO;
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkJSHelperMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [data writeToFile:path atomically:YES];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return NO;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @finally {
        [handle closeFile];
    }
    return YES;
}

- (BOOL)appendConsoleVectorBatch:(const TLinkHelperConsoleState::Batch &)batch begin:(size_t)begin count:(size_t)count toConsolePath:(NSString *)path {
    if(![path isKindOfClass:[NSString class]]||!path.length||begin>batch.count||!count||count>batch.count-begin||count>TLinkConsoleLogVectorIO::MaxVectors)return NO;
    std::array<TLinkConsoleLogVectorIO::Span,TLinkConsoleLogVectorIO::MaxVectors> spans{};
    for(size_t n=0;n<count;++n){
        NSData *data=batch.entries[begin+n]->line.data;
        spans[n]=TLinkConsoleLogVectorIO::Span((const uint8_t *)data.bytes,data.length);
    }
    size_t total=0;if(TLinkConsoleLogVectorIO::Validate(spans.data(),count,total))return NO;
    NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if([attrs[NSFileSize] unsignedLongLongValue]>kTLinkJSHelperMaxConsoleLogBytes)
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]){
        // Preserve the original atomic creation/replacement path. Only this
        // fallback materializes the bounded complete group.
        NSMutableData *joined=[NSMutableData dataWithCapacity:total];if(!joined)return NO;
        for(size_t n=0;n<count;++n)[joined appendBytes:spans[n].bytes length:spans[n].length];
        return [joined writeToFile:path atomically:YES];
    }
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];if(!handle)return NO;
    @try {
        [handle seekToEndOfFile];
        const int fd=handle.fileDescriptor;if(fd<0)return NO;
        const auto output=TLinkConsoleLogVectorIO::WriteAll(spans.data(),count,TLinkHelperConsoleVectorCapacity(),
            [fd](const TLinkConsoleLogVectorIO::Span *parts,size_t number)->int64_t {
                std::array<struct iovec,TLinkConsoleLogVectorIO::MaxVectors> vectors{};
                for(size_t n=0;n<number;++n){vectors[n].iov_base=const_cast<uint8_t *>(parts[n].bytes);vectors[n].iov_len=parts[n].length;}
                return ::writev(fd,vectors.data(),(int)number);
            });
        return !output.error&&!output.zeroWrite;
    } @finally {[handle closeFile];}
}

- (uint64_t)writeConsoleBatch:(const TLinkHelperConsoleState::Batch &)batch toConsolePath:(NSString *)path {
    if(![path isKindOfClass:[NSString class]]||!path.length)return TLinkConsoleLogBatchMask(0,batch.count);
    uint64_t failed=0;
    for(size_t begin=0;begin<batch.count;){
        size_t count=1;
        BOOL written=NO;
        @autoreleasepool {
        @try {try {
            const uint64_t bytes=[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
            // An already-oversize file uses the original one-line rotation path,
            // including its behavior when remove fails. Replan the next group.
            if(bytes<=kTLinkJSHelperMaxConsoleLogBytes)
                count=TLinkConsoleLogBatchCount(bytes,kTLinkJSHelperMaxConsoleLogBytes,batch.count-begin,[&batch,begin](size_t n){return batch.entries[begin+n]->line.data.length;});
            if(count>1)written=[self appendConsoleVectorBatch:batch begin:begin count:count toConsolePath:path];
            else written=[self appendConsoleData:batch.entries[begin]->line.data toConsolePath:path];
        }catch(...) {}} @catch(__unused NSException *exception) {}
        }
        // A failed group is not replayed: it may already have written bytes.
        if(!written)failed|=TLinkConsoleLogBatchMask(begin,count);
        begin+=count;
    }
    return failed;
}

@end
