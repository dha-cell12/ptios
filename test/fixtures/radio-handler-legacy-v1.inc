// Frozen aed36da radio compatibility oracle (unchanged in C02b37).
    else if (taskType == TASK_WIFI)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = wifiTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
    else if (taskType == TASK_BLUETOOTH)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *state = bluetoothTaskFromRawData(eventData, &err);
            if (err) {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            } else {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", state ?: @"0"] UTF8String], writeStreamRef);
            }
        }
    }
