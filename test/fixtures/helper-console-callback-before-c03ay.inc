        ctx[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
            NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n", [NSDate date], runId ?: @"", level ?: @"log", message ?: @""];
            [weakSelf appendLine:line toPath:logPath];
            [weakSelf appendLine:line toPath:latestPath];
            NSLog(@"tlinkauto-jsd[%@][%@]: %@", runId ?: @"", level ?: @"log", message ?: @"");
        };
