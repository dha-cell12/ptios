static void TLinkScriptAppendLog(TLinkScriptSession *session, NSString *line)
{
    if (!session || line.length == 0) return;
    NSString *entry = [NSString stringWithFormat:@"%llu %@", TLinkNowMs(), line];
    @synchronized (session) {
        if (!session.logs) session.logs = [NSMutableArray array];
        [session.logs addObject:entry];
        while (session.logs.count > 200) {
            [session.logs removeObjectAtIndex:0];
        }
    }
    POCLogf("script[%s]: %s", [session.sessionId UTF8String], [line UTF8String]);
}

