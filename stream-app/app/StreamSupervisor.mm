#import "StreamSupervisor.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>
#import <errno.h>
#import <sys/sysctl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern char **environ;

extern "C" {
int posix_spawnattr_set_persona_np(posix_spawnattr_t *attr, uid_t persona_id, uint32_t flags);
int posix_spawnattr_set_persona_uid_np(posix_spawnattr_t *attr, uid_t uid);
int posix_spawnattr_set_persona_gid_np(posix_spawnattr_t *attr, uid_t gid);
}

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

// ---------------------------------------------------------------------------
// SCStreamSupervisor
//
// Minimal spawn + watchdog for the bundled streamd binary. Uses posix_spawn to
// launch streamd --daemon, then waits on the child on a background queue so an
// unexpected exit can trigger a throttled respawn. No root is used.
// ---------------------------------------------------------------------------

static const NSTimeInterval kSCRespawnThrottle = 3.0;
static NSString *const kSCRequiredStreamdServiceMarker = @"serviceVersion=22";

@implementation SCStreamSupervisor {
    dispatch_queue_t _queue;
    pid_t _pid;
    BOOL _running;
    NSDate *_lastSpawn;
    BOOL _requiresReplacement;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.tlinkauto.streamcontrol.supervisor", DISPATCH_QUEUE_SERIAL);
        _pid = -1;
        _running = NO;
        _requiresReplacement = NO;
        _autoRespawn = YES;
    }
    return self;
}

- (BOOL)running { return _running; }
- (pid_t)childPid { return _pid; }

- (NSString *)streamdPath
{
    NSString *dir = [[NSBundle mainBundle] bundlePath];
    return [dir stringByAppendingPathComponent:@"streamd"];
}

- (NSString *)privhelperPath
{
    NSString *dir = [[NSBundle mainBundle] bundlePath];
    return [dir stringByAppendingPathComponent:@"privhelper"];
}

- (void)emitLog:(NSString *)line
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(supervisorDidLog:)]) {
            [self.delegate supervisorDidLog:line];
        }
    });
}

- (void)emitRunning:(BOOL)running pid:(pid_t)pid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(supervisorDidChangeRunning:pid:)]) {
            [self.delegate supervisorDidChangeRunning:running pid:pid];
        }
    });
}

- (void)start
{
    [self ensureService];
}

- (void)ensureService
{
    [self ensureServiceWithCompletion:nil];
}

- (void)ensureServiceWithCompletion:(void (^)(BOOL running, NSString *detail))completion
{
    dispatch_async(_queue, ^{
        self->_autoRespawn = YES;
        BOOL running = [self ensureServiceLockedWithReplace:NO reason:@"ensure"];
        if (!running) {
            [self emitLog:@"supervisor: helper ensure failed; falling back to direct app spawn"];
            [self spawnLocked];
            for (int i = 0; i < 8 && !running; i++) {
                usleep(250000);
                running = [self probeTaskServerAndUpdateLocked:@"direct-spawn"];
            }
        }
        if (completion) {
            NSString *detail = [NSString stringWithFormat:@"streamd_probe_%@ pid=%d service_marker=%@",
                                running ? @"ok" : @"failed",
                                self->_pid,
                                kSCRequiredStreamdServiceMarker];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(running, detail);
            });
        }
    });
}

- (void)stop
{
    dispatch_async(_queue, ^{
        self->_autoRespawn = NO;
        [self requestTaskServerShutdownLocked:@"stop"];
        if (self->_pid > 0) {
            [self emitLog:[NSString stringWithFormat:@"supervisor: terminating pid=%d", self->_pid]];
            kill(self->_pid, SIGTERM);
            usleep(300000);
            self->_running = NO;
            self->_pid = -1;
            [self emitRunning:NO pid:-1];
            [self killStaleStreamdLocked];
            [self runPrivhelperKillStreamdLocked];
        } else {
            [self emitLog:@"supervisor: stop requested; scanning for stale streamd"];
            [self killStaleStreamdLocked];
            [self runPrivhelperKillStreamdLocked];
        }
    });
}

- (void)restart
{
    dispatch_async(_queue, ^{
        [self emitLog:@"supervisor: restart requested; replacing service streamd"];
        self->_autoRespawn = NO;
        self->_running = NO;
        self->_pid = -1;
        [self emitRunning:NO pid:-1];
        self->_autoRespawn = YES;
        if ([self ensureServiceLockedWithReplace:YES reason:@"restart"]) {
            return;
        }
        [self emitLog:@"supervisor: helper restart failed; falling back to direct app spawn"];
        [self spawnLocked];
    });
}

- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)timeoutSec
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return nil;

    struct timeval tv;
    tv.tv_sec = timeoutSec > 0 ? timeoutSec : 1;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return nil;
    }

    NSString *payload = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    const char *bytes = [payload UTF8String];
    send(sock, bytes, strlen(bytes), 0);

    NSMutableData *data = [NSMutableData data];
    char buf[2048];
    while (true) {
        ssize_t n = recv(sock, buf, sizeof(buf), 0);
        if (n <= 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
        if (memchr(buf, '\n', (size_t)n)) break;
        if (data.length > 64 * 1024) break;
    }
    close(sock);

    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (pid_t)streamdPidFromHelloStatusLocked
{
    NSString *response = [self sendLocalTaskLineLocked:@"60\n" timeout:2];
    if (![response hasPrefix:@"0;;"]) return 0;
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return 0;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return 0;
    return (pid_t)[json[@"pid"] intValue];
}

- (NSString *)streamdLaunchPathFromHelloStatusLocked
{
    NSString *response = [self sendLocalTaskLineLocked:@"60\n" timeout:2];
    if (![response hasPrefix:@"0;;"]) return @"";
    NSString *payload = [[response substringFromIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *jsonData = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    if (jsonData.length == 0) return @"";
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    NSString *path = nil;
    if ([json isKindOfClass:[NSDictionary class]]) path = json[@"launch_executable_path"];
    return [path isKindOfClass:[NSString class]] ? path : @"";
}

- (BOOL)probeTaskServerAndUpdateLocked:(NSString *)reason
{
    NSString *status = [self sendLocalTaskLineLocked:@"97\n" timeout:2];
    if (status.length == 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: %@ probe tcp/6000 no response", reason ?: @"service"]];
        self->_running = NO;
        self->_pid = -1;
        self->_requiresReplacement = NO;
        [self emitRunning:NO pid:-1];
        return NO;
    }

    pid_t pid = [self streamdPidFromHelloStatusLocked];
    BOOL versionMatches = [status containsString:kSCRequiredStreamdServiceMarker];
    BOOL pathMatches = YES;
    NSString *runningPath = @"";
    if (pid > 0) {
        char pathBuffer[PROC_PIDPATHINFO_MAXSIZE] = {0};
        int pathLength = proc_pidpath(pid, pathBuffer, sizeof(pathBuffer));
        if (pathLength > 0) {
            runningPath = [NSString stringWithUTF8String:pathBuffer] ?: @"";
            NSString *expectedPath = [[[self streamdPath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
            NSString *actualPath = [[runningPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
            pathMatches = expectedPath.length > 0 && [actualPath isEqualToString:expectedPath];
        } else {
            // proc_pidpath can fail across the app/root process boundary. The
            // daemon records argv[0] at startup so we can still distinguish a
            // live binary from one in a removed TrollStore container.
            runningPath = [self streamdLaunchPathFromHelloStatusLocked];
            NSString *expectedPath = [[[self streamdPath] stringByStandardizingPath] stringByResolvingSymlinksInPath];
            NSString *actualPath = [[runningPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
            pathMatches = expectedPath.length > 0 && actualPath.length > 0 && [actualPath isEqualToString:expectedPath];
            if (runningPath.length == 0) runningPath = @"unresolvable";
        }
    }
    if (!versionMatches || !pathMatches) {
        self->_running = NO;
        self->_pid = pid > 0 ? pid : -1;
        self->_requiresReplacement = YES;
        [self emitRunning:NO pid:self->_pid];
        [self emitLog:[NSString stringWithFormat:@"supervisor: %@ found stale streamd pid=%d version=%@ path=%@; replacement required",
                       reason ?: @"service",
                       self->_pid,
                       versionMatches ? @"current" : @"outdated",
                       runningPath.length > 0 ? runningPath : @"unknown"]];
        return NO;
    }

    self->_running = YES;
    self->_pid = pid > 0 ? pid : self->_pid;
    self->_requiresReplacement = NO;
    [self emitRunning:YES pid:self->_pid];
    [self emitLog:[NSString stringWithFormat:@"supervisor: %@ probe ok pid=%d -> %@",
                   reason ?: @"service",
                   self->_pid,
                   [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
    return YES;
}

- (BOOL)ensureServiceLockedWithReplace:(BOOL)replaceExisting reason:(NSString *)reason
{
    if (!replaceExisting && [self probeTaskServerAndUpdateLocked:reason ?: @"ensure"]) {
        int auxiliaryExit = [self runPrivhelperEnsureStreamdLocked:NO];
        [self emitLog:[NSString stringWithFormat:@"supervisor: auxiliary service ensure exit=%d", auxiliaryExit]];
        return YES;
    }

    BOOL shouldReplace = replaceExisting || self->_requiresReplacement;
    int exitCode = [self runPrivhelperEnsureStreamdLocked:shouldReplace];
    [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper ensure exit=%d replace=%d", exitCode, shouldReplace ? 1 : 0]];

    for (int i = 0; i < 8; i++) {
        if ([self probeTaskServerAndUpdateLocked:reason ?: @"ensure"]) return YES;
        usleep(250000);
    }
    return NO;
}

- (void)requestTaskServerShutdownLocked:(NSString *)reason
{
    NSString *status = [self sendLocalTaskLineLocked:@"97\n" timeout:1];
    if (status.length > 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: tcp/6000 before %@ -> %@", reason, [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
    }

    NSString *shutdown = [self sendLocalTaskLineLocked:@"96\n" timeout:1];
    if (shutdown.length > 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: task96 shutdown response -> %@", [shutdown stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
        usleep(400000);
    }
}

- (int)runPrivhelperKillStreamdLocked
{
    NSString *path = [self privhelperPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper missing/not executable at %@", path]];
        return -1;
    }

    const char *cpath = [path fileSystemRepresentation];
    NSString *except = self->_pid > 0 ? [NSString stringWithFormat:@"%d", self->_pid] : @"-1";
    char *arg0 = strdup(cpath);
    char *arg1 = strdup("--kill-streamd");
    char *arg2 = strdup("--except-pid");
    char *arg3 = strdup([except UTF8String]);
    if (!arg0 || !arg1 || !arg2 || !arg3) {
        free(arg0); free(arg1); free(arg2); free(arg3);
        [self emitLog:@"supervisor: privhelper argv alloc failed"];
        return -2;
    }
    char *const argv[] = { arg0, arg1, arg2, arg3, NULL };

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int persona = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaUid = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int personaGid = posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1); free(arg2); free(arg3);

    if (rc != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper spawn failed rc=%d persona=%d uid=%d gid=%d", rc, persona, personaUid, personaGid]];
        return rc;
    }

    int status = 0;
    pid_t w = waitpid(pid, &status, 0);
    int exitCode = -1;
    if (w == pid && WIFEXITED(status)) exitCode = WEXITSTATUS(status);
    [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper pid=%d wait=%d status=%d exit=%d persona=%d uid=%d gid=%d",
                   pid, w, status, exitCode, persona, personaUid, personaGid]];
    return exitCode;
}

- (int)runPrivhelperEnsureStreamdLocked:(BOOL)replaceExisting
{
    NSString *helperPath = [self privhelperPath];
    NSString *streamdPath = [self streamdPath];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper missing/not executable at %@", helperPath]];
        return -1;
    }
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:streamdPath]) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd missing/not executable at %@", streamdPath]];
        return -2;
    }

    const char *cpath = [helperPath fileSystemRepresentation];
    char *arg0 = strdup(cpath);
    char *arg1 = strdup("--ensure-streamd");
    char *arg2 = strdup([streamdPath fileSystemRepresentation]);
    char *arg3 = replaceExisting ? strdup("--replace") : NULL;
    if (!arg0 || !arg1 || !arg2 || (replaceExisting && !arg3)) {
        free(arg0); free(arg1); free(arg2); free(arg3);
        [self emitLog:@"supervisor: privhelper ensure argv alloc failed"];
        return -3;
    }
    char *const argv[] = { arg0, arg1, arg2, arg3, NULL };

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int persona = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaUid = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int personaGid = posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1); free(arg2); free(arg3);

    if (rc != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper ensure spawn failed rc=%d persona=%d uid=%d gid=%d", rc, persona, personaUid, personaGid]];
        return rc;
    }

    int status = 0;
    pid_t w = waitpid(pid, &status, 0);
    int exitCode = -1;
    if (w == pid && WIFEXITED(status)) exitCode = WEXITSTATUS(status);
    [self emitLog:[NSString stringWithFormat:@"supervisor: privhelper ensure pid=%d wait=%d status=%d exit=%d persona=%d uid=%d gid=%d",
                   pid, w, status, exitCode, persona, personaUid, personaGid]];
    return exitCode;
}

- (BOOL)preparePortForSpawnLocked
{
    NSString *before = [self sendLocalTaskLineLocked:@"97\n" timeout:1];
    if (before.length > 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: tcp/6000 currently responds -> %@", [before stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
    } else {
        [self emitLog:@"supervisor: tcp/6000 has no responder before spawn"];
    }

    [self requestTaskServerShutdownLocked:@"spawn"];
    [self killStaleStreamdLocked];
    [self runPrivhelperKillStreamdLocked];
    usleep(300000);

    NSString *after = [self sendLocalTaskLineLocked:@"97\n" timeout:1];
    if (after.length > 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: warning tcp/6000 still responds after cleanup -> %@", [after stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]];
        return NO;
    } else {
        [self emitLog:@"supervisor: tcp/6000 cleanup complete; no responder"];
        return YES;
    }
}

- (void)killStaleStreamdLocked
{
    pid_t selfPid = getpid();
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd scan failed len=%zu errno=%d", len, errno]];
        return;
    }

    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) {
        [self emitLog:@"supervisor: stale streamd scan alloc failed"];
        return;
    }

    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd scan sysctl failed errno=%d", errno]];
        free(procs);
        return;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    int killed = 0;
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == selfPid) continue;

        const char *comm = procs[i].kp_proc.p_comm;
        BOOL isStreamd = (comm && strcmp(comm, "streamd") == 0);

        if (!isStreamd) {
            char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
            int got = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
            if (got > 0) {
                const char *base = strrchr(pathbuf, '/');
                base = base ? base + 1 : pathbuf;
                isStreamd = (strcmp(base, "streamd") == 0);
            }
        }

        if (!isStreamd) continue;

        errno = 0;
        int rc = kill(pid, SIGTERM);
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd pid=%d kill rc=%d errno=%d", pid, rc, errno]];
        if (rc == 0) killed++;
    }
    free(procs);

    if (killed > 0) {
        usleep(500000);
    } else {
        [self emitLog:@"supervisor: no stale streamd process found by sysctl"];
    }
}
- (void)spawnLocked
{
    NSString *path = [self streamdPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd not found at %@", path]];
        return;
    }

    if (![self preparePortForSpawnLocked]) {
        [self emitLog:@"supervisor: refusing to spawn because tcp/6000 is still occupied"];
        self->_running = NO;
        self->_pid = -1;
        [self emitRunning:NO pid:-1];
        return;
    }

    self->_lastSpawn = [NSDate date];

    const char *cpath = [path fileSystemRepresentation];
    char *const argv[] = { (char *)cpath, (char *)"--daemon", NULL };

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, NULL, argv, environ);
    if (rc != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: posix_spawn failed rc=%d", rc]];
        return;
    }

    self->_pid = pid;
    self->_running = YES;
    [self emitLog:[NSString stringWithFormat:@"supervisor: spawned streamd pid=%d", pid]];
    [self emitRunning:YES pid:pid];

    // Wait for the child on a concurrent queue so the serial _queue stays free.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int status = 0;
        pid_t w = waitpid(pid, &status, 0);
        dispatch_async(self->_queue, ^{
            [self handleChildExit:w status:status expectedPid:pid];
        });
    });
}

- (void)handleChildExit:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid
{
    if (self->_pid != expectedPid) {
        // A newer child already replaced this one; ignore stale exit.
        return;
    }

    self->_running = NO;
    self->_pid = -1;
    [self emitRunning:NO pid:-1];

    if (w < 0) {
        [self emitLog:@"supervisor: waitpid failed"];
    } else if (WIFEXITED(status)) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd exited code=%d", WEXITSTATUS(status)]];
    } else if (WIFSIGNALED(status)) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd killed signal=%d", WTERMSIG(status)]];
    }

    if (!self->_autoRespawn) {
        [self emitLog:@"supervisor: respawn disabled; staying stopped"];
        return;
    }

    // Throttle respawn so a crash-loop doesn't spin.
    NSTimeInterval since = [[NSDate date] timeIntervalSinceDate:self->_lastSpawn];
    NSTimeInterval delay = (since >= kSCRespawnThrottle) ? 0.0 : (kSCRespawnThrottle - since);
    [self emitLog:[NSString stringWithFormat:@"supervisor: respawning in %.1fs", delay]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self->_queue, ^{
        if (self->_autoRespawn && !self->_running) {
            [self spawnLocked];
        }
    });
}

@end
