static void consoleVectorRuntimeCases(NSString *root){
    puts("Console vector Foundation: actual/frozen batch writers, real writev/POSIX files and controlled short/error delivery");fflush(stdout);
    TLinkJSRuntimeCore *logger=[TLinkJSRuntimeCore new];
    std::vector<std::shared_ptr<TLinkConsoleLogEntry>> batch;
    NSMutableData *expected=[NSMutableData data];
    for(unsigned n=0;n<64;++n){
        NSData *data=[[NSString stringWithFormat:@"%u ảnh 测试 😀\r\n",n] dataUsingEncoding:NSUTF8StringEncoding];
        batch.push_back(std::make_shared<TLinkConsoleLogEntry>(data,@"",@"",@"vector",@"warn",@"message",nullptr));[expected appendData:data];
    }
    NSString *beforePath=[root stringByAppendingPathComponent:@"vector-before.log"],*path=[root stringByAppendingPathComponent:@"vector-now.log"];
    for(size_t limit:{size_t(1),size_t(2),size_t(16),size_t(64)}){
        consoleVectorOverride=limit;consoleVectorMode=0;
        for(unsigned missing=0;missing<2;++missing){
            for(NSString *target in @[beforePath,path]){
                [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
                if(!missing)assert([[NSData data] writeToFile:target atomically:YES]);
            }
            consoleJoinedCount=consoleBeforeJoinedCount=0;consoleVectorCalls=0;
            assert([logger beforeWriteConsoleBatch:batch toConsolePath:beforePath]==0);
            assert(consoleBeforeJoinedCount==1&&consoleJoinedCount==0);
            if(!missing)for(const auto &entry:batch)consoleExpectedSpans.emplace_back((const uint8_t *)entry->data.bytes,entry->data.length);
            assert([logger writeConsoleBatch:batch toConsolePath:path]==0);
            consoleExpectedSpans.clear();
            assert([[NSData dataWithContentsOfFile:path] isEqual:expected]);
            assert([[NSData dataWithContentsOfFile:path] isEqual:[NSData dataWithContentsOfFile:beforePath]]);
            const size_t capacity=TLinkConsoleLogVectorCapacity();
            assert(consoleJoinedCount==missing&&consoleVectorCalls==(missing?0:(64+capacity-1)/capacity)&&consoleLive==0);
        }
    }
    consoleVectorOverride=0;
    for(unsigned mode=1;mode<=7;++mode){
        assert([[NSData data] writeToFile:path atomically:YES]);consoleVectorCalls=0;consoleVectorMode=mode;
        const uint64_t failed=[logger writeConsoleBatch:batch toConsolePath:path];
        NSData *actual=[NSData dataWithContentsOfFile:path];
        if(mode==1){assert(!failed&&[actual isEqual:expected]&&consoleVectorCalls>2);}
        else {
            assert(failed==UINT64_MAX);
            const NSUInteger length=mode==2?7:0;assert(actual.length==length);
            assert([actual isEqual:[expected subdataWithRange:NSMakeRange(0,length)]]);
            assert(consoleVectorCalls==(mode==2?2U:(mode==7?0U:1U)));
        }
        assert(consoleLive==0);{std::lock_guard<std::mutex> guard(consoleDescriptorMutex);assert(consoleDescriptors.empty());}
        consoleVectorMode=0;
        assert([[NSData data] writeToFile:path atomically:YES]);
        assert([logger writeConsoleBatch:batch toConsolePath:path]==0&&[[NSData dataWithContentsOfFile:path] isEqual:expected]);
    }
    // Drain knows both path outcomes independently, even after a committed
    // prefix. Existing after-close/one-path/rotation tests above remain live.
    TLinkJSRuntimeCore *drained=consoleStart([root stringByAppendingPathComponent:@"vector-drain"],@"vector-drain");
    [drained holdWriter];for(unsigned n=0;n<8;++n)[drained appendConsoleLogWithLevel:@"log" message:@"partial failure"];
    consoleVectorMode=2;consoleVectorCalls=0;[drained resumeWriter];[drained finishConsoleLogging];consoleVectorMode=0;
    assert([[drained currentConsoleLogStats][@"writeFailures"] intValue]==8&&[[drained currentConsoleLogStats][@"pendingLines"] intValue]==0&&consoleLive==0);
    // MRC witnesses measure only explicit pending temporary owners supplied by
    // the sink. They do not estimate Foundation allocations, bytes or RSS.
    for(unsigned fault=0;fault<3;++fault){
        TLinkAXFixtureResetOwners();consoleTrackSystemOwners=true;consoleSystemFault=fault;
        @autoreleasepool {
            for(unsigned n=0;n<64;++n){const BOOL ok=[logger beforeEmitConsoleSystemLog:*batch[n]];assert(ok==(fault==0));}
            assert(TLinkAXFixtureLiveOwners()==64&&TLinkAXFixturePeakOwners()==64);
        }
        assert(TLinkAXFixtureLiveOwners()==0&&TLinkAXFixtureDroppedOwners()==64);
        TLinkAXFixtureResetOwners();
        @autoreleasepool {
            for(unsigned n=0;n<64;++n){const BOOL ok=[logger emitConsoleSystemLog:*batch[n]];assert(ok==(fault==0)&&TLinkAXFixtureLiveOwners()==0);}
            assert(TLinkAXFixturePeakOwners()==1);
        }
        assert(TLinkAXFixtureDroppedOwners()==64);consoleTrackSystemOwners=false;consoleSystemFault=0;consoleTakeSystemRecords();
    }
    {std::lock_guard<std::mutex> guard(consoleDescriptorMutex);assert(consoleDescriptors.empty());}
    puts("Console vector Foundation passed: frozen bytes, direct source spans, host vector caps, atomic missing-file fallback, partial/EINTR/zero/EIO/over-return/NS/C++/invalid-fd recovery, failed-prefix admission cleanup and normal sink pool peak 1 versus 64 MRC owners. Foundation/device memory and latency remain unqualified.");
}
