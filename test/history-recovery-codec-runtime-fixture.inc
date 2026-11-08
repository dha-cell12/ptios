// Both complete current and C03aq histories use the same real POSIX/JSON adapters.
static void historyRecoveryCodecReset(){
    historyRecoveryEncodes=historyRecoveryDecodes=historyRecoveryBuffers=0;
    historyRecoveryFirstEncoding=nullptr;historyRecoveryWriteUsedFirst=false;
    [historyWriteAttempts removeAllObjects];
}
static BOOL historyRecoveryCodecCall(bool modern,NSDictionary *expected,NSString *path){
    NSObject *monitor=modern?Current::TLinkRunHistoryLock():BeforeRecoveryCodec::TLinkRunHistoryLock();
    @synchronized(monitor) {
    const int fd=modern?Current::TLinkRunHistoryAcquireFileLock():BeforeRecoveryCodec::TLinkRunHistoryAcquireFileLock();
    assert(fd>=0);
    @try {
        return modern?Current::TLinkRunHistoryRepairJSON(expected,path,@"codec"):
            BeforeRecoveryCodec::TLinkRunHistoryRepairJSON(expected,path,@"codec");
    } @finally {
        if(modern)Current::TLinkRunHistoryReleaseFileLock(fd);
        else BeforeRecoveryCodec::TLinkRunHistoryReleaseFileLock(fd);
    }
    }
}
static NSMutableData *historyRecoveryCodecDifferent(NSData *encoded){
    NSMutableData *changed=[encoded mutableCopy];
    NSData *needle=[@"origin-A" dataUsingEncoding:NSUTF8StringEncoding];
    const NSRange range=[changed rangeOfData:needle options:0 range:NSMakeRange(0,changed.length)];
    assert(range.location!=NSNotFound);
    ((uint8_t *)changed.mutableBytes)[range.location+needle.length-1]='B';return changed;
}
static void historyRecoveryCodecCases(){
    puts("History recovery codec Foundation: complete preceding/current repair, real JSON and POSIX files");
    NSString *saved=Current::fixtureRoot;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"recovery-codec-current"];
    BeforeRecoveryCodec::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"recovery-codec-before"];
    Current::TLinkRunHistoryEnsureDirectories();BeforeRecoveryCodec::TLinkRunHistoryEnsureDirectories();
    NSFileManager *fm=[NSFileManager defaultManager];
    for(unsigned cycle=0;cycle<16;++cycle){@autoreleasepool {
        // Single-key dictionaries give stable canonical byte order on every SDK.
        NSDictionary *input=@{@"payload":@[@"origin-A",@(cycle),@"ảnh\0测试😀",@YES,[NSNull null],
            @(INT64_MIN),@(UINT64_MAX),@(-0.0),@{@"nested":@[@1.25,@"quoted\"\n"]}]};
        NSData *initial=[NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
        NSDictionary *expected=[NSJSONSerialization JSONObjectWithData:initial options:NSJSONReadingMutableContainers error:nil];
        NSData *encoded=[NSJSONSerialization dataWithJSONObject:expected options:NSJSONWritingPrettyPrinted error:nil];assert(encoded.length>0);
        for(unsigned shape=0;shape<6;++shape){
            for(bool modern:{false,true}){
                NSString *root=modern?Current::fixtureRoot:BeforeRecoveryCodec::fixtureRoot;
                NSString *path=[[root stringByAppendingPathComponent:@"runs"] stringByAppendingPathComponent:@"record.json"];
                NSMutableData *bytes=[encoded mutableCopy];
                if(shape==1){
                    uint8_t *text=(uint8_t *)bytes.mutableBytes;NSUInteger newline=NSNotFound;
                    for(NSUInteger n=0;n<bytes.length;++n)if(text[n]=='\n'||text[n]=='\r'){newline=n;break;}
                    assert(newline!=NSNotFound);text[newline]='\t'; // Same graph/length, different formatting.
                }else if(shape==2)bytes=historyRecoveryCodecDifferent(encoded);
                else if(shape==3){const uint8_t space=' ';[bytes appendBytes:&space length:1];}
                else if(shape==5)memset(bytes.mutableBytes,'x',bytes.length);
                if(shape==4){if([fm fileExistsAtPath:path])assert([fm removeItemAtPath:path error:nil]);}
                else assert([bytes writeToFile:path atomically:YES]);
                historyRecoveryCodecReset();const size_t reads=historyRecoveryReads;
                assert(historyRecoveryCodecCall(modern,expected,path));
                const bool repaired=shape>=2;
                assert(historyWriteAttempts.count==(repaired?1U:0U));
                assert(historyRecoveryEncodes==(repaired&&!modern?2U:1U));
                assert(historyRecoveryBuffers==((shape==0&&modern)||shape==3||shape==4?0U:1U));
                assert(historyRecoveryDecodes==((shape==0&&modern)||shape==3||shape==4?0U:1U));
                if(repaired&&modern)assert(historyRecoveryWriteUsedFirst);
                if(shape==3||shape==4)assert(historyRecoveryReads==reads);
                NSData *stored=[NSData dataWithContentsOfFile:path];
                if(!repaired)assert([stored isEqual:bytes]);
                assert([[NSJSONSerialization JSONObjectWithData:stored options:0 error:nil] isEqual:expected]);
                assert(historyLocks.empty()&&historyRecoveryFds.empty()&&historyLockFds.empty());
            }
        }
    }}
    // A mismatch near the end of a multi-chunk file reconstructs the verified prefix.
    NSString *padding=[@"" stringByPaddingToLength:131089 withString:@"z" startingAtIndex:0];
    NSDictionary *large=@{@"payload":@[padding,@"origin-A"]};
    NSData *encoded=[NSJSONSerialization dataWithJSONObject:large options:NSJSONWritingPrettyPrinted error:nil];
    NSString *path=[[Current::fixtureRoot stringByAppendingPathComponent:@"runs"] stringByAppendingPathComponent:@"large.json"];
    assert([historyRecoveryCodecDifferent(encoded) writeToFile:path atomically:YES]);
    historyRecoveryCodecReset();assert(historyRecoveryCodecCall(true,large,path));
    assert(historyRecoveryBuffers==1&&historyRecoveryDecodes==1&&historyRecoveryEncodes==1&&historyRecoveryWriteUsedFirst);
    assert([[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil] isEqual:large]);
    // Real short reads after EINTR retain the exact path and need no fallback.
    historyRecoveryCodecReset();historyRecoveryReadFault=1;
    assert(historyRecoveryCodecCall(true,large,path));historyRecoveryReadFault=0;
    assert(!historyRecoveryBuffers&&!historyRecoveryDecodes&&!historyWriteAttempts.count&&historyRecoveryFds.empty());
    // Refusal/unwind after the first read never reaches the writer or leaks its FD/lock.
    for(unsigned fault=1;fault<=3;++fault){
        assert([historyRecoveryCodecDifferent(encoded) writeToFile:path atomically:YES]);
        historyRecoveryCodecReset();historyRecoveryBufferFault=fault;BOOL accepted=NO;bool caught=false;
        @try {try {accepted=historyRecoveryCodecCall(true,large,path);}catch(const std::runtime_error &){caught=true;}}
        @catch(NSException *exception){(void)exception;caught=true;}
        historyRecoveryBufferFault=0;
        assert(!accepted&&caught==(fault>=2)&&!historyWriteAttempts.count&&historyRecoveryFds.empty()&&historyLocks.empty()&&historyLockFds.empty());
        historyRecoveryCodecReset();assert(historyRecoveryCodecCall(true,large,path));
    }
    Current::fixtureRoot=saved;BeforeRecoveryCodec::fixtureRoot=nil;
    historyRecoveryCodecReset();
    puts("History recovery codec passed: 192 complete frozen/current exact/format/changed/size/missing/malformed cases, zero exact-file fallback buffers/parses, one versus two repair encodes, original-data writer identity, multi-chunk prefix recovery, short/EINTR reads, allocation refusal/NS/C++ unwind and balanced real descriptors/locks. Device timing/RSS unmeasured.");
}
