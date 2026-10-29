// Frozen TrollStore event legacy encoder from b8207e7a (C03r build passed).
static NSData *fixtureLegacyTrollEventBatchResponse(NSDictionary *batch, NSString *error)
{
    if (error.length) return [error hasPrefix:@"-1;;"] ? [error dataUsingEncoding:NSUTF8StringEncoding] : TLinkError(error);
    NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
    return json.length ? TLinkSuccess([json base64EncodedStringWithOptions:0]) : TLinkError(@"event_channel_json_failed");
}
