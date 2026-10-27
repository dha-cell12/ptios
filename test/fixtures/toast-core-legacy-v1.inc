// Frozen df1283d toast compatibility oracle.
void showToastFromRawData(UInt8 *eventData, NSError **error)
{
    @autoreleasepool{
        NSArray *data = [[NSString stringWithFormat:@"%s", eventData] componentsSeparatedByString:@";;"];
        if ([data count] < 3)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;The data format should be \"type;;content;;duration(in seconds)[];;position(0: top, 1: bottom, 2: left, 3: right)]\". For example, 0;;success;;1.5;;0.\r\n"}];
            return;
        }
        int type = [data[0] intValue];
        int duration = [data[2] intValue];
        int position = 0;
        int fontSize = 0;
        if ([data count] >= 4)
        {
            position = [data[3] intValue];
        }
        if ([data count] >= 5)
        {
            fontSize = [data[4] intValue];
        }

        if (type > 4 || type < 0)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unknown type. The type ranges from 0-3. Please refer to the documentation on Github.\r\n"}];
            return;
        }
        if (duration <= 0 && type != 0)
        {
            *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Duration should be a positive float number.\r\n"}];
            return;
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            if (type == 0)
                [Toast hideToast];
            else
                [Toast showToastWithContent:data[1] type:type duration:duration position:position fontSize:fontSize];
        });
    }
}

