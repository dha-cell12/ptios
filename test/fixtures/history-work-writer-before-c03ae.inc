static BOOL TLinkRunHistoryWriteJSON(id object, NSString *path, NSJSONWritingOptions options = NSJSONWritingPrettyPrinted)
{
    if (![NSJSONSerialization isValidJSONObject:object] || path.length == 0) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:options error:nil];
    if (!data || ([path isEqualToString:TLinkRunHistoryIndexPath()] && data.length > kTLinkRunHistoryIndexMaxBytes) ||
        ![data writeToFile:path atomically:YES]) return NO;
    chmod(path.fileSystemRepresentation, 0640);
    lchown(path.fileSystemRepresentation, 501, 501);
    return YES;
}

