#pragma once

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#if defined(TLINK_ROOTLESS_RUNTIME) && TLINK_ROOTLESS_RUNTIME && __has_include(<rootless.h>)
#include <rootless.h>
#define TLINK_HAS_ROOTLESS_SDK 1
#else
#define TLINK_HAS_ROOTLESS_SDK 0
#endif
#if __has_include(<roothide.h>)
#include <roothide.h>
#define TLINK_HAS_ROOTHIDE_SDK 1
#else
#define TLINK_HAS_ROOTHIDE_SDK 0
#endif

// Call only for bootstrap-owned files. Shared /var/mobile data and stock iOS
// framework paths do not use this conversion.
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
#elif defined(TLINK_ROOTLESS_RUNTIME) && TLINK_ROOTLESS_RUNTIME
    if ([path isEqualToString:@"/var/jb"] || [path hasPrefix:@"/var/jb/"]) return path;
#if TLINK_HAS_ROOTLESS_SDK
    return ROOT_PATH_NS_VAR(path);
#else
    // The standalone Xcode app does not link Theos's libroot archive. Standard
    // rootless jailbreaks expose their bootstrap at /var/jb.
    return [@"/var/jb" stringByAppendingString:path];
#endif
#endif

    return path;
}

static const char *const TLinkRoothidePathMarker __attribute__((used)) =
    "roothide_jbroot_paths_v1";
