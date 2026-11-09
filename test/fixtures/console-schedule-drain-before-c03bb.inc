- (void)drainConsoleLogs {
    for(;;){
        std::vector<std::shared_ptr<TLinkConsoleLogEntry>> batch;
        os_unfair_lock_lock(&_logStateLock);
        if(_logPending.empty()){
            _logDrainScheduled=NO;
            os_unfair_lock_unlock(&_logStateLock);
            return;
        }
        batch.swap(_logPending);
        os_unfair_lock_unlock(&_logStateLock);
        @autoreleasepool {
            uint64_t failed=TLinkConsoleLogBatchMask(0,batch.size());
            @try {try {
                for(const auto &entry:batch)if(![self emitConsoleSystemLog:*entry])_logBudget->systemFailed();
                const uint64_t runFailed=[self writeConsoleBatch:batch toConsolePath:batch.front()->runPath];
                const uint64_t latestFailed=[self writeConsoleBatch:batch toConsolePath:batch.front()->latestPath];
                failed=runFailed|latestFailed;
            }catch(...) {}} @catch(__unused NSException *exception) {}
            @finally {
                for(size_t n=0;n<batch.size();++n){
                    if(failed&(uint64_t(1)<<n))_logBudget->failed();
                    auto permit=std::move(batch[n]->permit);
                    batch[n].reset(); // Retire the payload before reopening its slot.
                    permit->finish();
                }
            }
        }
    }
}

