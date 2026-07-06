#import <Foundation/Foundation.h>

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

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

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) {
            TLinkHelperLog(@"privhelper version=1 scope=kill-streamd");
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

        TLinkHelperLog(@"usage: privhelper --version | --kill-streamd [--except-pid pid]");
        return 64;
    }
}
