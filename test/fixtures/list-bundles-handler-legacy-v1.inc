// Frozen 68cd857 listBundles compatibility oracle.
    else if (taskType == TASK_LIST_BUNDLES)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = listBundlesFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
