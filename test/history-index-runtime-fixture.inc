// C03u: actual descriptor reader and index-only encoded-output limit.
static void historyBoundedIndexRejected(NSString *snapshotCode,NSString *mutationCode){
    historySnapshotRejected(snapshotCode,@"read");
    NSString *root=Current::fixtureRoot,*lock=[root stringByAppendingPathComponent:@"history.lock"];
    for(bool beginning:{true,false}){
        NSDictionary *files=historyDiskBytes(root);const NSUInteger events=historyEvents.count,writes=historyWriteAttempts.count;
        const BOOL ready=Current::sTLinkRunHistoryRecovered;
        const size_t markers=historyMarkerChanges,opens=historyRecoveryOpens;
        assert(!historyMutation(beginning).count);
        NSDictionary *last=Current::sTLinkRunHistoryLastPersistenceFailure;
        assert([last[@"stage"] isEqualToString:@"read"]&&[last[@"code"] isEqualToString:mutationCode]);
        assert(historyEvents.count==events&&historyWriteAttempts.count==writes&&[files isEqual:historyDiskBytes(root)]);
        assert(Current::sTLinkRunHistoryRecovered==ready&&historyMarkerChanges==markers&&historyRecoveryOpens==opens);
        assert(historyLocks.empty()&&historyIndexFds.empty()&&historyRecoveryFds.empty()&&historyChildCanLock(lock));
    }
}
static void historyBoundedIndexCases(){
    fputs("History index Foundation: actual bounded POSIX reader, byte limits and index commit refusal\n",stderr);
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"bounded-index"];
    Current::TLinkRunHistoryEnsureDirectories();
    NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    const NSUInteger limit=Current::kTLinkRunHistoryIndexMaxBytes;assert(limit==32*1024*1024);
    NSData *healthy=[@"{\"schema\":\"run_history_v1\",\"runs\":[],\"extension\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([healthy writeToFile:path atomically:YES]);
    // Real sparse oversize: use only stat here; the general byte-preservation helper would read it.
    int fd=::open(path.fileSystemRepresentation,O_WRONLY|O_TRUNC);assert(fd>=0&&::ftruncate(fd,(off_t)limit+1)==0&&::close(fd)==0);
    const size_t allocations=historyIndexAllocations,reads=historyIndexReadCalls,markers=historyMarkerChanges;
    const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;
    NSDictionary *oversize=Current::TLinkRunHistorySnapshot(0);
    assert([oversize[@"error"] isEqualToString:@"history_snapshot_too_large"]);
    for(bool beginning:{true,false})assert(!historyMutation(beginning).count&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"index_too_large"]);
    struct stat info;assert(::stat(path.fileSystemRepresentation,&info)==0&&(uint64_t)info.st_size==limit+1);
    assert(historyIndexAllocations==allocations&&historyIndexReadCalls==reads&&historyMarkerChanges==markers);
    assert(historyWriteAttempts.count==writes&&historyEvents.count==events&&historyIndexFds.empty()&&historyLocks.empty());
    assert([healthy writeToFile:path atomically:YES]);
    for(unsigned fault=1;fault<=2;++fault){historyIndexOpenFault=fault;historyBoundedIndexRejected(@"history_snapshot_read_failed",@"read_failed");historyIndexOpenFault=0;}
    for(unsigned fault=1;fault<=3;++fault){
        historyIndexStatFault=fault;
        historyBoundedIndexRejected(fault==2?@"history_snapshot_too_large":@"history_snapshot_read_failed",fault==2?@"index_too_large":@"read_failed");
        historyIndexStatFault=0;
    }
    for(unsigned fault:{2U,3U,4U,5U,7U}){
        historyIndexReadFault=fault;
        if(fault==4||fault==5){
            // Snapshot contains exceptions; begin/finish retain their existing fixed diagnostics.
            historyBoundedIndexRejected(@"history_snapshot_exception",@"exception");
        }else historyBoundedIndexRejected(@"history_snapshot_read_failed",@"read_failed");
        historyIndexReadFault=0;
    }
    historyIndexReadFault=1;const uint64_t bytes=historyIndexBytes;
    assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
    assert(historyIndexReadFault==6&&historyIndexBytes-bytes==healthy.length&&historyIndexFds.empty());historyIndexReadFault=0;
    @autoreleasepool {
        NSMutableData *padded=[healthy mutableCopy];[padded increaseLengthBy:limit-padded.length];
        memset((uint8_t *)padded.mutableBytes+healthy.length,' ',padded.length-healthy.length);
        assert(padded.length==limit&&[padded writeToFile:path atomically:YES]);
        const uint64_t before=historyIndexBytes;const size_t calls=historyIndexReadCalls;
        assert([Current::TLinkRunHistorySnapshot(0)[@"state"] isEqualToString:@"implemented"]);
        assert(historyIndexBytes-before==limit&&historyIndexReadCalls-calls>=513&&historyIndexFds.empty());
        // Equality is also admitted by the production writer before its atomic write.
        historyEncodedIndexOverride=padded;assert(Current::TLinkRunHistoryWriteIndex(@[]));historyEncodedIndexOverride=nil;
        assert([padded isEqual:[NSData dataWithContentsOfFile:path]]);
        historyIndexReadFault=7;const NSUInteger eventCount=historyEvents.count;
        NSDictionary *grown=Current::TLinkRunHistorySnapshot(0);historyIndexReadFault=0;
        assert([grown[@"error"] isEqualToString:@"history_snapshot_too_large"]&&historyEvents.count==eventCount&&historyIndexFds.empty());
    }
    assert([healthy writeToFile:path atomically:YES]);
    // Reject symlink (including dangling), FIFO and directory leaves without payload IO.
    NSFileManager *fm=[NSFileManager defaultManager];NSString *target=[Current::fixtureRoot stringByAppendingPathComponent:@"outside.json"];
    assert([healthy writeToFile:target atomically:YES]);struct stat targetInfo;assert(::stat(target.fileSystemRepresentation,&targetInfo)==0);
    for(unsigned kind=0;kind<4;++kind){
        assert([fm removeItemAtPath:path error:nil]);
        if(kind<2)assert(::symlink((kind==0?target:[target stringByAppendingString:@".missing"]).fileSystemRepresentation,path.fileSystemRepresentation)==0);
        else if(kind==2)assert(::mkfifo(path.fileSystemRepresentation,0600)==0);
        else assert([fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
        const size_t beforeReads=historyIndexReadCalls,beforeAllocations=historyIndexAllocations;
        // No whole-file snapshot helper is used on a FIFO/symlink.
        NSDictionary *reply=Current::TLinkRunHistorySnapshot(0);
        assert([reply[@"error"] isEqualToString:@"history_snapshot_read_failed"]);
        for(bool beginning:{true,false})assert(!historyMutation(beginning).count&&[Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"read_failed"]);
        assert(historyIndexReadCalls==beforeReads&&historyIndexAllocations==beforeAllocations&&historyIndexFds.empty()&&historyLocks.empty());
        struct stat after;assert(::stat(target.fileSystemRepresentation,&after)==0&&after.st_mode==targetInfo.st_mode);
        assert([healthy isEqual:[NSData dataWithContentsOfFile:target]]);
    }
    assert([fm removeItemAtPath:path error:nil]&&[healthy writeToFile:path atomically:YES]);
    @autoreleasepool {
        // Supply an oversized encoded NSData at the real encoder boundary, avoiding huge artifacts.
        NSData *tooLarge=[NSMutableData dataWithLength:limit+1];
        for(bool beginning:{true,false}){
            assert([healthy writeToFile:path atomically:YES]);Current::sTLinkRunHistoryRecovered=YES;
            historyEncodedIndexOverride=tooLarge;[historyWriteAttempts removeAllObjects];const NSUInteger count=historyEvents.count;
            assert(!historyMutation(beginning).count);historyEncodedIndexOverride=nil;
            assert([healthy isEqual:[NSData dataWithContentsOfFile:path]]&&historyEvents.count==count);
            // historyMutation(false) finishes as failed, so it writes evidence before its record.
            NSArray *expectedWrites=beginning?@[@"record"]:@[@"evidence",@"record"];
            if(![historyWriteAttempts isEqualToArray:expectedWrites]){
                fprintf(stderr,"History oversized index %s: expected %s, received %s\n",beginning?"begin":"failed finish",
                    expectedWrites.description.UTF8String,historyWriteAttempts.description.UTF8String);
            }
            assert([historyWriteAttempts isEqualToArray:expectedWrites]);
            assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"stage"] isEqualToString:@"index"]);
            assert([Current::sTLinkRunHistoryLastPersistenceFailure[@"code"] isEqualToString:@"write_failed"]);
            assert(historyPendingSize()==1&&!Current::sTLinkRunHistoryRecovered&&historyLocks.empty()&&historyIndexFds.empty());
            if(!beginning){
                NSDictionary *ahead=historyReadJSON([Current::TLinkRunHistoryRunsPath() stringByAppendingPathComponent:@"validation-finish.json"]);
                NSDictionary *evidence=historyReadJSON([Current::TLinkRunHistoryEvidencePath() stringByAppendingPathComponent:@"validation-finish.json"]);
                assert([ahead[@"state"] isEqualToString:@"failed"]&&[ahead[@"failure_evidence"] isEqual:evidence]);
            }
            // Same production recovery/ACK semantics: the ahead record is not rolled back or replayed.
            assert(historyMutation(beginning).count&&historyPendingSize()==0&&Current::sTLinkRunHistoryRecovered&&historyEvents.count==count+1);
        }
    }
    @autoreleasepool {
        // Real JSON encoding of worst escaped bounded error/tail fields fits below 32 MiB.
        NSString *unit=[NSString stringWithFormat:@"%C",(unichar)1];
        NSString *line=[unit stringByPaddingToLength:1000 withString:unit startingAtIndex:0];
        NSString *error=[unit stringByPaddingToLength:4000 withString:unit startingAtIndex:0];
        NSMutableArray *tail=[NSMutableArray array];for(unsigned n=0;n<50;++n)[tail addObject:line];
        NSMutableArray *runs=[NSMutableArray array];
        for(unsigned n=0;n<50;++n)[runs addObject:@{@"run_id":[NSString stringWithFormat:@"max-%u",n],@"state":@"failed",@"error":error,
            @"failure_evidence":@{@"schema":Current::TLinkFailureEvidenceSchemaV1,@"error":error,@"log_tail":tail}}];
        assert(Current::TLinkRunHistoryWriteIndex(runs));
        assert(::stat(path.fileSystemRepresentation,&info)==0&&info.st_size>16*1024*1024&&(uint64_t)info.st_size<limit);
        NSDictionary *reply=Current::TLinkRunHistorySnapshot(50);
        assert([reply[@"state"] isEqualToString:@"implemented"]&&[reply[@"runs"] count]==50&&[reply[@"failed_count"] intValue]==50);
    }
    assert(historyIndexFds.empty()&&historyLocks.empty()&&!historyEncodedIndexOverride);
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    puts("History bounded index passed: real sparse oversize before allocation/payload IO, exact 32-MiB read/write, open/stat/negative-size/EOF/EIO/EINTR/short/NS/C++/growth faults, symlink/FIFO/directory refusal, writer refusal/pending recovery and 50 worst-escaped bounded payloads. Total JSON/RSS/IO time and extension sizes remain separate.");
}
