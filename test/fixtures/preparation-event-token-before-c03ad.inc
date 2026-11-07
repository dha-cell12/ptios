static NSString *TLinkEventToken(NSString *value, NSString *fallback)
{
    NSString *source = [value isKindOfClass:[NSString class]] ? value.lowercaseString : @"";
    NSMutableString *token = [NSMutableString string];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyz0123456789._-"];
    for (NSUInteger index = 0; index < source.length && token.length < 64; index++) {
        unichar c = [source characterAtIndex:index];
        if ([allowed characterIsMember:c]) [token appendFormat:@"%C", c];
    }
    return token.length > 0 ? token : fallback;
}

