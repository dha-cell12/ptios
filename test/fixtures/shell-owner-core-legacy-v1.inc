// Frozen from 965913e; compatibility oracle.
// === runShell drain/timeout support (Group A) ===

static const NSUInteger kShellMaxCapturedOutputBytes = 768 * 1024;
static const NSUInteger kTLinkautoJSMaxResponseBytes = 1024 * 1024;
static const NSUInteger kShellReadChunkBytes = 16 * 1024;
static const double kShellDefaultTimeout = 30.0;
static const double kShellMinTimeout = 1.0;
static const double kShellMaxTimeout = 300.0;
static const double kShellTerminateGrace = 1.5;

@interface TLinkShellDrainContext : NSObject {
@private
    os_unfair_lock _lock;
    BOOL _forceCloseReaders;
}
@property (nonatomic, strong) NSMutableData *outData;
@property (nonatomic, strong) NSMutableData *errData;
@property (nonatomic, assign) NSUInteger capturedBytes;
@property (nonatomic, assign) BOOL outTruncated;
@property (nonatomic, assign) BOOL errTruncated;
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr;
- (void)requestForceCloseReaders;
- (BOOL)shouldForceCloseReaders;
@end

@implementation TLinkShellDrainContext
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = OS_UNFAIR_LOCK_INIT;
        _forceCloseReaders = false;
        _outData = [NSMutableData data];
        _errData = [NSMutableData data];
    }
    return self;
}
- (void)requestForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    _forceCloseReaders = true;
    os_unfair_lock_unlock(&_lock);
}
- (BOOL)shouldForceCloseReaders {
    os_unfair_lock_lock(&_lock);
    BOOL value = _forceCloseReaders;
    os_unfair_lock_unlock(&_lock);
    return value;
}
- (void)appendChunk:(NSData *)chunk toStderr:(BOOL)isStderr {
    if (!chunk || chunk.length == 0) return;
    os_unfair_lock_lock(&_lock);
    NSUInteger remaining = (self.capturedBytes >= kShellMaxCapturedOutputBytes) ? 0 : (kShellMaxCapturedOutputBytes - self.capturedBytes);
    NSUInteger accepted = MIN(remaining, chunk.length);
    if (accepted > 0) {
        self.capturedBytes += accepted;
        if (isStderr) {
            [self.errData appendBytes:chunk.bytes length:accepted];
        } else {
            [self.outData appendBytes:chunk.bytes length:accepted];
        }
    }
    if (accepted < chunk.length) {
        if (isStderr) self.errTruncated = true;
        else self.outTruncated = true;
    }
    os_unfair_lock_unlock(&_lock);
}
@end

@interface TLinkShellResult : NSObject
@property (nonatomic, assign) int exitCode;
@property (nonatomic, assign) int terminationSignal;
@property (nonatomic, assign) BOOL timedOut;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL drainForcedClosed;
@property (nonatomic, strong) NSString *stdoutStr;
@property (nonatomic, strong) NSString *stderrStr;
@property (nonatomic, assign) BOOL stdoutTruncated;
@property (nonatomic, assign) BOOL stderrTruncated;
@end

@implementation TLinkShellResult
@end

