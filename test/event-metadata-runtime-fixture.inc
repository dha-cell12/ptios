static NSString *fixtureBeforeFingerprint;
// Only the private fingerprint out-value is adapted for the healthy frozen
// sweep comparison. The old loop/callback/pool behavior is kept verbatim.
static NSDictionary *FixtureBeforeLoadSnapshot(BOOL nonblocking,NSString **fingerprint,NSString **error){
    if(fingerprint)*fingerprint=nil;
    NSDictionary *journal=TLinkEventLoadSnapshot(nonblocking,NULL,error);
    if(journal&&fingerprint)*fingerprint=FixtureBeforeFingerprint();return journal;
}
#include "EventMetadataBeforeSweep.inc"
static void FixtureMetadataRequire(bool condition,unsigned line){
    if(!condition)fprintf(stderr,"Event metadata failure line %u: owners=%llu live=%llu peak=%llu drops=%llu repairs=%zu locks=%zu waiters=%lu active=%d\n",line,
        (unsigned long long)TLinkAXFixtureCreatedOwners(),(unsigned long long)TLinkAXFixtureLiveOwners(),
        (unsigned long long)TLinkAXFixturePeakOwners(),(unsigned long long)TLinkAXFixtureDroppedOwners(),
        fixturePermissionCalls.size(),fixtureEventLocks.size(),(unsigned long)sTLinkEventWaiters.count,sTLinkEventActivePolls.load());
    assert(condition);
}
#define EVENT_METADATA_REQUIRE(condition) FixtureMetadataRequire((condition),__LINE__)
static NSString *FixtureStampText(const TLinkEventMetadata::Stamp &value){
    using Stamp=TLinkEventMetadata::Stamp;
    if(!value)return nil;
    if(value.kind==Stamp::Kind::Missing)return [NSString stringWithFormat:@"absent:%d",value.error];
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%lld:%lld:%lld",
        (unsigned long long)value.device,(unsigned long long)value.inode,(long long)value.size,
        (long long)value.modifiedSeconds,(long long)value.modifiedNanos,(long long)value.changedSeconds,(long long)value.changedNanos];
}
static void FixtureMetadataFingerprintCases(){
    fixtureFingerprintSynthetic=true;
    for(unsigned n=0;n<5000;++n){
        @autoreleasepool{
            fixtureFingerprintInfo.st_dev=(dev_t)n;fixtureFingerprintInfo.st_ino=(ino_t)(UINT64_MAX-n);
            fixtureFingerprintInfo.st_size=(off_t)(n%2?-(int64_t)n:INT64_MAX-(int64_t)n);
            fixtureFingerprintInfo.st_mtimespec.tv_sec=(time_t)(INT64_MIN+(int64_t)n);
            fixtureFingerprintInfo.st_mtimespec.tv_nsec=n%3?long(-1):long(n*17);
            fixtureFingerprintInfo.st_ctimespec.tv_sec=(time_t)(INT64_MAX-(int64_t)n);
            fixtureFingerprintInfo.st_ctimespec.tv_nsec=(long)(n*19);
            fixtureFingerprintFailure=n%7?0:(n%3?ENOENT:EACCES);
            const auto value=TLinkEventFileFingerprint();
            EVENT_METADATA_REQUIRE([FixtureBeforeFingerprint() isEqual:FixtureStampText(value)]);
        }
    }
    fixtureFingerprintSynthetic=false;fixtureFingerprintFailure=0;
    NSString *path=TLinkEventJournalPath();NSFileManager *fm=[NSFileManager defaultManager];
    if([fm fileExistsAtPath:path])EVENT_METADATA_REQUIRE([fm removeItemAtPath:path error:nil]);
    const auto missing=TLinkEventFileFingerprint();EVENT_METADATA_REQUIRE([FixtureBeforeFingerprint() isEqual:FixtureStampText(missing)]);
    EVENT_METADATA_REQUIRE([fixtureJournalData(fixtureJournal(2,@[fixtureStoredEvent(1)])) writeToFile:path atomically:YES]);
    const auto first=TLinkEventFileFingerprint();EVENT_METADATA_REQUIRE(first!=missing&&[FixtureBeforeFingerprint() isEqual:FixtureStampText(first)]);
    EVENT_METADATA_REQUIRE([fixtureJournalData(fixtureJournal(3,@[fixtureStoredEvent(1),fixtureStoredEvent(2)])) writeToFile:path atomically:YES]);
    const auto replaced=TLinkEventFileFingerprint();EVENT_METADATA_REQUIRE(replaced!=first&&[FixtureBeforeFingerprint() isEqual:FixtureStampText(replaced)]);
    EVENT_METADATA_REQUIRE([fm removeItemAtPath:path error:nil]&&TLinkEventFileFingerprint()!=replaced);
}
static bool FixturePermissionStateEqual(const FixtureEventPermissionState &a,const FixtureEventPermissionState &b){return a.mode==b.mode&&a.uid==b.uid&&a.gid==b.gid;}
static void FixtureMetadataPermissionCases(){
    NSString *saved=fixtureEventRootOverride,*root=TLinkEventChannelRootPath();
    NSString *nested=[root stringByAppendingPathComponent:@"metadata-permissions"];NSFileManager *fm=[NSFileManager defaultManager];
    EVENT_METADATA_REQUIRE(![fm fileExistsAtPath:nested]);fixtureEventRootOverride=nested;EVENT_METADATA_REQUIRE(publish()==1);
    fixturePermissionsActive=true;
    for(unsigned n=0;n<128;++n){
        for(unsigned failures:{0U,1U,2U,4U,8U,15U}){
            const mode_t rootModes[]={0750,0700,04750,01750};
            const FixtureEventPermissionState initial[2]={{rootModes[n%4],uid_t(n&4?502:501),gid_t(n&8?502:501)},
                {mode_t(n&16?0600:0640),uid_t(n&32?503:501),gid_t(n&64?503:501)}};
            FixtureEventPermissionState expected[2]{};
            for(bool modern:{false,true}){
                fixturePermissionState[0]=initial[0];fixturePermissionState[1]=initial[1];fixturePermissionFailures=failures;fixturePermissionCalls.clear();
                const int fd=modern?TLinkEventAcquireFileLock(n%2,NO):FixtureBeforeAcquireFileLock(n%2,NO);
                EVENT_METADATA_REQUIRE(fd>=0);TLinkEventReleaseFileLock(fd);
                const size_t planned=((initial[0].mode&07777)!=0750)+(initial[0].uid!=501||initial[0].gid!=501)+
                    ((initial[1].mode&07777)!=0640)+(initial[1].uid!=501||initial[1].gid!=501);
                EVENT_METADATA_REQUIRE(fixturePermissionCalls.size()==(modern?planned:4));
                if(modern)EVENT_METADATA_REQUIRE(FixturePermissionStateEqual(expected[0],fixturePermissionState[0])&&FixturePermissionStateEqual(expected[1],fixturePermissionState[1]));
                else{expected[0]=fixturePermissionState[0];expected[1]=fixturePermissionState[1];}
            }
        }
    }
    fixturePermissionFailures=0;fixturePermissionState[0]={0750,501,501};fixturePermissionState[1]={0640,501,501};fixturePermissionCalls.clear();
    for(unsigned n=0;n<64;++n){const int fd=TLinkEventAcquireFileLock(n%2,NO);EVENT_METADATA_REQUIRE(fd>=0);TLinkEventReleaseFileLock(fd);}
    EVENT_METADATA_REQUIRE(fixturePermissionCalls.empty());fixturePermissionsActive=false;
    fixtureEventRootOverride=saved;EVENT_METADATA_REQUIRE([nested hasPrefix:[root stringByAppendingString:@"/"]]&&[fm removeItemAtPath:nested error:nil]);
}
static void FixtureMetadataParserCases(){
    NSArray *cursors=@[@"",@"0",@"1",@"18446744073709551615",@"18446744073709551616",@"-1",@"+1",@"١"];
    NSArray *timeouts=@[@"",@"0",@"25000",@"25001",@"-1",@"x",@"99999999999999999999999999"];
    NSArray *limits=@[@"",@"1",@"32",@"33",@"0",@"-1"];
    NSArray *topics=@[@"",@"*",@"Ab09._-",@"a,b",@"a,,b",@"a*b",@"ảnh",@"😀",@"a\0b",
        [@"" stringByPaddingToLength:64 withString:@"A" startingAtIndex:0],[@"" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0],
        @"a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a",@"a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a,a"];
    for(unsigned n=0;n<2000;++n){
        @autoreleasepool{
            NSString *value=[NSString stringWithFormat:@"%@;;%@;;%@;;%@",cursors[n%cursors.count],timeouts[(n/3)%timeouts.count],limits[(n/7)%limits.count],topics[(n/11)%topics.count]];
            NSString *oldError=nil,*error=nil;NSDictionary *old=FixtureBeforeParseBody(value,&oldError),*actual=TLinkEventParseBody(value,&error);
            EVENT_METADATA_REQUIRE([old isEqual:actual]&&(oldError==error||[oldError isEqual:error]));
        }
    }
    for(NSString *topic in topics){
        NSString *value=[@"0;;0;;1;;" stringByAppendingString:topic],*oldError=nil,*error=nil;
        EVENT_METADATA_REQUIRE([FixtureBeforeParseBody(value,&oldError) isEqual:TLinkEventParseBody(value,&error)]&&(oldError==error||[oldError isEqual:error]));
    }
}
static void FixtureMetadataJournalPools(){
    NSMutableArray *events=[NSMutableArray array];for(unsigned n=1;n<=256;++n)[events addObject:fixtureStoredEvent(n)];
    EVENT_METADATA_REQUIRE([fixtureJournalData(fixtureJournal(257,events)) writeToFile:TLinkEventJournalPath() atomically:YES]);
    NSDictionary *before=nil,*actual=nil;
    for(bool modern:{false,true}){
        @autoreleasepool{
            const int fd=TLinkEventAcquireFileLock(YES,NO);EVENT_METADATA_REQUIRE(fd>=0);
            TLinkAXFixtureResetOwners();fixtureMetadataIntegerOwners=true;NSString *error=nil;
            NSDictionary *journal=modern?TLinkEventReadJournal(&error):FixtureBeforeReadJournal(&error);
            EVENT_METADATA_REQUIRE(journal&&!error&&TLinkAXFixtureCreatedOwners()==513);
            EVENT_METADATA_REQUIRE(modern?(TLinkAXFixtureLiveOwners()==1&&TLinkAXFixturePeakOwners()==3):TLinkAXFixtureLiveOwners()==513);
            fixtureMetadataIntegerOwners=false;TLinkEventReleaseFileLock(fd);if(modern)actual=journal;else before=journal;
        }
        EVENT_METADATA_REQUIRE(TLinkAXFixtureLiveOwners()==0);
    }
    EVENT_METADATA_REQUIRE([actual isEqual:before]);
    for(bool modern:{false,true}){
        @autoreleasepool{
            const int fd=TLinkEventAcquireFileLock(NO,NO);EVENT_METADATA_REQUIRE(fd>=0);
            TLinkAXFixtureResetOwners();fixtureTrackPreparationOwners=true;
            BOOL ok=modern?TLinkEventWriteJournal(actual):FixtureBeforeWriteJournal(actual);
            EVENT_METADATA_REQUIRE(ok&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureLiveOwners()==(modern?0U:1U));
            fixtureTrackPreparationOwners=false;TLinkEventReleaseFileLock(fd);
        }
        EVENT_METADATA_REQUIRE(TLinkAXFixtureLiveOwners()==0);
    }
}
static void FixtureMetadataQueuedBegin(){
    dispatch_queue_t queue=TLinkEventOwnerQueue();
    for(unsigned n=0;n<3;++n){
        dispatch_semaphore_t entered=dispatch_semaphore_create(0),release=dispatch_semaphore_create(0);
        dispatch_async(queue,^{dispatch_semaphore_signal(entered);assert(dispatch_semaphore_wait(release,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);});
        EVENT_METADATA_REQUIRE(dispatch_semaphore_wait(entered,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        __block NSDictionary *held=nil;__block NSString *failure=nil;__block unsigned calls=0;
        TLinkEventPollRequest *request=nil;
        @autoreleasepool{
            TLinkAXFixtureResetOwners();fixtureMetadataParserOwners=true;
            request=TLinkEventChannelBeginPoll(n==1?@"0;;0;;1;;ảnh":@"256;;0;;1;;*",nil,^(TLinkEventPollRequest *,NSDictionary *batch,NSString *error){held=batch;failure=error;++calls;});
            EVENT_METADATA_REQUIRE(request&&TLinkAXFixtureCreatedOwners()==1&&TLinkAXFixtureLiveOwners()==0);fixtureMetadataParserOwners=false;
        }
        if(n==2)[request cancel];
        dispatch_semaphore_signal(release);dispatch_sync(queue,^{});
        if(n==0)EVENT_METADATA_REQUIRE(calls==1&&held&&!failure&&[held[@"timed_out"] boolValue]);
        if(n==1)EVENT_METADATA_REQUIRE(calls==1&&!held&&[failure isEqual:@"event_topic_invalid"]);
        if(n==2)EVENT_METADATA_REQUIRE(calls==0&&request.isCancelled);
        EVENT_METADATA_REQUIRE(sTLinkEventActivePolls==0&&TLinkAXFixtureLiveOwners()==0);
    }
}
static NSArray *FixtureMetadataSweepPools(bool modern){
    __block NSArray *held=nil;
    dispatch_sync(TLinkEventOwnerQueue(),^{
        @autoreleasepool{
            EVENT_METADATA_REQUIRE(!sTLinkEventWaiters.count&&sTLinkEventActivePolls==0);fixtureBeforeFingerprint=nil;
            NSMutableArray *batches=[NSMutableArray array];
            for(unsigned n=0;n<8;++n){
                TLinkEventPendingPoll *request=[TLinkEventPendingPoll new];request->lease=std::make_shared<TLinkEventPollLease>(sTLinkEventActivePolls,8);
                request->authorized=YES;request->started=0;request->timeout=0;request->cursor=256;request->limit=1;request->topics=[NSSet set];
                request->completion=[^(TLinkEventPollRequest *,NSDictionary *batch,NSString *error){
                    assert(batch&&!error);TLinkAXFixtureAutoreleaseOwner();[batches addObject:batch];
                } copy];[sTLinkEventWaiters addObject:request];
            }
            TLinkAXFixtureResetOwners();if(modern)TLinkEventSweep(YES);else FixtureBeforeSweep(YES);
            EVENT_METADATA_REQUIRE(batches.count==8&&TLinkAXFixtureCreatedOwners()==8&&sTLinkEventActivePolls==0&&!sTLinkEventWaiters.count);
            EVENT_METADATA_REQUIRE(modern?(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixturePeakOwners()==1):TLinkAXFixtureLiveOwners()==8);
            held=[batches copy];fixtureBeforeFingerprint=nil;
        }
        EVENT_METADATA_REQUIRE(TLinkAXFixtureLiveOwners()==0&&!sTLinkEventSnapshot&&!sTLinkEventFingerprint);
    });
    return held;
}
static void fixtureEventMetadataCases(){
    fputs("Event metadata Foundation: actual/frozen stamps, permission repairs/parser and real journal/queue/MRC owners\n",stderr);
    NSString *path=TLinkEventJournalPath();NSData *saved=[NSData dataWithContentsOfFile:path];const bool savedNotify=suppressNotify;suppressNotify=true;
    FixtureMetadataFingerprintCases();FixtureMetadataPermissionCases();FixtureMetadataParserCases();FixtureMetadataJournalPools();FixtureMetadataQueuedBegin();
    NSArray *before=FixtureMetadataSweepPools(false),*actual=FixtureMetadataSweepPools(true);EVENT_METADATA_REQUIRE([before isEqual:actual]);
    if(saved)EVENT_METADATA_REQUIRE([saved writeToFile:path atomically:YES]);else EVENT_METADATA_REQUIRE([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
    suppressNotify=savedNotify;
    EVENT_METADATA_REQUIRE(!fixtureLiveEventFds&&!fixtureLiveJournalFds&&fixtureEventLocks.empty()&&sTLinkEventActivePolls==0);
    puts("Event metadata passed: 5000 frozen stat/errno stamps, real replace/delete, 128x6 permission/failure states and zero warm repairs, 2000 parser comparisons, 513-to3 journal numeric witness peak, encoding retirement, held-queue begin/cancel and eight-waiter callback peak1 versus8. Native expectations; device metadata/CPU/RSS remains unqualified.");
}
#undef EVENT_METADATA_REQUIRE
