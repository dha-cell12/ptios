static BOOL TLinkEventWriteJournal(NSDictionary *journal)
{
    if (![NSJSONSerialization isValidJSONObject:journal]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:journal options:0 error:nil];
    NSString *path = TLinkEventJournalPath();
    if (!data || data.length > kTLinkEventJournalMaxBytes || ![data writeToFile:path atomically:YES]) return NO;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    return YES;
}

