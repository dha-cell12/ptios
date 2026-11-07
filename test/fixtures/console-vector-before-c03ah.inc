- (uint64_t)writeConsoleBatch:(const std::vector<std::shared_ptr<TLinkConsoleLogEntry>> &)batch toConsolePath:(NSString *)path {
    if(![path isKindOfClass:[NSString class]]||!path.length)return TLinkConsoleLogBatchMask(0,batch.size());
    uint64_t failed=0;
    for(size_t begin=0;begin<batch.size();){
        size_t count=1;
        BOOL written=NO;
        @autoreleasepool {
        @try {try {
            const uint64_t bytes=[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
            // An already-oversize file uses the original one-line rotation path,
            // including its behavior when remove fails. Replan the next group.
            if(bytes<=kTLinkautoJSMaxConsoleLogBytes)
                count=TLinkConsoleLogBatchCount(bytes,kTLinkautoJSMaxConsoleLogBytes,batch.size()-begin,[&batch,begin](size_t n){return batch[begin+n]->data.length;});
            NSData *data=batch[begin]->data;
            if(count>1){
                NSMutableData *joined=[NSMutableData data];
                for(size_t n=0;n<count;++n)[joined appendData:batch[begin+n]->data];
                data=joined;
            }
            written=[self appendConsoleData:data toConsolePath:path];
        }catch(...) {}} @catch(__unused NSException *exception) {}
        }
        // A failed group is not replayed: it may already have written bytes.
        if(!written)failed|=TLinkConsoleLogBatchMask(begin,count);
        begin+=count;
    }
    return failed;
}

- (BOOL)emitConsoleSystemLog:(const TLinkConsoleLogEntry &)entry {
    @try {try {
        NSLog(@"com.tlinkauto.jsruntime[%@][%@]: %@",entry.runId?:@"",entry.systemLevel,entry.systemMessage);
        return YES;
    }catch(...) {}} @catch(__unused NSException *exception) {}
    return NO;
}