static TLinkShellResult *RunShellCore(NSString *command, TLinkTaskExecutionContext *context, double timeoutSeconds, NSUInteger maxOutputBytes) {
    TLinkShellResult *result = [[TLinkShellResult alloc] init];
    result.exitCode = -1;
    result.stdoutStr = @"";
    result.stderrStr = @"";

    double actualTimeout = timeoutSeconds;
    if (actualTimeout <= 0) actualTimeout = (context && context.defaultTimeoutSeconds > 0) ? context.defaultTimeoutSeconds : kShellDefaultTimeout;
    if (actualTimeout < kShellMinTimeout) actualTimeout = kShellMinTimeout;
    if (actualTimeout > kShellMaxTimeout) actualTimeout = kShellMaxTimeout;

    int outPipe[2] = {-1, -1};
    int errPipe[2] = {-1, -1};
    
    if (pipe(outPipe) != 0 || pipe(errPipe) != 0) {
        result.stderrStr = @"Failed to create pipes";
        return result;
    }
    
    fcntl(outPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(outPipe[1], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(errPipe[1], F_SETFD, FD_CLOEXEC);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errPipe[0]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);

    pid_t pid = -1;
    NSString *sudoPath = TLinkJailbreakPath(@"/usr/bin/sudo");
    NSString *helperPath = TLinkJailbreakPath(@"/usr/bin/tlinkautob");
    const char *sudoFileSystemPath = [sudoPath fileSystemRepresentation];
    const char *helperFileSystemPath = [helperPath fileSystemRepresentation];
    const char *cmdArgs[] = {sudoFileSystemPath, helperFileSystemPath, "-e", [command UTF8String], NULL};
    int spawnErr = posix_spawn(&pid, sudoFileSystemPath, &actions, &attr, (char *const *)cmdArgs, NULL);

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);

    close(outPipe[1]);
    close(errPipe[1]);

    if (spawnErr != 0) {
        close(outPipe[0]);
        close(errPipe[0]);
        result.stderrStr = [NSString stringWithFormat:@"posix_spawn failed: %d", spawnErr];
        return result;
    }

    TLinkShellDrainContext *drainCtx = [[TLinkShellDrainContext alloc] init];

    dispatch_queue_t ioQueue = dispatch_queue_create("com.tlinkauto.shell.io", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t drainGroup = dispatch_group_create();

    void (^drainBlock)(int, BOOL) = ^(int fd, BOOL isStderr) {
        fcntl(fd, F_SETFL, O_NONBLOCK);
        while (![drainCtx shouldForceCloseReaders]) {
            struct pollfd pfd = { fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 100);
            if (ret > 0) {
                if (pfd.revents & POLLIN) {
                    uint8_t buf[kShellReadChunkBytes];
                    ssize_t bytesRead = read(fd, buf, sizeof(buf));
                    if (bytesRead > 0) {
                        NSData *chunk = [NSData dataWithBytes:buf length:bytesRead];
                        [drainCtx appendChunk:chunk toStderr:isStderr];
                    } else if (bytesRead == 0) {
                        break;
                    }
                } else if (pfd.revents & (POLLHUP | POLLERR)) {
                    break;
                }
            } else if (ret < 0 && errno != EINTR) {
                break;
            }
        }
        close(fd);
    };

    int outFd = outPipe[0];
    int errFd = errPipe[0];
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(outFd, false); });
    dispatch_group_async(drainGroup, ioQueue, ^{ drainBlock(errFd, true); });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:actualTimeout];
    BOOL timedOut = false;
    BOOL cancelled = false;

    while (true) {
        int status;
        pid_t wpid = waitpid(pid, &status, WNOHANG);
        if (wpid == pid) {
            if (WIFEXITED(status)) {
                result.exitCode = WEXITSTATUS(status);
            } else if (WIFSIGNALED(status)) {
                result.exitCode = -1;
                result.terminationSignal = WTERMSIG(status);
            }
            break;
        }

        if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
            timedOut = true;
            break;
        }
        if (TLinkNativeStopped() || (context && context.cancellationToken && [context.cancellationToken isCancelled])) {
            cancelled = true;
            break;
        }
        usleep(20 * 1000);
    }

    if (timedOut || cancelled) {
        result.timedOut = timedOut;
        result.cancelled = cancelled;
        kill(-pid, SIGTERM);
        
        NSDate *graceDeadline = [NSDate dateWithTimeIntervalSinceNow:kShellTerminateGrace];
        while (true) {
            int status;
            pid_t wpid = waitpid(pid, &status, WNOHANG);
            if (wpid == pid) {
                if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
                else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
                break;
            }
            if ([[NSDate date] compare:graceDeadline] != NSOrderedAscending) {
                kill(-pid, SIGKILL);
                break;
            }
            usleep(20 * 1000);
        }
        
        if (result.exitCode == -1 && result.terminationSignal == 0) {
            int status;
            waitpid(pid, &status, 0);
            if (WIFEXITED(status)) result.exitCode = WEXITSTATUS(status);
            else if (WIFSIGNALED(status)) { result.exitCode = -1; result.terminationSignal = WTERMSIG(status); }
        }

        NSDate *drainDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (dispatch_group_wait(drainGroup, DISPATCH_TIME_NOW) != 0) {
            if ([[NSDate date] compare:drainDeadline] != NSOrderedAscending) {
                [drainCtx requestForceCloseReaders];
                result.drainForcedClosed = true;
                break;
            }
            usleep(20 * 1000);
        }
    }

    dispatch_group_wait(drainGroup, DISPATCH_TIME_FOREVER);

    NSString *outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSUTF8StringEncoding];
    if (!outStr && drainCtx.outData.length > 0) outStr = [[NSString alloc] initWithData:drainCtx.outData encoding:NSASCIIStringEncoding];
    
    NSString *errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSUTF8StringEncoding];
    if (!errStr && drainCtx.errData.length > 0) errStr = [[NSString alloc] initWithData:drainCtx.errData encoding:NSASCIIStringEncoding];

    result.stdoutStr = outStr ?: @"";
    result.stderrStr = errStr ?: @"";
    result.stdoutTruncated = drainCtx.outTruncated;
    result.stderrTruncated = drainCtx.errTruncated;

    return result;
}

