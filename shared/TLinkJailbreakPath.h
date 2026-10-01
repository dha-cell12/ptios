#pragma once

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#if __has_include(<roothide.h>)
#include <roothide.h>
#define TLINK_HAS_ROOTHIDE_SDK 1
#else
#define TLINK_HAS_ROOTHIDE_SDK 0
#endif

// Roothide randomizes the bootstrap root. Rootful builds deliberately return
// the original path so the existing package behavior is unchanged.
static inline NSString *TLinkJailbreakPath(NSString *path)
{
    if (path.length == 0 || ![path hasPrefix:@"/"]) return path;

#if defined(TLINK_ROOTHIDE_RUNTIME) && TLINK_ROOTHIDE_RUNTIME
#if TLINK_HAS_ROOTHIDE_SDK
    return jbroot(path);
#endif

    typedef const char *(*TLinkJBRootFunction)(const char *);
    TLinkJBRootFunction jbrootFunction =
        (TLinkJBRootFunction)dlsym(RTLD_DEFAULT, "jbroot");
    if (jbrootFunction) {
        const char *resolved = jbrootFunction([path fileSystemRepresentation]);
        if (resolved && resolved[0]) {
            return [NSString stringWithUTF8String:resolved];
        }
    }

    // Xcode-built app binaries do not link libroothide directly. RootHide's
    // package manager places a .jbroot link beside packaged Mach-O files, so
    // this is a deterministic fallback without embedding the randomized root.
    Dl_info imageInfo = {0};
    if (dladdr((const void *)&TLinkJailbreakPath, &imageInfo) != 0 &&
        imageInfo.dli_fname && imageInfo.dli_fname[0]) {
        NSString *imagePath = [NSString stringWithUTF8String:imageInfo.dli_fname];
        NSString *imageDirectory = [imagePath stringByDeletingLastPathComponent];
        NSString *relativePath = [path substringFromIndex:1];
        return [[[imageDirectory stringByAppendingPathComponent:@".jbroot"]
            stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    }
#endif

    return path;
}

static const char *const TLinkRoothidePathMarker __attribute__((used)) =
    "roothide_jbroot_paths_v1";
