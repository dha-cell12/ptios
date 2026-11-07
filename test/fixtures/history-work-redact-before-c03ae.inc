static NSString *TLinkRunHistoryRedactText(NSString *value)
{
    NSString *text = [value isKindOfClass:[NSString class]] ? value : @"";
    NSArray<NSRegularExpression *> *patterns = TLinkRunHistoryRedactionPatterns();
    for (NSUInteger index = 0; index < patterns.count; index++) {
        NSRegularExpression *regex = patterns[index];
        NSString *replacement = index == 0 ? @"$1=[REDACTED]" : @"Bearer [REDACTED]";
        text = [regex stringByReplacingMatchesInString:text
                                                options:0
                                                  range:NSMakeRange(0, text.length)
                                           withTemplate:replacement];
    }
    return text;
}

