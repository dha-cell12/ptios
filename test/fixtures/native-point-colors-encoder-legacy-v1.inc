// Frozen Foundation point-color encoder from 30789db; compatibility oracle only.
static NSString *TLinkautoJSEncodePointColorTable(NSArray *points)
{
    if (![points isKindOfClass:[NSArray class]] || [points count] == 0 || [points count] > 512) return nil;
    NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
    for (id item in points) {
        if (![item isKindOfClass:[NSDictionary class]]) return nil;
        NSDictionary *dict = (NSDictionary *)item;
        double x = [dict[@"x"] doubleValue];
        double y = [dict[@"y"] doubleValue];
        int r = [dict[@"red"] respondsToSelector:@selector(intValue)] ? [dict[@"red"] intValue] : [dict[@"r"] intValue];
        int g = [dict[@"green"] respondsToSelector:@selector(intValue)] ? [dict[@"green"] intValue] : [dict[@"g"] intValue];
        int b = [dict[@"blue"] respondsToSelector:@selector(intValue)] ? [dict[@"blue"] intValue] : [dict[@"b"] intValue];
        if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return nil;
        [encoded addObject:[NSString stringWithFormat:@"%.0f,,%.0f,,%d,,%d,,%d", x, y, r, g, b]];
    }
    return [encoded componentsJoinedByString:@"|"];
}

