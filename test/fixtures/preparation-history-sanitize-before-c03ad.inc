static NSString *TLinkRunHistorySanitize(NSString *value)
{
    NSString *source = [value isKindOfClass:[NSString class]] ? value : @"";
    NSMutableString *safe = [NSMutableString stringWithCapacity:source.length];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
    for (NSUInteger i = 0; i < source.length && safe.length < 96; i++) {
        unichar c = [source characterAtIndex:i];
        [safe appendString:[allowed characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"_"];
    }
    return safe.length > 0 ? safe : @"run";
}

