static NSDictionary *TLinkEventBoundedPayload(NSDictionary *payload)
{
    if (![payload isKindOfClass:[NSDictionary class]] ||
        ![NSJSONSerialization isValidJSONObject:payload]) return @{};
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (data.length <= kTLinkEventPayloadMaxBytes) return payload;
    return @{
        @"truncated": @true,
        @"original_bytes": @(data.length),
        @"reason": @"event_payload_limit",
    };
}

