static NSDictionary *fixtureOwnedJournalOutcome(bool modern,unsigned readFault=0,unsigned openFault=0,unsigned statFault=0){
    const int lock=TLinkEventAcquireFileLock(YES,NO);assert(lock>=0);
    fixtureJournalReadFault=readFault;fixtureJournalOpenFault=openFault;fixtureJournalStatFault=statFault;
    const unsigned reads=fixtureJournalReads.load(),allocations=fixtureJournalAllocations.load();const uint64_t bytes=fixtureJournalBytes.load();
    BOOL missing=NO;NSString *error=nil,*exception=@"";NSData *data=nil;
    @try {try {data=modern?TLinkEventReadJournalData(&missing,&error):FixtureBeforeOwnedJournalData(&missing,&error);}
        catch(const std::runtime_error &){exception=@"cpp";}}
    @catch(NSException *caught){exception=caught.name;}
    @finally {
        fixtureJournalReadFault=fixtureJournalOpenFault=fixtureJournalStatFault=0;
        TLinkEventReleaseFileLock(lock);
    }
    assert(fixtureEventLocks.empty()&&fixtureJournalFds.empty()&&!fixtureLiveEventFds&&!fixtureLiveJournalFds);
    return @{@"missing":@(missing),@"error":error?:@"",@"exception":exception,@"data":data?(id)data:(id)[NSNull null],
             @"reads":@(fixtureJournalReads.load()-reads),@"bytes":@(fixtureJournalBytes.load()-bytes),@"allocations":@(fixtureJournalAllocations.load()-allocations)};
}
static void fixtureOwnedJournalReadCases(){
    dispatch_sync(TLinkEventOwnerQueue(),^{@autoreleasepool {
        NSString *path=TLinkEventJournalPath();NSData *saved=[NSData dataWithContentsOfFile:path];
        const bool notifications=suppressNotify;suppressNotify=true;
        const unsigned writes=fixtureWrites.load(),posts=fixturePosts.load();unsigned comparisons=0;
        for(NSUInteger length:{NSUInteger(0),NSUInteger(1),NSUInteger(17),NSUInteger(65537),NSUInteger(131089)}){
            NSMutableData *body=[NSMutableData dataWithLength:length];
            for(NSUInteger n=0;n<length;++n)((uint8_t *)body.mutableBytes)[n]=uint8_t(n*23+5);
            for(unsigned fault=0;fault<=7;++fault){
                assert([body writeToFile:path atomically:YES]);NSDictionary *before=fixtureOwnedJournalOutcome(false,fault);
                assert([body writeToFile:path atomically:YES]);NSDictionary *now=fixtureOwnedJournalOutcome(true,fault);
                if(![before isEqual:now])fprintf(stderr,"Owned journal read mismatch: length=%lu fault=%u\nbefore=%.2048s\nnow=%.2048s\n",(unsigned long)length,fault,[[before description] UTF8String]?:"<unencodable>",[[now description] UTF8String]?:"<unencodable>");
                assert([before isEqual:now]);++comparisons;
                if(!fault){
                    assert([now[@"data"] isEqual:body]&&[now[@"allocations"] unsignedIntegerValue]==1);
                    for(unsigned stat=1;stat<=3;++stat){
                        before=fixtureOwnedJournalOutcome(false,0,0,stat);now=fixtureOwnedJournalOutcome(true,0,0,stat);
                        assert([before isEqual:now]&&[now[@"allocations"] unsignedIntegerValue]==0);++comparisons;
                    }
                    for(unsigned open=1;open<=2;++open){
                        before=fixtureOwnedJournalOutcome(false,0,open);now=fixtureOwnedJournalOutcome(true,0,open);
                        assert([before isEqual:now]&&[now[@"allocations"] unsignedIntegerValue]==0);++comparisons;
                    }
                }
            }
        }
        assert([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
        assert([fixtureOwnedJournalOutcome(false) isEqual:fixtureOwnedJournalOutcome(true)]);++comparisons;
        assert(comparisons==66&&fixtureWrites==writes&&fixturePosts==posts);
        if(saved)assert([saved writeToFile:path atomically:YES]);
        suppressNotify=notifications;
    }});
    puts("Owned journal read passed: 66 complete preceding/current byte/error/syscall cases, empty/binary/three-chunk data, short/EINTR/EOF/EIO/NS/C++/growth, open/stat/size and missing-file parity, no publication/notification effects and balanced descriptors.");
}
