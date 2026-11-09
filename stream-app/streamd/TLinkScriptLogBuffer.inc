#include "../../shared/TLinkScriptLogPolicy.h"
#include "../../shared/TLinkConsoleLogBudget.h"
#include <atomic>
static std::atomic<uint64_t> sTLinkScriptLogFormatFailures{0};
static void TLinkScriptLogFailed(void) {
    uint64_t value=sTLinkScriptLogFormatFailures.load();
    while(value!=UINT64_MAX&&!sTLinkScriptLogFormatFailures.compare_exchange_weak(value,value+1)){}
}
// The session monitor owns all operations. Held tail arrays retain their rows
// independently of later eviction/clear; they are outside the ring's quota.
@interface TLinkScriptLogBuffer : NSObject {
    NSMutableArray<NSString *> *_rows;
    TLinkScriptLogPolicy::Ring _ring;
    uint64_t _truncated;
}
@property(nonatomic,readonly) NSUInteger count;
@property(nonatomic,readonly) uint64_t truncated;
- (void)append:(NSString *)entry truncated:(BOOL)truncated;
- (NSArray<NSString *> *)tail:(NSUInteger)limit;
- (void)removeAllObjects;
@end
@implementation TLinkScriptLogBuffer
- (instancetype)init {
    self=[super init];
    if(self){_rows=[NSMutableArray arrayWithCapacity:TLinkScriptLogPolicy::Entries];if(!_rows)return nil;}
    return self;
}
- (NSUInteger)count {return _ring.count();}
- (uint64_t)truncated {return _truncated;}
- (void)append:(NSString *)entry truncated:(BOOL)truncated {
    const NSUInteger slot=_ring.next();
    if(slot<_rows.count)_rows[slot]=entry;else [_rows addObject:entry];
    _ring.appended();if(truncated)TLinkScriptLogPolicy::Increment(_truncated);
}
- (NSArray<NSString *> *)tail:(NSUInteger)limit {
    const NSUInteger count=_ring.tailCount(limit);
    NSMutableArray<NSString *> *rows=[NSMutableArray arrayWithCapacity:count];
    for(NSUInteger index=0;index<count;++index)[rows addObject:_rows[_ring.tailIndex(limit,index)]];
    return [rows copy];
}
- (void)removeAllObjects {[_rows removeAllObjects];_ring.clear();}
@end
static NSDictionary *TLinkScriptLogDiagnostics(TLinkScriptLogBuffer *logs) {
    const auto system=POCLogGetStatistics();
    return @{@"max_entries":@(TLinkScriptLogPolicy::Entries),@"max_message_utf16_units":@(TLinkScriptLogPolicy::MessageUnits),
        @"max_entry_utf16_units":@(TLinkScriptLogPolicy::MessageUnits+33),@"retained_entries":@(logs.count),@"truncated_total":@(logs.truncated),
        @"system_scope":@"process",@"system_accepted":@(system.accepted),@"system_dropped":@(system.dropped),
        @"system_truncated":@(system.truncated),@"process_format_failures":@(sTLinkScriptLogFormatFailures.load()),
        @"system_failures":@(system.systemFailures),@"file_failures":@(system.fileFailures),
        @"pending":@(system.pending),@"max_pending":@(TLinkConsoleLogMaxPending),@"max_formatted_bytes":@(TLinkScriptLogPolicy::FormattedBytes),
        @"max_debug_file_bytes":@(TLinkScriptLogPolicy::FileBytes)};
}
