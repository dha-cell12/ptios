// Frozen console hook from be66e2cf; NSLog was synchronous before disk admission.
    void (^logBlock)(NSString *, NSString *) = ^(NSString *level, NSString *message) {
        NSLog(@"com.tlinkauto.jsruntime[%@][%@]: %@", weakSelf.runId ?: @"", level ?: @"log", message ?: @"");
        TLinkJSRuntimeCore *strongSelf = weakSelf;
        if (strongSelf) [strongSelf appendConsoleLogWithLevel:level message:message];
    };
    context[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
        logBlock(level, message);
    };
