// Complete preceding C03ad history and current history share controlled clocks,
// IO adapters and explicit MRC witnesses; actual Foundation codecs stay real.
@interface HistoryTailText : NSString {
@public NSString *backing;NSUInteger searches,pieces,splitPieces;
}
- (instancetype)initWithText:(NSString *)text;
@end
@implementation HistoryTailText
- (instancetype)initWithText:(NSString *)text {self=[super init];if(self)backing=[text copy];return self;}
- (NSUInteger)length {return backing.length;}
- (unichar)characterAtIndex:(NSUInteger)index {return [backing characterAtIndex:index];}
- (void)getCharacters:(unichar *)buffer range:(NSRange)range {[backing getCharacters:buffer range:range];}
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set options:(NSStringCompareOptions)options range:(NSRange)range {
    assert(options==NSBackwardsSearch&&range.location==0&&range.length<=backing.length);++searches;
    return [backing rangeOfCharacterFromSet:set options:options range:range];
}
- (NSString *)substringWithRange:(NSRange)range {++pieces;return [backing substringWithRange:range];}
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set {
    NSArray *result=[backing componentsSeparatedByCharactersInSet:set];splitPieces+=result.count;return result;
}
@end
static void historyWorkRequire(bool condition,unsigned line){
    if(!condition)fprintf(stderr,"History work failure line %u: created=%llu live=%llu peak=%llu drops=%llu locks=%zu writes=%lu readFault=%u writeFault=%u\n",line,
        (unsigned long long)TLinkAXFixtureCreatedOwners(),(unsigned long long)TLinkAXFixtureLiveOwners(),
        (unsigned long long)TLinkAXFixturePeakOwners(),(unsigned long long)TLinkAXFixtureDroppedOwners(),
        historyLocks.size(),(unsigned long)historyWriteAttempts.count,historyReadFault,historyWriteFault);
    assert(condition);
}
#define HISTORY_WORK_REQUIRE(condition) historyWorkRequire((condition),__LINE__)
static NSArray *historyWorkOldTail(NSString *text){
    return BeforeWork::TLinkRunHistoryBoundedLogTail([text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]);
}
static void historyWorkTextCases(){
    NSArray *separators=@[@"\n",@"\r",@"\r\n",@"\v",@"\f",@"\u0085",@"\u2028",@"\u2029",@""];
    for(unsigned n=0;n<1000;++n){
        @autoreleasepool{
            NSMutableString *text=[NSMutableString string];
            for(unsigned row=0;row<n%104;++row){
                [text appendFormat:@"%@%@",row%4?@"ảnh 测试 😀 license_key=secret":@"",separators[(row+n)%separators.count]];
            }
            if(n%3==0)[text appendString:@"tail\0kept Bearer token"];
            HistoryTailText *probe=[[HistoryTailText alloc] initWithText:text];
            NSArray *expected=historyWorkOldTail(probe),*actual=Current::TLinkRunHistoryTailFromText(probe);
            HISTORY_WORK_REQUIRE([expected isEqual:actual]&&probe->pieces<=50&&probe->searches<=50);
        }
    }
    HistoryTailText *dense=[[HistoryTailText alloc] initWithText:[@"" stringByPaddingToLength:262144 withString:@"\n" startingAtIndex:0]];
    HISTORY_WORK_REQUIRE([historyWorkOldTail(dense) isEqual:Current::TLinkRunHistoryTailFromText(dense)]);
    HISTORY_WORK_REQUIRE(dense->splitPieces==262145&&dense->pieces==50&&dense->searches==50);
    // Full unbounded input remains bounded in output; truncation follows redaction.
    NSString *longLine=[@"license_key=secret " stringByAppendingString:[@"" stringByPaddingToLength:12000 withString:@"x" startingAtIndex:0]];
    HISTORY_WORK_REQUIRE([historyWorkOldTail(longLine) isEqual:Current::TLinkRunHistoryTailFromText(longLine)]);
    NSArray *held=nil;
    @autoreleasepool{held=Current::TLinkRunHistoryTailFromText(@"old\nlicense_key=secret\nảnh\0尾\n");}
    HISTORY_WORK_REQUIRE([held isEqual:historyWorkOldTail(@"old\nlicense_key=secret\nảnh\0尾\n")]);
}
static void historyWorkLinePools(){
    NSMutableArray *input=[NSMutableArray array];for(unsigned n=0;n<50;++n)[input addObject:[HistoryProbe new]];
    NSArray *held=nil,*expected=nil;
    for(bool modern:{false,true}){
        @autoreleasepool{
            TLinkAXFixtureResetOwners();historyWorkTracking=true;
            if(modern)held=Current::TLinkRunHistoryBoundedLogTail(input);else expected=BeforeWork::TLinkRunHistoryBoundedLogTail(input);
            HISTORY_WORK_REQUIRE(TLinkAXFixtureCreatedOwners()==150);
            HISTORY_WORK_REQUIRE(modern?(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixturePeakOwners()==2):(TLinkAXFixtureLiveOwners()==150&&TLinkAXFixturePeakOwners()==150));
            historyWorkTracking=false;
        }
        HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==0);
    }
    HISTORY_WORK_REQUIRE([held isEqual:expected]);
}
static NSDictionary *historyWorkFlow(bool modern,bool beforeIndex=false){
    HistoryBegin begin=modern?Current::TLinkRunHistoryBegin:BeforeWork::TLinkRunHistoryBegin;
    HistoryFinish finish=modern?Current::TLinkRunHistoryFinish:BeforeWork::TLinkRunHistoryFinish;
    HistorySnapshot snapshot=modern?Current::TLinkRunHistorySnapshot:BeforeWork::TLinkRunHistorySnapshot;
    NSString *root=modern?Current::fixtureRoot:BeforeWork::fixtureRoot;
    if(beforeIndex){begin=BeforeIndexWork::TLinkRunHistoryBegin;finish=BeforeIndexWork::TLinkRunHistoryFinish;snapshot=BeforeIndexWork::TLinkRunHistorySnapshot;root=BeforeIndexWork::fixtureRoot;}
    historyUUIDs=900000;[historyEvents removeAllObjects];[historyWriteAttempts removeAllObjects];
    NSMutableArray *replies=[NSMutableArray array];
    for(unsigned n=0;n<64;++n){
        @autoreleasepool{
            NSDictionary *running=begin(@"fixture",@"/bundle/ảnh",@"main.js",@{@"n":@(n)});
            HISTORY_WORK_REQUIRE(running[@"run_id"]!=nil);
            NSDictionary *done=finish(running[@"run_id"],n%3?@"finished":@"failed",@"license_key=secret",@[@"line",@"Bearer secret",@"ảnh"],@"",@"",nil,@{@"n":@(n)});
            HISTORY_WORK_REQUIRE(done[@"run_id"]!=nil);[replies addObject:historyNormalize(done,root)];
        }
    }
    NSMutableArray *snapshots=[NSMutableArray array];
    for(NSUInteger limit:{NSUInteger(0),NSUInteger(1),NSUInteger(20),NSUInteger(49),NSUInteger(50),NSUInteger(51),NSUIntegerMax})[snapshots addObject:historyNormalize(snapshot(limit),root)];
    NSDictionary *result=@{@"replies":replies,@"snapshots":snapshots,@"index":historyNormalize(historyReadJSON([root stringByAppendingPathComponent:@"index.json"]),root),
        @"events":historyNormalize([historyEvents copy],root),@"writes":[historyWriteAttempts copy]};
    return result;
}
static void historyWorkOperationPools(){
    for(bool modern:{false,true}){
        HistoryBegin begin=modern?Current::TLinkRunHistoryBegin:BeforeWork::TLinkRunHistoryBegin;
        HistoryFinish finish=modern?Current::TLinkRunHistoryFinish:BeforeWork::TLinkRunHistoryFinish;
        HistorySnapshot snapshot=modern?Current::TLinkRunHistorySnapshot:BeforeWork::TLinkRunHistorySnapshot;
        NSDictionary *held=nil;
        // An individual JSON write retires its encoding temporary before the
        // enclosing transaction writes another artifact/index.
        @autoreleasepool{
            NSString *root=modern?Current::fixtureRoot:BeforeWork::fixtureRoot;
            NSString *path=[root stringByAppendingPathComponent:@"runs/pool-only.json"];
            TLinkAXFixtureResetOwners();historyWorkTracking=true;
            BOOL written=modern?Current::TLinkRunHistoryWriteJSON(@{@"held":@"ảnh"},path):BeforeWork::TLinkRunHistoryWriteJSON(@{@"held":@"ảnh"},path);
            HISTORY_WORK_REQUIRE(written&&TLinkAXFixtureCreatedOwners()==1);
            HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==(modern?0U:1U));
            historyWorkTracking=false;
        }
        HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==0);
        NSArray *heldTail=nil;
        @autoreleasepool{
            NSString *console=[historyTestRoot stringByAppendingPathComponent:@"work-console.log"];
            HISTORY_WORK_REQUIRE([[@"old\nlicense_key=secret\nảnh\n" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:console atomically:YES]);
            TLinkAXFixtureResetOwners();historyWorkTracking=true;
            heldTail=modern?Current::TLinkRunHistoryTailFromConsoleFile(console):BeforeWork::TLinkRunHistoryTailFromConsoleFile(console);
            HISTORY_WORK_REQUIRE(TLinkAXFixtureCreatedOwners()>0&&heldTail.count&&historyConsoleFds.empty());
            HISTORY_WORK_REQUIRE(modern?TLinkAXFixtureLiveOwners()==0:TLinkAXFixtureLiveOwners()>0);
            historyWorkTracking=false;
        }
        HISTORY_WORK_REQUIRE([heldTail isEqual:historyWorkOldTail(@"old\nlicense_key=secret\nảnh\n")]&&TLinkAXFixtureLiveOwners()==0);
        NSMutableArray *retired=[NSMutableArray array];
        NSString *root=modern?Current::fixtureRoot:BeforeWork::fixtureRoot;
        for(unsigned n=0;n<64;++n){
            NSString *runId=[NSString stringWithFormat:@"retire-%u",n];
            [retired addObject:@{@"run_id":runId,@"record_path":[root stringByAppendingPathComponent:[NSString stringWithFormat:@"runs/%@.json",runId]],@"failure_evidence":@{}}];
        }
        @autoreleasepool{
            TLinkAXFixtureResetOwners();historyWorkTracking=true;
            const int fd=modern?Current::TLinkRunHistoryAcquireFileLock():BeforeWork::TLinkRunHistoryAcquireFileLock();
            HISTORY_WORK_REQUIRE(fd>=0);
            if(modern)Current::TLinkRunHistoryPrune(retired,@[retired[0]]);else BeforeWork::TLinkRunHistoryPrune(retired,@[retired[0]]);
            if(modern)Current::TLinkRunHistoryReleaseFileLock(fd);else BeforeWork::TLinkRunHistoryReleaseFileLock(fd);
            HISTORY_WORK_REQUIRE(TLinkAXFixtureCreatedOwners()==192);
            HISTORY_WORK_REQUIRE(modern?(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixturePeakOwners()==3):TLinkAXFixtureLiveOwners()==192);
            historyWorkTracking=false;
        }
        HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==0);
        for(unsigned operation=0;operation<3;++operation){
            @autoreleasepool{
                TLinkAXFixtureResetOwners();historyWorkTracking=true;
                if(operation==0)held=begin(@"fixture",@"/bundle",@"lifetime.js",@{});
                if(operation==1)held=finish(held[@"run_id"],@"failed",@"license_key=secret",@[@"line"],@"",@"",nil,@{});
                if(operation==2)held=snapshot(50);
                HISTORY_WORK_REQUIRE(held.count&&historyLocks.empty()&&historyIndexFds.empty()&&historyLockFds.empty());
                HISTORY_WORK_REQUIRE(TLinkAXFixtureCreatedOwners()>0);
                HISTORY_WORK_REQUIRE(modern?TLinkAXFixtureLiveOwners()==0:TLinkAXFixtureLiveOwners()>0);
                if(operation==2)HISTORY_WORK_REQUIRE(modern?TLinkAXFixturePeakOwners()==2:TLinkAXFixturePeakOwners()==52);
                historyWorkTracking=false;
            }
            HISTORY_WORK_REQUIRE(held.count&&TLinkAXFixtureLiveOwners()==0);
        }
    }
    // Public entry catches read/write faults before a normal return. No replay.
    for(bool reading:{false,true}){
        for(unsigned fault:{1U,2U}){
            @autoreleasepool{
                TLinkAXFixtureResetOwners();historyWorkTracking=true;
                if(reading)historyReadFault=fault;else{historyWriteStage=@"record";historyWriteFault=fault+1;}
                NSDictionary *failed=Current::TLinkRunHistoryBegin(@"fixture",@"/bundle",@"fault.js",@{});
                HISTORY_WORK_REQUIRE(!failed.count&&TLinkAXFixtureLiveOwners()==0&&historyLocks.empty());
                if(reading)HISTORY_WORK_REQUIRE([Current::TLinkRunHistorySnapshot(1)[@"error"] isEqual:@"history_snapshot_exception"]&&TLinkAXFixtureLiveOwners()==0);
                historyReadFault=historyWriteFault=0;historyWriteStage=nil;historyWorkTracking=false;
            }
            HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==0&&historyIndexFds.empty()&&historyLockFds.empty());
        }
    }
}
static void historyWorkCases(){
    fputs("History work Foundation: actual/preceding complete history, bounded Foundation tail and MRC operation/line/row owners\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedRecovered=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"work-current"];
    BeforeWork::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"work-before"];
    Current::sTLinkRunHistoryRecovered=NO;
    historyWorkTextCases();historyWorkLinePools();
    NSDictionary *expected=historyWorkFlow(false),*actual=historyWorkFlow(true);
    HISTORY_WORK_REQUIRE([expected isEqual:actual]);
    historyWorkOperationPools();
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedRecovered;
    HISTORY_WORK_REQUIRE(TLinkAXFixtureLiveOwners()==0&&historyLocks.empty()&&historyConsoleFds.empty());
    puts("History work passed: 1000 Foundation newline/Unicode/redaction tails, 262145 versus 50 logical components, 64 complete frozen transactions/retention/events/index and seven status limits, explicit line/row/write/public-operation pool retirement, held graphs and caught NS/C++ read/write faults. Foundation allocation/device performance remains unqualified.");
}
#undef HISTORY_WORK_REQUIRE
