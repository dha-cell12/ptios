// C03x: actual descriptor reads versus frozen stable-file tails and controlled races.
static void historyConsoleTailCases(){
    fputs("History console tail Foundation: fixed descriptor window, frozen formatting and real file races\n",stderr);
    NSString *path=[historyTestRoot stringByAppendingPathComponent:@"bounded-console.log"];
    NSData *tail=[@"\r\nlicense_key=console-secret\nBearer console-token\nảnh 测试\nlast\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray<NSData *> *corpus=[NSMutableArray array];
    for(NSUInteger length:{(NSUInteger)0,(NSUInteger)1,(NSUInteger)262143,(NSUInteger)262144,(NSUInteger)262145,(NSUInteger)786569}){
        NSMutableData *data=[NSMutableData dataWithLength:length];
        if(length)memset(data.mutableBytes,'x',length);
        if(length>=tail.length)memcpy((uint8_t *)data.mutableBytes+length-tail.length,tail.bytes,tail.length);
        [corpus addObject:data];
    }
    [corpus addObject:[@"\n\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [corpus addObject:[[@"line\rnext\n" stringByPaddingToLength:4000 withString:@"line\rnext\n" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding]];
    const uint8_t invalid[]={0xff,0xfe,'\n','x'};
    [corpus addObject:[NSData dataWithBytes:invalid length:sizeof(invalid)]];
    // A multibyte character straddling the fixed window remains invalid UTF8,
    // preserving the frozen empty-tail behavior instead of repairing text.
    NSMutableData *split=[[[@"é" stringByAppendingString:[@"x" stringByPaddingToLength:262143 withString:@"x" startingAtIndex:0]] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [corpus addObject:split];
    for(NSData *data in corpus){
        assert([data writeToFile:path atomically:YES]);
        NSArray *expected=Legacy::TLinkRunHistoryTailFromConsoleFile(path);
        const uint64_t before=historyConsoleBytes;
        NSArray *actual=Current::TLinkRunHistoryTailFromConsoleFile(path);
        assert([actual isEqual:expected]&&historyConsoleBytes-before==MIN(data.length,(NSUInteger)262144));
        assert(historyConsoleFds.empty()&&historyLocks.empty());
    }
    NSData *ordinary=[@"first\nlicense_key=console-secret\nlast\n" dataUsingEncoding:NSUTF8StringEncoding];
    assert([ordinary writeToFile:path atomically:YES]);
    NSArray *expected=Legacy::TLinkRunHistoryTailFromConsoleFile(path);
    for(unsigned fault=1;fault<=10;++fault){
        historyConsoleFault=fault;bool threw=false;NSArray *actual=nil;
        @try{try{actual=Current::TLinkRunHistoryTailFromConsoleFile(path);}catch(const std::runtime_error &){threw=true;}}
        @catch(__unused NSException *exception){assert(false);}
        historyConsoleFault=0;
        if(fault==3||fault==7)assert(!threw&&[actual isEqual:expected]);
        else if(fault==9||fault==10)assert(threw);
        else assert(!threw&&!actual.count);
        assert(historyConsoleFds.empty()&&historyLocks.empty());
    }
    // Growth after fstat must not extend the bytes read from the old window.
    NSMutableData *growth=[NSMutableData dataWithLength:2*1024*1024];memset(growth.mutableBytes,'g',growth.length);
    historyConsoleAfterStat=[path,growth](int){
        const int writer=::open(path.fileSystemRepresentation,O_WRONLY|O_APPEND);assert(writer>=0);
        size_t offset=0;while(offset<growth.length){ssize_t got=::write(writer,(const uint8_t *)growth.bytes+offset,growth.length-offset);if(got<0&&errno==EINTR)continue;assert(got>0);offset+=(size_t)got;}
        assert(::close(writer)==0);
    };
    uint64_t before=historyConsoleBytes;
    assert([Current::TLinkRunHistoryTailFromConsoleFile(path) isEqual:expected]);historyConsoleAfterStat={};
    assert(historyConsoleBytes-before==ordinary.length&&historyConsoleFds.empty());
    // Replacing the pathname after fstat does not replace the admitted descriptor.
    assert([ordinary writeToFile:path atomically:YES]);NSString *saved=[path stringByAppendingString:@".saved"];
    historyConsoleAfterStat=[path,saved,growth](int){assert(::rename(path.fileSystemRepresentation,saved.fileSystemRepresentation)==0&&[growth writeToFile:path atomically:YES]);};
    assert([Current::TLinkRunHistoryTailFromConsoleFile(path) isEqual:expected]);historyConsoleAfterStat={};
    assert(historyConsoleFds.empty()&&::unlink(saved.fileSystemRepresentation)==0);
    // Truncation/early EOF discards the incomplete window and closes the reader.
    assert([ordinary writeToFile:path atomically:YES]);
    historyConsoleAfterStat=[path](int){const int writer=::open(path.fileSystemRepresentation,O_WRONLY);assert(writer>=0&&::ftruncate(writer,0)==0&&::close(writer)==0);};
    assert(!Current::TLinkRunHistoryTailFromConsoleFile(path).count);historyConsoleAfterStat={};assert(historyConsoleFds.empty());
    // Refuse special leaves and symlinks without a payload read/allocation.
    NSFileManager *fm=[NSFileManager defaultManager];NSString *target=[path stringByAppendingString:@".target"];
    assert([ordinary writeToFile:target atomically:YES]);
    for(unsigned kind=0;kind<4;++kind){
        assert([fm removeItemAtPath:path error:nil]);
        if(kind==0)assert(::symlink(target.fileSystemRepresentation,path.fileSystemRepresentation)==0);
        if(kind==1)assert(::mkfifo(path.fileSystemRepresentation,0600)==0);
        if(kind==2)assert([fm createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:nil]);
        const size_t reads=historyConsoleReads,allocations=historyConsoleAllocations;
        assert(!Current::TLinkRunHistoryTailFromConsoleFile(path).count);
        assert(historyConsoleReads==reads&&historyConsoleAllocations==allocations&&historyConsoleFds.empty());
        // Restore an ordinary leaf so each next iteration starts the same way.
        if(kind<3)assert([fm removeItemAtPath:path error:nil]);
        assert([ordinary writeToFile:path atomically:YES]);
    }
    // Public failed finish still persists the redacted tail; supplied lines skip file IO.
    NSString *savedRoot=Current::fixtureRoot;const BOOL savedReady=Current::sTLinkRunHistoryRecovered;
    Current::fixtureRoot=[historyTestRoot stringByAppendingPathComponent:@"console-tail-history"];
    NSDictionary *done=Current::TLinkRunHistoryFinish(@"console-tail",@"failed",@"failure",@[],path,@"",nil,@{});
    assert([done[@"failure_evidence"][@"log_tail"] isEqual:expected]);
    for(unsigned fault:{4U,6U,8U}){
        historyConsoleFault=fault;
        NSDictionary *emptyTail=Current::TLinkRunHistoryFinish(@"console-tail-error",@"failed",@"original failure",@[],path,@"",nil,@{});
        historyConsoleFault=0;
        assert(emptyTail.count&&![emptyTail[@"failure_evidence"][@"log_tail"] count]&&[emptyTail[@"error"] isEqualToString:@"original failure"]);
        assert(historyConsoleFds.empty()&&historyLocks.empty());
    }
    const size_t reads=historyConsoleReads;
    assert(Current::TLinkRunHistoryFinish(@"supplied-tail",@"failed",@"failure",@[@"supplied"],path,@"",nil,@{}).count);
    assert(historyConsoleReads==reads&&historyConsoleFds.empty()&&historyLocks.empty());
    Current::fixtureRoot=savedRoot;Current::sTLinkRunHistoryRecovered=savedReady;
    puts("History console tail passed: frozen byte/UTF8/redaction/newline/limit parity, <=256-KiB actual reads, EINTR/short/error/EOF/allocation/NS/C++ unwind, real append/rename/truncate, special-leaf refusal and public evidence/supplied-tail paths. Device IO latency remains unqualified.");
}
