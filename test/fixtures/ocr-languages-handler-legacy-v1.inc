// Frozen 86c0974 OCR languages compatibility oracle.
    else if (taskType == TASK_OCR_TESSERACT_REGION)
    {
        @autoreleasepool {
            NSError *err = nil;
            NSString *ret = handleTesseractOCRTaskFromRawData(eventData, &err);
            if (err)
            {
                notifyClient((UInt8*)[[err localizedDescription] UTF8String], writeStreamRef);
            }
            else
            {
                notifyClient((UInt8*)[[NSString stringWithFormat:@"0;;%@\r\n", ret ?: @""] UTF8String], writeStreamRef);
            }
        }
    }
