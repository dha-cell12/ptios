// Frozen pre-C02b11 combined live color bridge at 6c9b095.
    else if ([method isEqualToString:TLinkJSNativeMethodIsColors] || [method isEqualToString:TLinkJSNativeMethodFindMultiColor]) {
        NSArray *points = [args count] > 0 ? [args objectAtIndex:0] : @[];
        NSDictionary *options = [args count] > 1 ? [args objectAtIndex:1] : @{};
        
        NSString *table=TLinkautoJSEncodePointColorTable(points);
        if(!table)return [TLinkJSNativeResponse responseWithError:@"requires 1-512 valid point colors" code:@-1];

        if ([method isEqualToString:TLinkJSNativeMethodIsColors]) {
            int mode = [options[@"mode"] respondsToSelector:@selector(intValue)] ? [options[@"mode"] intValue] : 1;
            double value = [options[@"value"] respondsToSelector:@selector(doubleValue)] ? [options[@"value"] doubleValue] : ([options[@"tolerance"] respondsToSelector:@selector(doubleValue)] ? [options[@"tolerance"] doubleValue] : 0);
            NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d2;;%@;;%d;;%.4f", TASK_COLOR_SEARCHER, table, mode, value] context:context];
            NSArray *parts = result[@"parts"];
            if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
            BOOL matched = [parts[1] intValue] != 0;
            NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
            res[@"matched"] = @(matched);
            res[@"value"] = @(matched);
            return [TLinkJSNativeResponse responseWithValue:res];
        } else {
            double x = [options[@"x"] respondsToSelector:@selector(doubleValue)] ? [options[@"x"] doubleValue] : 0;
            double y = [options[@"y"] respondsToSelector:@selector(doubleValue)] ? [options[@"y"] doubleValue] : 0;
            double width = [options[@"width"] respondsToSelector:@selector(doubleValue)] ? [options[@"width"] doubleValue] : 0;
            double height = [options[@"height"] respondsToSelector:@selector(doubleValue)] ? [options[@"height"] doubleValue] : 0;
            int mode = [options[@"mode"] respondsToSelector:@selector(intValue)] ? [options[@"mode"] intValue] : 1;
            double value = [options[@"value"] respondsToSelector:@selector(doubleValue)] ? [options[@"value"] doubleValue] : ([options[@"tolerance"] respondsToSelector:@selector(doubleValue)] ? [options[@"tolerance"] doubleValue] : 0);
            int skip = [options[@"skip"] respondsToSelector:@selector(intValue)] ? [options[@"skip"] intValue] : 0;
            if (!TLinkautoJSIsFiniteNumber(x) || !TLinkautoJSIsFiniteNumber(y) || !TLinkautoJSIsFiniteNumber(width) || !TLinkautoJSIsFiniteNumber(height)) {
                return [TLinkJSNativeResponse responseWithError:@"findMultiColor(options) requires finite x/y/width/height" code:@-1];
            }
            NSString *payload = [NSString stringWithFormat:@"3;;%.0f;;%.0f;;%.0f;;%.0f;;%@;;%d;;%.4f;;%d", x, y, width, height, table, mode, value, skip];
            NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_COLOR_SEARCHER, payload] context:context];
            NSArray *parts = result[@"parts"];
            if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:result];
            int foundX = [parts[1] intValue];
            int foundY = [parts[2] intValue];
            NSMutableDictionary *res = [NSMutableDictionary dictionaryWithDictionary:result];
            res[@"matched"] = @(foundX >= 0 && foundY >= 0);
            res[@"x"] = @(foundX);
            res[@"y"] = @(foundY);
            return [TLinkJSNativeResponse responseWithValue:res];
        }
    }
    
