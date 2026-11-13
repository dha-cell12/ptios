#import <Foundation/Foundation.h>
#include <assert.h>
#include "../shared/TLinkJailbreakPath.h"

#ifndef EXPECTED_JB_PREFIX
#define EXPECTED_JB_PREFIX @""
#endif

int main(void) {
    @autoreleasepool {
        assert(TLinkJailbreakPath(nil) == nil);
        assert([TLinkJailbreakPath(@"") isEqualToString:@""]);
        assert([TLinkJailbreakPath(@"relative/file") isEqualToString:@"relative/file"]);
        for (NSString *path in @[@"/Applications/TLinkauto.app", @"/usr/bin/sudo",
            @"/usr/bin/tlinkautob", @"/bin/sh", @"/usr/lib/libactivator.dylib",
            @"/Library/Application Support/TLinkauto/start-recording.png"]) {
            NSString *expected = [EXPECTED_JB_PREFIX stringByAppendingString:path];
            assert([TLinkJailbreakPath(path) isEqualToString:expected]);
        }
#if defined(TLINK_ROOTLESS_RUNTIME) && TLINK_ROOTLESS_RUNTIME
        assert([TLinkJailbreakPath(@"/var/jb/usr/bin/sudo") isEqualToString:@"/var/jb/usr/bin/sudo"]);
        assert([TLinkJailbreakPath(@"/var/jb") isEqualToString:@"/var/jb"]);
#endif
    }
    return 0;
}
