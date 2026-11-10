static void historyStatusMemoCases(){
    @autoreleasepool {
    puts("History status memo Foundation: fresh reads, frozen projections and detached mutable results");
    NSString *savedRoot=Current::fixtureRoot;const uint64_t savedFailures=Current::sTLinkRunHistoryPersistenceFailures;
    NSDictionary *savedLast=Current::sTLinkRunHistoryLastPersistenceFailure;const BOOL savedRecovered=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"status-memo"];Current::TLinkRunHistoryEnsureDirectories();
    NSString *path=Current::TLinkRunHistoryIndexPath();NSMutableArray *runs=[NSMutableArray array];
    NSString *error=[@"ảnh " stringByPaddingToLength:700 withString:@"x" startingAtIndex:0],*line=[@"line " stringByPaddingToLength:400 withString:@"z" startingAtIndex:0];
    for(unsigned n=0;n<32;++n){[runs addObject:@{@"run_id":[NSString stringWithFormat:@"memo-%u",n],@"state":n%3?@"finished":@"failed",@"error":error,
        @"failure_evidence":@{@"error":error,@"log_tail":@[line,line,line,line]},
        @"extra":@{@"wide":@(UINT64_MAX),@"nested":@[@{@"value":@7}]},@"play_settings":@{@"nested":@[@1,@2]}}];}
    assert(Current::TLinkRunHistoryWriteIndex(runs));NSData *bytes=[NSData dataWithContentsOfFile:path];assert(bytes);
    historyMemoEnabled=true;TLinkHistoryStatusMemo::Clear();NSDictionary *expected=Current::TLinkRunHistoryBeforeStatusMemo(20);
    const unsigned decodes=historyMemoDecodes.load();const size_t reads=historyIndexReads;
    for(unsigned n=0;n<129;++n){NSDictionary *value=Current::TLinkRunHistorySnapshot(20);assert([expected isEqual:value]);}
    assert(historyMemoDecodes==decodes+1&&historyIndexReads==reads+129&&TLinkHistoryStatusMemo::Snapshot());
    NSMutableDictionary *first=Current::TLinkRunHistorySnapshot(20)[@"runs"][0];
    first[@"extra"][@"nested"][0][@"value"]=@0;first[@"play_settings"][@"nested"][0]=@99;
    [(NSMutableArray *)first[@"failure_evidence"][@"log_tail"] addObject:@"poison"];
    assert([expected isEqual:Current::TLinkRunHistorySnapshot(20)]);
    for(NSUInteger limit:{NSUInteger(0),NSUInteger(1),NSUInteger(20),NSUInteger(50),NSUInteger(1000)}){
        NSDictionary *before=Current::TLinkRunHistoryBeforeStatusMemo(limit),*now=Current::TLinkRunHistorySnapshot(limit);
        assert([before isEqual:now]&&[now[@"total_count"] unsignedIntegerValue]==32&&[now[@"failed_count"] unsignedIntegerValue]==11);
        const unsigned warm=historyMemoDecodes.load();Current::TLinkRunHistorySnapshot(limit);assert(historyMemoDecodes==warm);
    }
    // Once the complete 32-row graph is retained, alternating request sizes
    // must neither decode again nor deep-copy the rows outside the request.
    const unsigned mixedDecodes=historyMemoDecodes.load();const size_t mixedReads=historyIndexReads;
    for(unsigned round=0;round<32;++round){
        for(NSUInteger limit:{NSUInteger(1),NSUInteger(20),NSUInteger(0),NSUInteger(50),NSUInteger(1000)}){
            NSDictionary *before=Current::TLinkRunHistoryBeforeStatusMemo(limit);
            const unsigned afterOracle=historyMemoDecodes.load();
            NSDictionary *now=Current::TLinkRunHistorySnapshot(limit);assert([before isEqual:now]);
            assert(historyMemoDecodes==afterOracle);
        }
    }
    assert(historyMemoDecodes==mixedDecodes+160&&historyIndexReads==mixedReads+320);
    historyMemoCopyNodes=0;Current::TLinkRunHistorySnapshot(1);const size_t oneRowNodes=historyMemoCopyNodes;
    historyMemoCopyNodes=0;Current::TLinkRunHistorySnapshot(50);assert(oneRowNodes>0&&historyMemoCopyNodes>oneRowNodes);
    // A partial projection cannot satisfy a larger request until that request
    // has performed its own fresh read/decode/projection.
    TLinkHistoryStatusMemo::Clear();Current::TLinkRunHistorySnapshot(1);const unsigned partialDecodes=historyMemoDecodes.load();
    Current::TLinkRunHistorySnapshot(20);assert(historyMemoDecodes==partialDecodes+1);
    Current::TLinkRunHistorySnapshot(1);assert(historyMemoDecodes==partialDecodes+1);
    Current::TLinkRunHistorySnapshot(50);assert(historyMemoDecodes==partialDecodes+2);
    const unsigned stable=historyMemoDecodes.load();assert([bytes writeToFile:path atomically:YES]);Current::TLinkRunHistorySnapshot(1000);assert(historyMemoDecodes==stable);
    Current::TLinkRunHistoryPersistenceFailure(@"memo-test",@"probe",@"fresh_diagnostics");
    NSDictionary *fresh=Current::TLinkRunHistorySnapshot(1000);assert([fresh[@"persistence_diagnostics"][@"last_failure"][@"code"] isEqual:@"fresh_diagnostics"]);
    for(unsigned fault=1;fault<=3;++fault){
        TLinkHistoryStatusMemo::Clear();historyMemoCopyFault=fault;
        NSDictionary *before=Current::TLinkRunHistoryBeforeStatusMemo(20),*now=Current::TLinkRunHistorySnapshot(20);assert([before isEqual:now]&&!TLinkHistoryStatusMemo::Snapshot());
        historyMemoCopyFault=0;Current::TLinkRunHistorySnapshot(20);assert(TLinkHistoryStatusMemo::Snapshot());
        historyMemoCopyFault=fault;now=Current::TLinkRunHistorySnapshot(20);historyMemoCopyFault=0;assert([before isEqual:now]&&!TLinkHistoryStatusMemo::Snapshot());
    }
    for(unsigned fault=1;fault<=2;++fault){
        Current::TLinkRunHistorySnapshot(20);historyReadFault=fault;NSDictionary *value=Current::TLinkRunHistorySnapshot(20);historyReadFault=0;
        assert([value[@"state"] isEqual:@"error"]&&!TLinkHistoryStatusMemo::Snapshot()&&historyLocks.empty()&&historyIndexFds.empty());
    }
    Current::TLinkRunHistorySnapshot(20);historySnapshotReadFault=1;
    NSDictionary *unreadable=Current::TLinkRunHistorySnapshot(20);historySnapshotReadFault=0;
    assert([unreadable[@"error"] isEqual:@"history_snapshot_read_failed"]&&!TLinkHistoryStatusMemo::Snapshot());
    Current::TLinkRunHistorySnapshot(20);const size_t deniedReads=historyIndexReads;historyLockDenied=true;
    NSDictionary *denied=Current::TLinkRunHistorySnapshot(20);historyLockDenied=false;
    assert([denied[@"error"] isEqual:@"history_snapshot_lock_failed"]&&historyIndexReads==deniedReads&&!TLinkHistoryStatusMemo::Snapshot());
    NSData *invalid=[@"not-json" dataUsingEncoding:NSUTF8StringEncoding];assert([invalid writeToFile:path atomically:YES]);
    assert([Current::TLinkRunHistorySnapshot(20)[@"error"] isEqual:@"history_snapshot_invalid_index"]&&!TLinkHistoryStatusMemo::Snapshot());
    NSFileManager *fm=[NSFileManager defaultManager];assert([fm removeItemAtPath:path error:nil]);
    NSDictionary *missing=Current::TLinkRunHistorySnapshot(20);
    assert([missing[@"state"] isEqual:@"implemented"]&&[missing[@"total_count"] unsignedIntegerValue]==0&&!TLinkHistoryStatusMemo::Snapshot()&&![fm fileExistsAtPath:path]);
    assert([bytes writeToFile:path atomically:YES]);Current::TLinkRunHistorySnapshot(20);
    assert([fm removeItemAtPath:path error:nil]&&[fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
    assert([Current::TLinkRunHistorySnapshot(20)[@"error"] isEqual:@"history_snapshot_read_failed"]&&!TLinkHistoryStatusMemo::Snapshot());assert([fm removeItemAtPath:path error:nil]);
    for(unsigned shape=0;shape<3;++shape){
        id value=@"leaf";
        if(shape==0){for(unsigned n=0;n<40;++n)value=@[value];}
        else if(shape==1){NSMutableArray *large=[NSMutableArray array];for(unsigned n=0;n<5000;++n)[large addObject:@0];value=large;}
        else value=[@"x" stringByPaddingToLength:TLinkHistoryStatusMemo::ByteLimit+1 withString:@"x" startingAtIndex:0];
        assert(Current::TLinkRunHistoryWriteIndex(@[@{@"run_id":@"large",@"state":@"finished",@"extra":value}]));
        const unsigned before=historyMemoDecodes.load();
        for(unsigned n=0;n<2;++n){@autoreleasepool {assert([Current::TLinkRunHistorySnapshot(20)[@"state"] isEqual:@"implemented"]&&!TLinkHistoryStatusMemo::Snapshot());}}
        assert(historyMemoDecodes==before+2);
    }
    // No serializer round-trip: wide numbers, negative zero and invalid UTF16 survive.
    const unichar unit=0xd83d;NSString *unpaired=[NSString stringWithCharacters:&unit length:1];
    NSMutableString *text=[@"original" mutableCopy];NSMutableData *key=[NSMutableData dataWithBytes:"key" length:3];
    NSMutableArray *projection=[NSMutableArray arrayWithObject:[@{@"wide":@(UINT64_MAX),@"zero":@(-0.0),@"text":text,@"unpaired":unpaired,@"nested":[NSMutableArray arrayWithObject:@1]} mutableCopy]];
    TLinkHistoryStatusMemo::Offer(key,20,projection,1,0);assert(TLinkHistoryStatusMemo::Snapshot());[text setString:@"changed"];[(NSMutableArray *)projection[0][@"nested"] addObject:@2];((uint8_t *)key.mutableBytes)[0]='x';
    NSData *original=[NSData dataWithBytes:"key" length:3];TLinkHistoryStatusMemo::Read held(20);assert(TLinkHistoryStatusMemo::Lookup(original,held));
    assert([held.rows[0][@"wide"] unsignedLongLongValue]==UINT64_MAX&&std::signbit([held.rows[0][@"zero"] doubleValue])&&[held.rows[0][@"text"] isEqual:@"original"]&&[held.rows[0][@"unpaired"] characterAtIndex:0]==unit&&[held.rows[0][@"nested"] count]==1);
    held.rows[0][@"nested"][0]=@9;TLinkHistoryStatusMemo::Read again(20);assert(TLinkHistoryStatusMemo::Lookup(original,again)&&[again.rows[0][@"nested"][0] intValue]==1);
    TLinkHistoryStatusMemo::Read larger(50);assert(TLinkHistoryStatusMemo::Lookup(original,larger)&&larger.rows.count==1);
    TLinkHistoryStatusMemo::Offer(original,20,@[],1,0);assert(!TLinkHistoryStatusMemo::Snapshot());
    TLinkHistoryStatusMemo::Offer(original,20,@[],0,0);TLinkHistoryStatusMemo::Read empty(50);
    assert(TLinkHistoryStatusMemo::Lookup(original,empty)&&empty.rows.count==0&&empty.total==0&&empty.failed==0);
    TLinkHistoryStatusMemo::Clear();historyMemoEnabled=false;historyMemoCopyFault=0;
    assert(historyLocks.empty()&&historyIndexFds.empty()&&Current::sTLinkRunHistoryRecovered==savedRecovered);
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryPersistenceFailures=savedFailures;Current::sTLinkRunHistoryLastPersistenceFailure=savedLast;
    puts("History status memo passed: 129 fresh reads/one decode, frozen limits/fields/counts, detached deep mutability, fresh diagnostics, copy NS/C++/nil fallback, read/lock/corruption/type failures, uncached graph/byte limits and exact uint64/negative-zero/UTF16 ownership. Device performance pending.");
    }
}
