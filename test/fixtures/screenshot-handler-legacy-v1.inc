// Frozen a97c1b0 screenshot album compatibility oracle.
    else if (taskType == TASK_SCREENSHOT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *resultPath = handleScreenshotTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else if (resultPath)
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", resultPath] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)"0\r\n", writeStreamRef);
            }
        }
    }
