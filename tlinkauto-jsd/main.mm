#import <Foundation/Foundation.h>
#import "TLinkJSHelperServer.h"

int main(int argc, char *argv[], char *envp[]) {
    @autoreleasepool {
        TLinkJSHelperServer *server = [[TLinkJSHelperServer alloc] init];
        [server run];
    }
    return 0;
}
