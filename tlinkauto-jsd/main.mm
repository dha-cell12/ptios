#import <Foundation/Foundation.h>
#import "TLinkJSHelperServer.h"
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[], char *envp[]) {
    @autoreleasepool {
        TLinkJSHelperServer *server = [[TLinkJSHelperServer alloc] init];
        if (argc >= 4 && strcmp(argv[1], "--run-script") == 0) {
            NSString *scriptPath = [NSString stringWithUTF8String:argv[2]];
            NSString *bundlePath = [NSString stringWithUTF8String:argv[3]];
            NSDictionary *manifest = @{};
            if (argc >= 5) {
                NSString *manifestPath = [NSString stringWithUTF8String:argv[4]];
                NSData *data = [NSData dataWithContentsOfFile:manifestPath];
                if (data) {
                    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([obj isKindOfClass:[NSDictionary class]]) manifest = obj;
                }
            }
            NSDictionary *status = [server runScriptDirectAtPath:scriptPath bundlePath:bundlePath manifest:manifest];
            NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
            if (json) {
                fwrite(json.bytes, 1, json.length, stdout);
                fwrite("\n", 1, 1, stdout);
            }
            NSString *state = [status[@"state"] isKindOfClass:[NSString class]] ? status[@"state"] : @"";
            return [state isEqualToString:@"completed"] ? 0 : 2;
        }
        [server run];
    }
    return 0;
}
