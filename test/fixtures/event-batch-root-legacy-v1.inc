// Frozen root event legacy encoder from 0340a8e3 (C03q build passed).
static NSData *fixtureLegacyEventBatchResponse(NSDictionary *batch, NSString *error)
{
    if (error.length) {
        NSString *line = [error hasPrefix:@"-1;;"] ? error : [NSString stringWithFormat:@"-1;;%@\r\n", error];
        return zx_dataFromCString(line.UTF8String);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:batch options:0 error:nil];
    return json.length ? zx_dataFromCString([[NSString stringWithFormat:@"0;;%@\r\n", [json base64EncodedStringWithOptions:0]] UTF8String])
        : zx_dataFromCString("-1;;event_channel_json_failed\r\n");
}
