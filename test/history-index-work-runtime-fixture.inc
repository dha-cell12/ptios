// A Foundation-backed message probe avoids private class-cluster initializer
// assumptions. Complete transaction parity below also uses real mutable arrays.
@interface HistoryTrimProbe : NSObject {
@public NSMutableArray *items;NSUInteger lastRemovals,rangeRemovals;NSRange removedRange;
}
@property(nonatomic,readonly) NSUInteger count;
- (void)addObject:(id)object;
- (id)objectAtIndexedSubscript:(NSUInteger)index;
- (id)lastObject;
- (void)removeLastObject;
- (void)removeObjectsInRange:(NSRange)range;
@end
@implementation HistoryTrimProbe
- (instancetype)init {self=[super init];if(self)items=[NSMutableArray array];return self;}
- (NSUInteger)count {return items.count;}
- (void)addObject:(id)object {[items addObject:object];}
- (id)objectAtIndexedSubscript:(NSUInteger)index {return items[index];}
- (id)lastObject {return items.lastObject;}
- (void)removeLastObject {++lastRemovals;[items removeLastObject];}
- (void)removeObjectsInRange:(NSRange)range {++rangeRemovals;removedRange=range;[items removeObjectsInRange:range];}
@end
static void historyIndexWorkTrims(){
    for(NSUInteger count:{NSUInteger(0),NSUInteger(1),NSUInteger(49),NSUInteger(50),NSUInteger(51),NSUInteger(128),NSUInteger(1000)}){
        @autoreleasepool {
            HistoryTrimProbe *old=[HistoryTrimProbe new],*now=[HistoryTrimProbe new];
            for(NSUInteger n=0;n<count;++n){NSDictionary *record=@{@"run_id":[NSString stringWithFormat:@"trim-%lu",(unsigned long)n]};[old addObject:record];[now addObject:record];}
            NSArray *expected=BeforeIndexWork::TLinkRunHistoryTrim((NSMutableArray *)old),*actual=Current::TLinkRunHistoryTrim((NSMutableArray *)now);
            assert([expected isEqual:actual]&&[old->items isEqual:now->items]&&now.count==MIN(count,NSUInteger(50)));
            const NSUInteger removed=count>50?count-50:0;
            assert(old->lastRemovals==removed&&!old->rangeRemovals&&!now->lastRemovals&&now->rangeRemovals==(removed?1U:0U));
            if(removed)assert(NSEqualRanges(now->removedRange,NSMakeRange(50,removed)));
            for(NSUInteger n=0;n<actual.count;++n)assert(actual[n]==expected[n]);
        }
    }
}
static void historyIndexWorkReaders(){
    NSMutableArray *source=[NSMutableArray array];
    for(unsigned n=0;n<32;++n)[source addObject:@{@"run_id":[NSString stringWithFormat:@"read-%u",n],@"state":@"finished",@"extra":@{@"text":@"ảnh\0尾"}}];
    assert(Current::TLinkRunHistoryWriteIndex(source));
    for(bool modern:{false,true}){
        for(bool immutable:{false,true}){
            NSMutableArray *held=nil;historyDecodeImmutable=immutable;historyCaptureDecode=true;
            const int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0);
            @autoreleasepool {
                TLinkAXFixtureResetOwners();historyIndexWorkOwners=true;
                held=modern?Current::TLinkRunHistoryReadCheckedIndex(@"probe"):BeforeIndexWork::TLinkRunHistoryReadCheckedIndex(@"probe");
                assert([held isEqual:source]&&[held isKindOfClass:[NSMutableArray class]]);
                assert((held==historyIndexDecodedRecords)==(modern&&!immutable));
                assert(TLinkAXFixtureCreatedOwners()==33);
                assert(modern?(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixturePeakOwners()==2):(TLinkAXFixtureLiveOwners()==33&&TLinkAXFixturePeakOwners()==33));
                historyIndexWorkOwners=false;
            }
            Current::TLinkRunHistoryReleaseFileLock(fd);
            assert([held isEqual:source]&&TLinkAXFixtureLiveOwners()==0&&historyIndexFds.empty());
            [held addObject:@{@"run_id":@"held-after-pool"}];assert(held.count==33);
            historyIndexDecodedRecords=nil;historyCaptureDecode=false;historyDecodeImmutable=false;
        }
    }
}
static void historyIndexWorkRecovery(){
    NSMutableArray *runs=[NSMutableArray array];
    for(unsigned n=0;n<32;++n){
        NSString *runId=[NSString stringWithFormat:@"recovery-%u",n];
        [runs addObject:@{@"schema":n==31?@"invalid":Current::TLinkRunHistorySchemaV1,@"run_id":runId,
            @"record_path":[Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:[runId stringByAppendingString:@".json"]],@"failure_evidence":@{}}];
    }
    for(bool modern:{false,true}){
        Current::sTLinkRunHistoryRecovered=NO;BeforeIndexWork::sTLinkRunHistoryRecovered=NO;
        const int fd=Current::TLinkRunHistoryAcquireFileLock();assert(fd>=0);
        const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;
        @autoreleasepool {
            TLinkAXFixtureResetOwners();historyRecoveryWorkOwners=true;
            const BOOL ok=modern?Current::TLinkRunHistoryRecover(runs,@"probe"):BeforeIndexWork::TLinkRunHistoryRecover(runs,@"probe");
            assert(!ok&&TLinkAXFixtureCreatedOwners()==32);
            assert(modern?(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixturePeakOwners()==1):(TLinkAXFixtureLiveOwners()==32&&TLinkAXFixturePeakOwners()==32));
            historyRecoveryWorkOwners=false;
        }
        Current::TLinkRunHistoryReleaseFileLock(fd);
        assert(TLinkAXFixtureLiveOwners()==0&&historyWriteAttempts.count==writes&&historyEvents.count==events);
    }
}
static void historyIndexWorkCases(){
    puts("History index work Foundation: actual/preceding decoded graph, checked validation/recovery and ordered bulk retention");fflush(stdout);
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"index-work-now"];
    BeforeIndexWork::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"index-work-before"];
    Current::sTLinkRunHistoryRecovered=NO;BeforeIndexWork::sTLinkRunHistoryRecovered=NO;
    historyIndexWorkTrims();
    NSDictionary *old=historyWorkFlow(false,true),*now=historyWorkFlow(true);
    assert([old isEqual:now]);
    // Use one private root for exact path and real held-lock comparisons.
    BeforeIndexWork::fixtureRoot=Current::fixtureRoot;
    historyIndexWorkReaders();historyIndexWorkRecovery();
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    assert(historyLocks.empty()&&historyIndexFds.empty()&&historyRecoveryFds.empty()&&TLinkAXFixtureLiveOwners()==0);
    puts("History index work passed: complete preceding 64-transaction/index/event/status parity; decoded mutable identity and immutable fallback, held graph mutation, reader MRC peak 2 versus 33, invalid-recovery peak 1 versus 32, exact retirement order/object identity and one bulk erase versus up to 950 removeLast calls. Foundation allocation/RSS/device gains remain unqualified.");
}
