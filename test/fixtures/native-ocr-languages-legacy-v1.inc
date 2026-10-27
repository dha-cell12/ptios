// Frozen 86c0974 OCR languages compatibility oracle.
    else if ([method isEqualToString:TLinkJSNativeMethodOcrLanguages]) {
        NSDictionary *result = [self executeRawPayload:[NSString stringWithFormat:@"%02dcheck_langs", TASK_OCR_TESSERACT_REGION] context:context];
        NSArray *parts = result[@"parts"];
        if (![result[@"ok"] boolValue] || [parts count] < 3) return [TLinkJSNativeResponse responseWithValue:TLinkautoJSOCRResultByAddingDecodedError(result)];
        NSString *langsText = TLinkautoJSBase64Decode(TLinkautoJSSafeStringPart(parts, 2));
        NSArray *langs = [langsText length] > 0 ? [langsText componentsSeparatedByString:@","] : @[];
        return [TLinkJSNativeResponse responseWithValue:TLinkautoJSResultByAdding(result, @{@"languages": langs, @"value": langsText ?: @""})];
    }
