// Frozen de4e01f RAW task 44/45/46 response bodies after ordinary entry gates.
    else if (taskType == TASK_ROOT_DIR)
    {
        @autoreleasepool {
            NSString *path = rootDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_CURRENT_DIR)
    {
        @autoreleasepool {
            NSString *path = currentDirValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
    else if (taskType == TASK_BOT_PATH)
    {
        @autoreleasepool {
            NSString *path = botPathValue();
            notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", path] UTF8String], writeStreamRef);
        }
    }
