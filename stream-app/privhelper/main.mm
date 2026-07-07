#import <Foundation/Foundation.h>

#include <errno.h>
#include <dlfcn.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>
#import <objc/message.h>

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

typedef int (*TLinkHelperSBSLaunchApplicationFn)(CFStringRef identifier, Boolean suspended);

static NSString *TLinkHelperLogPath(void)
{
    return @"/var/mobile/Library/TLinkauto/privhelper.log";
}

static void TLinkHelperEnsureLogDir(void)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/Library/TLinkauto"
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void TLinkHelperLog(NSString *line)
{
    TLinkHelperEnsureLogDir();
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                  dateStyle:NSDateFormatterShortStyle
                                                  timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", ts ?: @"", line ?: @""];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:TLinkHelperLogPath()];
    if (!fh) {
        [data writeToFile:TLinkHelperLogPath() atomically:YES];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
    printf("%s", [entry UTF8String]);
    fflush(stdout);
}

static BOOL TLinkProcessIsStreamd(struct kinfo_proc *proc)
{
    if (!proc) return NO;
    const char *comm = proc->kp_proc.p_comm;
    if (comm && strcmp(comm, "streamd") == 0) return YES;

    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int got = proc_pidpath(proc->kp_proc.p_pid, pathbuf, sizeof(pathbuf));
    if (got <= 0) return NO;
    const char *base = strrchr(pathbuf, '/');
    base = base ? base + 1 : pathbuf;
    return strcmp(base, "streamd") == 0;
}

static int TLinkKillStreamd(pid_t exceptPid)
{
    pid_t selfPid = getpid();
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        TLinkHelperLog([NSString stringWithFormat:@"kill-streamd: sysctl sizing failed len=%zu errno=%d", len, errno]);
        return 2;
    }

    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) {
        TLinkHelperLog(@"kill-streamd: alloc failed");
        return 3;
    }

    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        TLinkHelperLog([NSString stringWithFormat:@"kill-streamd: sysctl list failed errno=%d", errno]);
        free(procs);
        return 4;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    int matched = 0;
    int signaled = 0;
    int failed = 0;
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == selfPid || pid == exceptPid) continue;
        if (!TLinkProcessIsStreamd(&procs[i])) continue;

        matched++;
        errno = 0;
        int rc = kill(pid, SIGTERM);
        TLinkHelperLog([NSString stringWithFormat:@"kill-streamd: SIGTERM pid=%d rc=%d errno=%d", pid, rc, errno]);
        if (rc == 0) signaled++;
        else failed++;
    }

    usleep(500000);

    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == selfPid || pid == exceptPid) continue;
        if (!TLinkProcessIsStreamd(&procs[i])) continue;
        if (kill(pid, 0) != 0) continue;

        errno = 0;
        int rc = kill(pid, SIGKILL);
        TLinkHelperLog([NSString stringWithFormat:@"kill-streamd: SIGKILL pid=%d rc=%d errno=%d", pid, rc, errno]);
        if (rc == 0) signaled++;
        else failed++;
    }

    free(procs);
    TLinkHelperLog([NSString stringWithFormat:@"kill-streamd: matched=%d signaled=%d failed=%d except=%d uid=%d euid=%d",
                    matched, signaled, failed, exceptPid, getuid(), geteuid()]);
    return failed == 0 ? 0 : 10;
}

static void TLinkHelperLoadLaunchServices(void)
{
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY | RTLD_GLOBAL);
}

static BOOL TLinkHelperOpenBundleWithWorkspace(NSString *bundleId)
{
    TLinkHelperLoadLaunchServices();
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSel]) return NO;

    id workspace = nil;
    @try {
        workspace = ((id (*)(Class, SEL))objc_msgSend)(workspaceClass, defaultSel);
    } @catch (__unused NSException *exception) {
        workspace = nil;
    }
    if (!workspace) return NO;

    NSArray<NSString *> *selectors = @[@"openApplicationWithBundleID:", @"openApplicationWithBundleIdentifier:"];
    for (NSString *selName in selectors) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        @try {
            BOOL ok = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(workspace, sel, bundleId);
            if (ok) return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL TLinkHelperOpenBundleWithSBS(NSString *bundleId, int *outRc)
{
    dlerror();
    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) {
        const char *err = dlerror();
        TLinkHelperLog([NSString stringWithFormat:@"open-bundle: SBS dlopen failed %s", err ?: "unknown"]);
        return NO;
    }
    TLinkHelperSBSLaunchApplicationFn fn = (TLinkHelperSBSLaunchApplicationFn)dlsym(handle, "SBSLaunchApplicationWithIdentifier");
    if (!fn) {
        TLinkHelperLog(@"open-bundle: SBSLaunchApplicationWithIdentifier missing");
        return NO;
    }
    int rc = fn((__bridge CFStringRef)bundleId, false);
    if (outRc) *outRc = rc;
    TLinkHelperLog([NSString stringWithFormat:@"open-bundle: SBS rc=%d bundle=%@", rc, bundleId]);
    return rc == 0;
}

static int TLinkOpenBundle(NSString *bundleId)
{
    if (bundleId.length == 0) {
        TLinkHelperLog(@"open-bundle: missing bundle id");
        return 20;
    }

    if (TLinkHelperOpenBundleWithWorkspace(bundleId)) {
        TLinkHelperLog([NSString stringWithFormat:@"open-bundle: workspace ok bundle=%@", bundleId]);
        return 0;
    }

    int sbsRc = INT_MIN;
    if (TLinkHelperOpenBundleWithSBS(bundleId, &sbsRc)) {
        return 0;
    }

    TLinkHelperLog([NSString stringWithFormat:@"open-bundle: failed bundle=%@ sbs_rc=%d", bundleId, sbsRc]);
    return 21;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) {
            TLinkHelperLog(@"privhelper version=2 scope=kill-streamd,open-bundle");
            return 0;
        }

        if (argc >= 2 && strcmp(argv[1], "--kill-streamd") == 0) {
            pid_t exceptPid = -1;
            for (int i = 2; i + 1 < argc; i++) {
                if (strcmp(argv[i], "--except-pid") == 0) {
                    exceptPid = (pid_t)atoi(argv[i + 1]);
                    i++;
                }
            }
            return TLinkKillStreamd(exceptPid);
        }

        if (argc >= 3 && strcmp(argv[1], "--open-bundle") == 0) {
            NSString *bundleId = [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkOpenBundle(bundleId);
        }

        TLinkHelperLog(@"usage: privhelper --version | --kill-streamd [--except-pid pid] | --open-bundle bundle.id");
        return 64;
    }
}
