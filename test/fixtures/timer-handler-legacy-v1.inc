// Frozen 5025221 timer compatibility oracle.
    else if (taskType == TASK_SET_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            setTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_REMOVE_TIMER)
    {
        @autoreleasepool {
            NSError *err = nil;
            removeTimerFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
