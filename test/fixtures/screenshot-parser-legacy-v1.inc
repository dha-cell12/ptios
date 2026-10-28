// Frozen a97c1b0 screenshot album compatibility oracle.
NSString* handleScreenshotTaskFromRawData(UInt8 *eventData, NSError **error)
{
    NSArray *data = [[NSString stringWithUTF8String:(char*)eventData] componentsSeparatedByString:@";;"];
    if ([data count] < 1)
    {
        if (error)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                         code:999
                                     userInfo:@{NSLocalizedDescriptionKey:@"-1;;Screenshot task missing action.\r\n"}];
        }
        return nil;
    }

    int action = [data[0] intValue];
    if (action == SCREENSHOT_TASK_CAPTURE || action == kTLinkOwnedCaptureAction)
    {
        if ([data count] < 2)
        {
            if (error)
            {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:@"-1;;Screenshot task missing output path.\r\n"}];
            }
            return nil;
        }

        NSString *filePath = data[1];
        if(action==kTLinkOwnedCaptureAction){
            auto owner=TLinkCaptureReceiverSlot();
            if([data count]!=2||!owner||!owner->matches(filePath.UTF8String)||!owner->valid()){
                if(error)*error=[NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;owned_capture_requires_ipc_lease\r\n"}];return nil;
            }
        }
        CGRect region = CGRectZero;
        if ([data count] >= 6)
        {
            CGFloat x = [data[2] floatValue];
            CGFloat y = [data[3] floatValue];
            CGFloat width = [data[4] floatValue];
            CGFloat height = [data[5] floatValue];
            region = CGRectMake(x, y, width, height);
        }

        return [Screen screenShotToPath:filePath region:region error:error];
    }
    else if (action == SCREENSHOT_TASK_SAVE_TO_ALBUM)
    {
        if ([data count] < 2)
        {
            if (error)
            {
                *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                             code:999
                                         userInfo:@{NSLocalizedDescriptionKey:@"-1;;Save to album missing file path.\r\n"}];
            }
            return nil;
        }

        [Screen saveToSystemAlbum:data[1] error:error];
        return nil;
    }
    else if (action == SCREENSHOT_TASK_CLEAR_ALBUM)
    {
        [Screen clearSystemAlbum:error];
        return nil;
    }

    if (error)
    {
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp"
                                     code:999
                                 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unknown screenshot action.\r\n"}];
    }
    return nil;
}
