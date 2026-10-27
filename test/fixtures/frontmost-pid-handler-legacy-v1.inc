// Frozen e5a4acb frontmost PID compatibility oracle.
    else if (taskType == TASK_FRONTMOST_PID)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *pid = frontMostPidFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", pid ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
