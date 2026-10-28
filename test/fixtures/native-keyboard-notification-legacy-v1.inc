// Frozen 023e926 keyboard notification compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodKeyboard]) {
        int kind = [args count] > 0 ? [[args objectAtIndex:0] intValue] : 0;
        NSString *content = [args count] > 1 && [args objectAtIndex:1] != [NSNull null] ? [args objectAtIndex:1] : nil;
        NSDictionary *result=nil;
        if(kind==6||kind==7)result=TLinkExecuteNativeClipboardText(kind,content,context);
        else{
            NSString *payload = content ? [NSString stringWithFormat:@"%d;;%@", kind, content] : [NSString stringWithFormat:@"%d", kind];
            result = [self executeRawPayload:[NSString stringWithFormat:@"%02d%@", TASK_TEXT_INPUT, payload] context:context];
        }
        if (kind != 6) return [TLinkJSNativeResponse responseWithValue:result];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 2) return [TLinkJSNativeResponse responseWithValue:result];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"text": TLinkautoJSSafeStringPart(parts, 1)})];
    }
