void POCLogf(const char *fmt, ...)
{
    char msg[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, args);
    va_end(args);

    NSLog(@"[poc-touch] %s", msg);

    @autoreleasepool {
        NSString *path = POCLogFilePath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:YES];
        }
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });
        NSString *line = [NSString stringWithFormat:@"%@ %s\n", [df stringFromDate:[NSDate date]], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {}
        @try { [fh closeFile]; } @catch (__unused NSException *e) {}
    }
}

