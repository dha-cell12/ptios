static NSDictionary *TLinkEventParseBody(NSString *body, NSString **error)
{
    NSArray<NSString *> *parts = [body.length > 0 ? body : @"" componentsSeparatedByString:@";;"];
    NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (parts.count > 4 ||
        (parts.count > 0 && [parts[0] rangeOfCharacterFromSet:notDigits].location != NSNotFound) ||
        (parts.count > 1 && ([parts[1] length] == 0 || [parts[1] rangeOfCharacterFromSet:notDigits].location != NSNotFound)) ||
        (parts.count > 2 && ([parts[2] length] == 0 || [parts[2] rangeOfCharacterFromSet:notDigits].location != NSNotFound))) {
        if (error) *error = @"event_request_invalid";
        return @{};
    }
    NSString *cursorText = parts.count > 0 ? parts[0] : @"";
    uint64_t cursor = 0;
    if (!TLinkEventParseUnsignedCursor(cursorText, &cursor)) {
        if (error) *error = @"event_request_invalid";
        return @{};
    }
    NSInteger requestedTimeout = parts.count > 1 ? [parts[1] integerValue] : (NSInteger)kTLinkEventPollDefaultTimeoutMs;
    NSInteger requestedMax = parts.count > 2 ? [parts[2] integerValue] : (NSInteger)kTLinkEventPollDefaultMaxEvents;
    if (requestedTimeout < 0 || requestedTimeout > (NSInteger)kTLinkEventPollMaxTimeoutMs) {
        if (error) *error = @"event_timeout_out_of_range";
        return @{};
    }
    if (requestedMax < 1 || requestedMax > (NSInteger)kTLinkEventPollMaxEvents) {
        if (error) *error = @"event_max_events_out_of_range";
        return @{};
    }
    NSArray *topics = parts.count > 3 && [parts[3] length] > 0
        ? [parts[3] componentsSeparatedByString:@","] : @[@"*"];
    if (topics.count > 16) {
        if (error) *error = @"event_topic_limit_exceeded";
        return @{};
    }
    for (NSString *topic in topics) {
        NSData *bytes = [topic dataUsingEncoding:NSUTF8StringEncoding];
        if (!TLinkEventTopicValid((const char *)bytes.bytes, bytes.length)) {
            if (error) *error = @"event_topic_invalid";
            return @{};
        }
    }
    return @{@"cursor": @(cursor), @"timeout": @(requestedTimeout), @"limit": @(requestedMax), @"topics": topics};
}

