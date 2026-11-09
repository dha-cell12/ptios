        auto entry=std::make_shared<TLinkConsoleLogEntry>(data,runPath,latestPath,runId,systemLevel,systemMessage,permit);
        os_unfair_lock_lock(&_logStateLock);
        @try {
            // Publish under the same lock that closes admission before drain.
            if(!_acceptingLogs||generation!=_logGeneration){_logBudget->dropped();return;}
            _logPending.push_back(entry);
            _logBudget->accepted(truncated);
            if(!_logDrainScheduled){
                _logDrainScheduled=YES;
                dispatch_async(_logQueue, ^{[self drainConsoleLogs];});
            }
        } @finally {os_unfair_lock_unlock(&_logStateLock);}
