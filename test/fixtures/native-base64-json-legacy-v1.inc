// Frozen from 892d8de; former listBundles JSON consumer and base64 decoder.
static NSString *TLinkautoJSBase64Decode(NSString *text)
{
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:text options:0];
    if (!data) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static id TLinkautoJSBase64JSON(NSString *text)
{
    NSString *json = TLinkautoJSBase64Decode(text);
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return obj;
}
