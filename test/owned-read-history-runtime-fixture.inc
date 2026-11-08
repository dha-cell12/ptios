static NSDictionary *historyOwnedIndexOutcome(bool modern,unsigned readFault=0,unsigned openFault=0,unsigned statFault=0){
    NSObject *monitor=modern?Current::TLinkRunHistoryLock():BeforeOwnedRead::TLinkRunHistoryLock();
    @synchronized(monitor){
        const int lock=modern?Current::TLinkRunHistoryAcquireFileLock(YES):BeforeOwnedRead::TLinkRunHistoryAcquireFileLock(YES);assert(lock>=0);
        historyIndexReadFault=readFault;historyIndexOpenFault=openFault;historyIndexStatFault=statFault;
        const size_t reads=historyIndexReadCalls,allocations=historyIndexAllocations;const uint64_t bytes=historyIndexBytes;
        BOOL missing=NO;NSString *code=nil,*exception=@"";NSData *data=nil;
        @try {try {data=modern?Current::TLinkRunHistoryReadIndexData(&missing,&code):BeforeOwnedRead::TLinkRunHistoryReadIndexData(&missing,&code);}
            catch(const std::runtime_error &){exception=@"cpp";}}
        @catch(NSException *caught){exception=caught.name;}
        @finally {
            historyIndexReadFault=historyIndexOpenFault=historyIndexStatFault=0;
            if(modern)Current::TLinkRunHistoryReleaseFileLock(lock);else BeforeOwnedRead::TLinkRunHistoryReleaseFileLock(lock);
        }
        assert(historyLocks.empty()&&historyIndexFds.empty()&&historyLockFds.empty());
        return @{@"missing":@(missing),@"code":code?:@"",@"exception":exception,@"data":data?(id)data:(id)[NSNull null],
                 @"reads":@(historyIndexReadCalls-reads),@"bytes":@(historyIndexBytes-bytes),@"allocations":@(historyIndexAllocations-allocations)};
    }
}
static void historyOwnedReadCases(){
    NSString *saved=Current::fixtureRoot;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"owned-read-history"];
    BeforeOwnedRead::fixtureRoot=Current::fixtureRoot;Current::TLinkRunHistoryEnsureDirectories();
    NSString *path=[Current::fixtureRoot stringByAppendingPathComponent:@"index.json"];
    const NSUInteger writes=historyWriteAttempts.count,events=historyEvents.count;const size_t markers=historyMarkerChanges;
    unsigned comparisons=0;
    for(NSUInteger length:{NSUInteger(0),NSUInteger(1),NSUInteger(17),NSUInteger(65537),NSUInteger(131089)}){
        @autoreleasepool {
            NSMutableData *body=[NSMutableData dataWithLength:length];
            for(NSUInteger n=0;n<length;++n)((uint8_t *)body.mutableBytes)[n]=uint8_t(n*19+3);
            for(unsigned fault=0;fault<=7;++fault){
                assert([body writeToFile:path atomically:YES]);NSDictionary *before=historyOwnedIndexOutcome(false,fault);
                assert([body writeToFile:path atomically:YES]);NSDictionary *now=historyOwnedIndexOutcome(true,fault);
                if(![before isEqual:now])fprintf(stderr,"Owned history read mismatch: length=%lu fault=%u\nbefore=%.2048s\nnow=%.2048s\n",(unsigned long)length,fault,[[before description] UTF8String]?:"<unencodable>",[[now description] UTF8String]?:"<unencodable>");
                assert([before isEqual:now]);++comparisons;
                if(!fault){
                    assert([now[@"data"] isEqual:body]&&[now[@"allocations"] unsignedIntegerValue]==1);
                    for(unsigned stat=1;stat<=3;++stat){
                        before=historyOwnedIndexOutcome(false,0,0,stat);now=historyOwnedIndexOutcome(true,0,0,stat);
                        assert([before isEqual:now]&&[now[@"allocations"] unsignedIntegerValue]==0);++comparisons;
                    }
                    for(unsigned open=1;open<=2;++open){
                        before=historyOwnedIndexOutcome(false,0,open);now=historyOwnedIndexOutcome(true,0,open);
                        assert([before isEqual:now]&&[now[@"allocations"] unsignedIntegerValue]==0);++comparisons;
                    }
                }
            }
        }
    }
    assert([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
    assert([historyOwnedIndexOutcome(false) isEqual:historyOwnedIndexOutcome(true)]);++comparisons;
    assert(comparisons==66&&historyWriteAttempts.count==writes&&historyEvents.count==events&&historyMarkerChanges==markers);
    Current::fixtureRoot=saved;BeforeOwnedRead::fixtureRoot=nil;
    puts("Owned index read passed: 66 complete preceding/current byte/error/read-count comparisons, empty/binary/three-chunk files, short/EINTR/EOF/EIO/NS/C++/growth, open/stat/size fences, missing file and zero writer/event/marker effects or live descriptors. Native input storage uses direct committed bytes.");
}
