static NSString *TLinkJSFileNormalizeMode(NSString *mode)
{
    NSString *value = [[mode ?: @"r" lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isEqualToString:@"r+b"]) return @"rb+";
    if ([value isEqualToString:@"w+b"]) return @"wb+";
    if ([value isEqualToString:@"a+b"]) return @"ab+";
    return value;
}

BOOL TLinkJSFileModeIsValid(NSString *mode)
{
    NSString *value = TLinkJSFileNormalizeMode(mode);
    static NSSet<NSString *> *validModes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        validModes = [NSSet setWithArray:@[
            @"r", @"rb", @"r+", @"rb+",
            @"w", @"wb", @"w+", @"wb+",
            @"a", @"ab", @"a+", @"ab+",
        ]];
    });
    return [validModes containsObject:value];
}

