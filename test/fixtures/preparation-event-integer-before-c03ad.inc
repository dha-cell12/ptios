static BOOL TLinkEventJournalInteger(id value, uint64_t *result)
{
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    NSString *text = [value stringValue];
    if (text.length == 0) return NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return TLinkEventParseUnsignedCursor(text, result);
}

