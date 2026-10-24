// Frozen C02b5 JS compatibility branch, baseline 1d710aa; change only for an intentional wire-contract migration.
    else if ([method isEqualToString:TLinkJSNativeMethodFramePickColors]) {
        int frameId = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSArray *points = [args count] > 1 ? [args objectAtIndex:1] : @[];
        NSDictionary *options = [args count] > 2 ? [args objectAtIndex:2] : @{};
        if (frameId <= 0 || ![points isKindOfClass:[NSArray class]] || [points count] == 0) return [TLinkJSNativeResponse responseWithError:@"framePickColors(frameId, points) requires a frame id and non-empty points array" code:@-1];
        NSMutableArray<NSString *> *encoded = [NSMutableArray arrayWithCapacity:[points count]];
        for (id point in points) {
            double x = 0, y = 0;
            if ([point isKindOfClass:[NSArray class]] && [point count] >= 2) {
                NSArray *arrayPoint = (NSArray *)point;
                x = [arrayPoint[0] doubleValue];
                y = [arrayPoint[1] doubleValue];
            }
            else if ([point isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dictPoint = (NSDictionary *)point;
                x = [dictPoint[@"x"] doubleValue];
                y = [dictPoint[@"y"] doubleValue];
            }
            else return [TLinkJSNativeResponse responseWithError:@"framePickColors points must be [x,y] arrays or {x,y} objects" code:@-1];
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y)) return [TLinkJSNativeResponse responseWithError:@"framePickColors points require finite coordinates" code:@-1];
            [encoded addObject:[NSString stringWithFormat:@"%.0f,%.0f", x, y]];
        }
        NSString *coord = TLinkautoJSStringOption(options, @"coord", @"pixel");
        if (!TLinkautoJSValidToken(coord)) return [TLinkJSNativeResponse responseWithError:@"coord contains unsupported protocol delimiter" code:@-1];
        int maxAgeMs = TLinkautoJSIntOption(options, @"maxAgeMs", 1000);
        NSString *payload = [NSString stringWithFormat:@"%d;;pick_many;;%@;;%@;;%d", frameId, [encoded componentsJoinedByString:@"|"], coord, maxAgeMs];
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_IN_FRAME, payload] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 5) return [TLinkJSNativeResponse responseWithValue:result];
        NSMutableArray *colors = [NSMutableArray array];
        for (NSString *item in [TLinkautoJSSafeStringPart(parts, 1) componentsSeparatedByString:@"|"]) {
            NSArray *fields = [item componentsSeparatedByString:@","];
            if ([fields count] == 5) [colors addObject:@{@"x": @([fields[0] intValue]), @"y": @([fields[1] intValue]), @"red": @([fields[2] intValue]), @"green": @([fields[3] intValue]), @"blue": @([fields[4] intValue])}];
        }
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"colors": colors, @"ageMs": @([TLinkautoJSSafeStringPart(parts, 2) longLongValue]), @"totalMs": @([TLinkautoJSSafeStringPart(parts, 3) doubleValue])})];
    }
