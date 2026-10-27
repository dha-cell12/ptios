// Frozen b6f5dae clipboard text compatibility oracle.
    else if (taskType == TASK_TEXT_INPUT)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *result = inputTextFromRawData(eventData,  &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", result] UTF8String], writeStreamRef);
            }
        }
    }
