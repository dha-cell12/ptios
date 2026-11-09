static NSDictionary *batchLogTrace(bool before,size_t initial,size_t chunk,size_t vectorLimit){
    resetFile();NSMutableData *prefix=[NSMutableData dataWithLength:initial];assert([prefix writeToFile:logPath atomically:YES]);
    const size_t opens=ioOpens,closes=ioCloses,stats=ioStats,vectors=ioVectors;
    vectorLimitOverride=vectorLimit;maxWrite=chunk;
    @autoreleasepool {
        for(unsigned n=0;n<64;++n){if(before)BeforeLogBatch::POCLogf("batch %02u %s",n,"ảnh");else POCLogf("batch %02u %s",n,"ảnh");}
    }
    drain();maxWrite=SIZE_MAX;vectorLimitOverride=0;
    assert(descriptors.empty()&&POCLogGetStatistics().pending==0&&BeforeLogBatch::POCLogGetStatistics().pending==0);
    return @{@"file":[NSData dataWithContentsOfFile:logPath],@"system":[messages copy],
        @"opens":@(ioOpens-opens),@"closes":@(ioCloses-closes),@"stats":@(ioStats-stats),@"vectors":@(ioVectors-vectors)};
}
static void batchByteCases(){
    for(size_t initial:{size_t(0),size_t(1048576),size_t(1048570),size_t(1048500),size_t(1048000),size_t(1048577)}){
        for(size_t limit:{size_t(1),size_t(2),size_t(64)}){
            for(size_t chunk:{SIZE_MAX,size_t(7)}){
                @autoreleasepool {
                    NSDictionary *old=batchLogTrace(true,initial,chunk,limit),*now=batchLogTrace(false,initial,chunk,limit);
                    assert([old[@"file"] isEqual:now[@"file"]]&&[old[@"system"] isEqual:now[@"system"]]);
                    assert([old[@"opens"] unsignedIntValue]==64&&[old[@"closes"] unsignedIntValue]==64);
                    assert([now[@"opens"] unsignedIntValue]==1&&[now[@"closes"] unsignedIntValue]==1&&[now[@"stats"] unsignedIntValue]==1);
                    if(!initial&&chunk==SIZE_MAX&&limit==64)assert([now[@"vectors"] unsignedLongLongValue]==(64+POCLogVectorLimit()-1)/POCLogVectorLimit());
                }
            }
        }
    }
}
static void batchFaultCases(){
    // A failed vectored write never replays an acknowledged prefix. Retire the
    // full uncertain group; a later independent batch can recover normally.
    resetFile();failAfter=11;
    auto before=POCLogGetStatistics();for(unsigned n=0;n<8;++n)POCLogf("file fault %u",n);drain();failAfter=-1;
    NSData *partial=[NSData dataWithContentsOfFile:logPath];assert(partial.length==11);
    assert(POCLogGetStatistics().fileFailures==before.fileFailures+8&&messages.count==8);
    POCLogf("recovery");drain();NSData *recovered=[NSData dataWithContentsOfFile:logPath];
    assert(recovered.length>11&&memcmp(recovered.bytes,partial.bytes,11)==0&&POCLogGetStatistics().pending==0);
    // Rollback a failed producer while older registered work is still pending.
    resetFile();POCLogf("kept before");enqueueMode=1;POCLogf("must not emit");enqueueMode=0;POCLogf("kept after");drain();
    assert(messages.count==2&&[[messages componentsJoinedByString:@"|"] rangeOfString:@"must not emit"].location==NSNotFound);
    // Discard one admitted block before its drain, then retain already consumed
    // blocks across the first drain. Weak registration must not duplicate work.
    resetFile();for(unsigned n=0;n<8;++n)POCLogf("discard %u",n);
    @autoreleasepool {@synchronized(queued){[queued removeObjectAtIndex:3];}}
    drain();assert(messages.count==7&&POCLogGetStatistics().pending==0);
    resetFile();for(unsigned n=0;n<8;++n)POCLogf("retained %u",n);
    dispatch_block_t first=nil;
    @autoreleasepool {
        @synchronized(queued){first=(dispatch_block_t)queued.firstObject;[queued removeObjectAtIndex:0];}
        first();assert(messages.count==8);first();assert(messages.count==8);drain();
        first=nil;
    }
    assert(POCLogGetStatistics().pending==0&&descriptors.empty());
}
static void batchRuntimeCases(){
    puts("Production file batching: complete C03av/current backends, actual weak registry and real checked vectors/files");
    batchByteCases();batchFaultCases();
    puts("Production file batch passed: 36 frozen raw/system/file comparisons, six reset boundaries, vector limits/short writes, 64-to-1 open/stat/close and host-clipped healthy writev, partial group refusal without replay, failed registration, discarded blocks, retained/no-op drains and recovery. Counts are fixture expectations; device IO/latency remain unqualified.");
}
