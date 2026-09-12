#import <Foundation/Foundation.h>
#import "../../shared/TLinkLicenseVerifier.h"
#import "../../shared/TLinkVPNManager.h"

#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <spawn.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <unistd.h>
#import <objc/message.h>

extern char **environ;

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

extern "C" {
int posix_spawnattr_set_persona_np(posix_spawnattr_t *attr, uid_t persona_id, uint32_t flags);
int posix_spawnattr_set_persona_uid_np(posix_spawnattr_t *attr, uid_t uid);
int posix_spawnattr_set_persona_gid_np(posix_spawnattr_t *attr, uid_t gid);
}

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

typedef int (*TLinkHelperSBSLaunchApplicationFn)(CFStringRef identifier, Boolean suspended);
static BOOL TLinkHelperOpenBundleWithSBS(NSString *bundleId, int *outRc);

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

static int TLinkHelperRequireLicense(NSString *feature, NSString *command)
{
    NSString *licenseError = nil;
    if (TLinkLicenseFeatureAllowed(feature, &licenseError)) return 0;
    NSDictionary *status = TLinkLicenseStatusDictionary();
    TLinkHelperLog([NSString stringWithFormat:@"license denied command=%@ feature=%@ state=%@ error=%@",
                    command ?: @"unknown",
                    feature ?: @"automation",
                    status[@"state"] ?: @"invalid",
                    licenseError ?: status[@"error"] ?: @"license_required"]);
    return 90;
}

static NSString *const kTLinkHelperVPNRequestDirectory =
    @"/var/mobile/Library/TLinkauto/tmp/vpn-private-requests";

static NSDictionary *TLinkHelperVPNFailure(NSString *code,
                                           NSDictionary *extra)
{
    NSMutableDictionary *result = extra
        ? [extra mutableCopy] : [NSMutableDictionary dictionary];
    result[@"ok"] = @0;
    result[@"code"] = code ?: @"vpn_private_helper_failed";
    return result;
}

static BOOL TLinkHelperWriteAll(int fd, NSData *data)
{
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    size_t remaining = data.length;
    while (remaining > 0) {
        ssize_t wrote = write(fd, bytes, remaining);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) return NO;
        bytes += wrote;
        remaining -= (size_t)wrote;
    }
    return YES;
}

static BOOL TLinkHelperVPNServerIsLoopback(NSString *server)
{
    NSString *candidate = [[server
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([candidate isEqualToString:@"localhost"]) return YES;
    if ([candidate hasPrefix:@"["] && [candidate hasSuffix:@"]"] &&
        candidate.length > 2) {
        candidate = [candidate substringWithRange:
            NSMakeRange(1, candidate.length - 2)];
    }
    struct in_addr ipv4 = {};
    if (inet_pton(AF_INET, candidate.UTF8String, &ipv4) == 1) {
        return (ntohl(ipv4.s_addr) & 0xff000000U) == 0x7f000000U;
    }
    struct in6_addr ipv6 = {};
    return inet_pton(AF_INET6, candidate.UTF8String, &ipv6) == 1 &&
        IN6_IS_ADDR_LOOPBACK(&ipv6);
}

static BOOL TLinkHelperVPNRequestPathAllowed(NSString *requestPath,
                                             NSString **requestID)
{
    struct stat directoryStat = {};
    if (lstat(kTLinkHelperVPNRequestDirectory.fileSystemRepresentation,
              &directoryStat) != 0 ||
        !S_ISDIR(directoryStat.st_mode) ||
        directoryStat.st_uid != 501 ||
        (directoryStat.st_mode & 077) != 0) {
        return NO;
    }
    if (requestPath.length == 0 ||
        ![requestPath isEqualToString:requestPath.stringByStandardizingPath] ||
        ![[requestPath stringByDeletingLastPathComponent]
            isEqualToString:kTLinkHelperVPNRequestDirectory]) {
        return NO;
    }
    NSString *name = requestPath.lastPathComponent;
    if (![name hasPrefix:@"vpnconf-"] || ![name hasSuffix:@".plist"]) {
        return NO;
    }
    NSRange tokenRange = NSMakeRange(
        @"vpnconf-".length,
        name.length - @"vpnconf-".length - @".plist".length);
    if ((NSInteger)tokenRange.length <= 0) return NO;
    NSString *token = [name substringWithRange:tokenRange];
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:token];
    if (!uuid || ![uuid.UUIDString isEqualToString:token]) return NO;
    if (requestID) *requestID = token;
    return YES;
}

static BOOL TLinkHelperWriteVPNResult(NSString *resultPath,
                                      NSString *requestID,
                                      NSInteger requestVersion,
                                      NSDictionary *rawResult)
{
    NSMutableDictionary *result = rawResult
        ? [rawResult mutableCopy] : [NSMutableDictionary dictionary];
    result[@"version"] = @(requestVersion);
    result[@"request_id"] = requestID ?: @"";
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization
        dataWithPropertyList:result
                     format:NSPropertyListBinaryFormat_v1_0
                    options:0
                      error:&error];
    if (!data || data.length > 65536) return NO;

    int fd = open(resultPath.fileSystemRepresentation,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return NO;
    BOOL ok = fchmod(fd, 0600) == 0 &&
              fchown(fd, 501, 501) == 0 &&
              TLinkHelperWriteAll(fd, data) &&
              fsync(fd) == 0;
    close(fd);
    if (!ok) unlink(resultPath.fileSystemRepresentation);
    return ok;
}

static int TLinkHelperConfigureVPN(NSString *requestPath)
{
    NSString *requestID = nil;
    if (!TLinkHelperVPNRequestPathAllowed(requestPath, &requestID)) {
        TLinkHelperLog(@"configure-vpn: refused request path");
        return 70;
    }
    NSString *resultPath = [requestPath stringByAppendingString:@".result"];
    unlink(resultPath.fileSystemRepresentation);

    int (^finish)(NSDictionary *, int) =
        ^int(NSDictionary *result, int exitCode) {
            BOOL wrote = TLinkHelperWriteVPNResult(
                resultPath, requestID, 2, result);
            TLinkHelperLog([NSString stringWithFormat:
                @"configure-vpn: request=%@ code=%@ ok=%d result_written=%d exit=%d uid=%d",
                requestID,
                result[@"code"] ?: @"unknown",
                [result[@"ok"] boolValue] ? 1 : 0,
                wrote ? 1 : 0,
                exitCode,
                geteuid()]);
            return wrote ? exitCode : 74;
        };

    if (geteuid() != 0 || getegid() != 0) {
        NSDictionary *failure = TLinkHelperVPNFailure(
            @"vpn_private_root_helper_required", @{
                @"executor_uid": @(geteuid()),
                @"executor_gid": @(getegid()),
            });
        return finish(failure, 71);
    }

    struct stat requestStat = {};
    int fd = open(requestPath.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0 || fstat(fd, &requestStat) != 0 ||
        !S_ISREG(requestStat.st_mode) || requestStat.st_uid != 501 ||
        (requestStat.st_mode & 077) != 0 || requestStat.st_nlink != 1 ||
        requestStat.st_size <= 0 || requestStat.st_size > 16384) {
        if (fd >= 0) close(fd);
        unlink(requestPath.fileSystemRepresentation);
        NSDictionary *failure = TLinkHelperVPNFailure(
            @"vpn_private_request_validation_failed", nil);
        return finish(failure, 72);
    }

    NSMutableData *requestData = [NSMutableData data];
    uint8_t buffer[4096];
    BOOL readOK = YES;
    while (requestData.length < (NSUInteger)requestStat.st_size) {
        ssize_t got = read(fd, buffer, sizeof(buffer));
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) { readOK = NO; break; }
        [requestData appendBytes:buffer length:(NSUInteger)got];
    }
    close(fd);
    // Credentials live only in memory after this point, even if the private
    // store takes several seconds to publish its service.
    unlink(requestPath.fileSystemRepresentation);

    NSError *parseError = nil;
    NSDictionary *request = readOK
        ? [NSPropertyListSerialization propertyListWithData:requestData
                                                    options:0
                                                     format:nil
                                                      error:&parseError]
        : nil;
    NSInteger requestVersion = [request[@"version"] integerValue];
    NSString *profileType = request[@"profile_type"];
    BOOL requestValid = [request isKindOfClass:[NSDictionary class]] &&
        requestVersion == 2 &&
        [request[@"request_id"] isEqualToString:requestID] &&
        [profileType isKindOfClass:[NSString class]] &&
        [request[@"server"] isKindOfClass:[NSString class]] &&
        [request[@"username"] isKindOfClass:[NSString class]] &&
        [request[@"password"] isKindOfClass:[NSString class]] &&
        (!request[@"remote_identifier"] ||
            [request[@"remote_identifier"] isKindOfClass:[NSString class]]) &&
        (!request[@"shared_secret"] ||
            [request[@"shared_secret"] isKindOfClass:[NSString class]]) &&
        (!request[@"group_name"] ||
            [request[@"group_name"] isKindOfClass:[NSString class]]) &&
        (!request[@"display_name"] ||
            [request[@"display_name"] isKindOfClass:[NSString class]]) &&
        (!request[@"encryption_level"] ||
            [request[@"encryption_level"] isKindOfClass:[NSNumber class]]) &&
        (!request[@"send_all_traffic"] ||
            [request[@"send_all_traffic"] isKindOfClass:[NSNumber class]]) &&
        fabs([request[@"created_at"] doubleValue] -
             [[NSDate date] timeIntervalSince1970]) <= 120.0;
    if (!requestValid) {
        NSDictionary *failure = TLinkHelperVPNFailure(
            @"vpn_private_request_invalid", @{
                @"native_error": parseError.localizedDescription ?: @"",
            });
        return finish(failure, 73);
    }

    NSSet<NSString *> *supportedTypes = [NSSet setWithObjects:
        @"PPTP", @"L2TP", @"IPSec", @"IKEv2", nil];
    NSString *server = [request[@"server"]
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *username = [request[@"username"]
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *password = request[@"password"];
    NSString *secret = request[@"shared_secret"] ?: @"";
    if (![supportedTypes containsObject:profileType]) {
        return finish(TLinkHelperVPNFailure(
            @"vpn_private_protocol_unsupported", nil), 73);
    }
    if (server.length == 0 || server.length > 1024 ||
        username.length == 0 || username.length > 1024 ||
        password.length == 0 || password.length > 4096 ||
        secret.length > 4096) {
        return finish(TLinkHelperVPNFailure(
            @"vpn_configuration_incomplete", nil), 73);
    }
    if (TLinkHelperVPNServerIsLoopback(server)) {
        return finish(TLinkHelperVPNFailure(
            @"vpn_server_loopback_not_allowed", nil), 73);
    }
    if ([profileType isEqualToString:@"L2TP"] && secret.length == 0) {
        return finish(TLinkHelperVPNFailure(
            @"vpn_l2tp_ipsec_shared_secret_required", nil), 73);
    }

    int licenseExit = TLinkHelperRequireLicense(
        @"automation", @"configure-vpn");
    if (licenseExit != 0) {
        NSDictionary *failure = TLinkHelperVPNFailure(
            @"license_required", nil);
        return finish(failure, licenseExit);
    }

    NSDictionary *result = nil;
    if ([profileType isEqualToString:@"IKEv2"]) {
        result = TLinkVPNConfigureIKEv2SynchronouslyForHelper(
            server, request[@"remote_identifier"] ?: server,
            username, password);
    } else {
        result = TLinkVPNConfigureLegacyPrivateSynchronouslyForHelper(
            profileType, server, username, password,
            secret, request[@"group_name"] ?: @"",
            request[@"display_name"] ?: @"",
            [request[@"encryption_level"] integerValue],
            request[@"send_all_traffic"]
                ? [request[@"send_all_traffic"] boolValue] : YES);
    }
    return finish(result, [result[@"ok"] boolValue] ? 0 : 75);
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

static BOOL TLinkHelperProcessIsSpringBoard(struct kinfo_proc *proc, NSString **outPath, BOOL *outExactPath)
{
    if (!proc) return NO;
    BOOL nameMatches = proc->kp_proc.p_comm && strcmp(proc->kp_proc.p_comm, "SpringBoard") == 0;
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int got = proc_pidpath(proc->kp_proc.p_pid, pathbuf, sizeof(pathbuf));
    NSString *path = got > 0 ? ([NSString stringWithUTF8String:pathbuf] ?: @"") : @"";
    BOOL exactPath = [path hasSuffix:@"/SpringBoard.app/SpringBoard"];
    if (outPath) *outPath = path;
    if (outExactPath) *outExactPath = exactPath;
    return exactPath || (nameMatches && path.length == 0);
}

static int TLinkRespring(void)
{
    if (geteuid() != 0) {
        TLinkHelperLog([NSString stringWithFormat:@"respring: refused non-root uid=%d euid=%d", getuid(), geteuid()]);
        return 70;
    }

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        TLinkHelperLog([NSString stringWithFormat:@"respring: sysctl sizing failed len=%zu errno=%d", len, errno]);
        return 71;
    }
    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) {
        TLinkHelperLog(@"respring: alloc failed");
        return 72;
    }
    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        TLinkHelperLog([NSString stringWithFormat:@"respring: sysctl list failed errno=%d", errno]);
        free(procs);
        return 73;
    }

    pid_t exactPid = -1;
    pid_t fallbackPid = -1;
    NSString *exactPath = @"";
    NSString *fallbackPath = @"";
    int count = (int)(len / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == getpid()) continue;
        NSString *path = nil;
        BOOL pathMatches = NO;
        if (!TLinkHelperProcessIsSpringBoard(&procs[i], &path, &pathMatches)) continue;
        if (pathMatches) {
            exactPid = pid;
            exactPath = path ?: @"";
            break;
        }
        if (fallbackPid <= 0) {
            fallbackPid = pid;
            fallbackPath = path ?: @"";
        }
    }
    free(procs);

    pid_t targetPid = exactPid > 0 ? exactPid : fallbackPid;
    NSString *targetPath = exactPid > 0 ? exactPath : fallbackPath;
    if (targetPid <= 0) {
        TLinkHelperLog(@"respring: SpringBoard process not found");
        return 74;
    }

    errno = 0;
    int termRc = kill(targetPid, SIGTERM);
    int termErrno = errno;
    TLinkHelperLog([NSString stringWithFormat:@"respring: SIGTERM pid=%d path=%@ rc=%d errno=%d uid=%d euid=%d",
                    targetPid, targetPath.length > 0 ? targetPath : @"name_only", termRc, termErrno, getuid(), geteuid()]);
    if (termRc != 0 && termErrno != ESRCH) return 75;

    for (int i = 0; i < 10; i++) {
        usleep(100000);
        if (kill(targetPid, 0) != 0 && errno == ESRCH) {
            TLinkHelperLog([NSString stringWithFormat:@"respring: SpringBoard pid=%d exited after SIGTERM", targetPid]);
            return 0;
        }
    }

    errno = 0;
    int killRc = kill(targetPid, SIGKILL);
    int killErrno = errno;
    TLinkHelperLog([NSString stringWithFormat:@"respring: SIGKILL pid=%d rc=%d errno=%d", targetPid, killRc, killErrno]);
    if (killRc != 0 && killErrno != ESRCH) return 76;
    return 0;
}

static void TLinkHelperLoadLaunchServices(void)
{
    dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/PrivateFrameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_GLOBAL);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY | RTLD_GLOBAL);
}

static id TLinkHelperObjectForSelectorOrKey(id object, NSString *selectorName, NSString *key)
{
    if (!object) return nil;
    if (selectorName.length > 0) {
        SEL sel = NSSelectorFromString(selectorName);
        if ([object respondsToSelector:sel]) {
            @try {
                return ((id (*)(id, SEL))objc_msgSend)(object, sel);
            } @catch (__unused NSException *exception) {
            }
        }
    }
    if (key.length > 0) {
        @try {
            return [object valueForKey:key];
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static NSString *TLinkHelperPathFromObject(id object)
{
    if (!object) return nil;
    if ([object isKindOfClass:[NSURL class]]) return [(NSURL *)object path];
    if ([object isKindOfClass:[NSString class]]) return (NSString *)object;
    return nil;
}

static NSString *TLinkHelperNormalizedPath(NSString *path)
{
    if (path.length == 0) return nil;
    NSString *standard = [path stringByStandardizingPath] ?: path;
    NSString *resolved = [standard stringByResolvingSymlinksInPath];
    return resolved.length > 0 ? resolved : standard;
}

static id TLinkHelperApplicationProxyForBundleId(NSString *bundleId)
{
    if (bundleId.length == 0) return nil;
    TLinkHelperLoadLaunchServices();
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:proxySel]) return nil;
    @try {
        return ((id (*)(Class, SEL, NSString *))objc_msgSend)(proxyClass, proxySel, bundleId);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *TLinkHelperBundlePathForBundleId(NSString *bundleId)
{
    id proxy = TLinkHelperApplicationProxyForBundleId(bundleId);
    if (!proxy) return nil;
    NSArray<NSString *> *selectors = @[@"bundleURL", @"bundlePath", @"path", @"resourcesDirectoryURL"];
    for (NSString *selectorName in selectors) {
        id value = TLinkHelperObjectForSelectorOrKey(proxy, selectorName, selectorName);
        NSString *path = TLinkHelperPathFromObject(value);
        if (path.length > 0) return TLinkHelperNormalizedPath(path);
    }
    return nil;
}

static NSString *TLinkHelperDataPathForBundleId(NSString *bundleId)
{
    id proxy = TLinkHelperApplicationProxyForBundleId(bundleId);
    if (!proxy) return nil;
    NSArray<NSString *> *selectors = @[@"dataContainerURL", @"containerURL"];
    for (NSString *selectorName in selectors) {
        id value = TLinkHelperObjectForSelectorOrKey(proxy, selectorName, selectorName);
        NSString *path = TLinkHelperPathFromObject(value);
        if (path.length > 0) return TLinkHelperNormalizedPath(path);
    }
    return nil;
}

static BOOL TLinkHelperDataPathAllowed(NSString *path)
{
    NSString *normalized = TLinkHelperNormalizedPath(path);
    if (normalized.length == 0) return NO;
    if ([normalized isEqualToString:@"/var/mobile"] ||
        [normalized isEqualToString:@"/private/var/mobile"]) {
        return NO;
    }
    NSArray<NSString *> *allowedPrefixes = @[
        @"/var/mobile/Containers/Data/Application/",
        @"/private/var/mobile/Containers/Data/Application/",
    ];
    for (NSString *prefix in allowedPrefixes) {
        if ([normalized hasPrefix:prefix] && normalized.length > prefix.length) {
            return YES;
        }
    }
    return NO;
}

static BOOL TLinkHelperPidIsAlive(pid_t pid)
{
    if (pid <= 0) return NO;
    if (kill(pid, 0) == 0) return YES;
    return errno == EPERM;
}

static NSString *TLinkHelperSendLoopbackLine(NSString *line, uint16_t port, int timeoutSec)
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return nil;
#ifdef SO_NOSIGPIPE
    int noSigPipe = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
#endif

    struct timeval tv;
    tv.tv_sec = timeoutSec > 0 ? timeoutSec : 1;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
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

static NSString *TLinkHelperSendLocalTaskLine(NSString *line, int timeoutSec)
{
    return TLinkHelperSendLoopbackLine(line, 6000, timeoutSec);
}

static BOOL TLinkHelperProcessHasName(struct kinfo_proc *proc, const char *name)
{
    if (!proc || !name) return NO;
    const char *comm = proc->kp_proc.p_comm;
    if (comm && strcmp(comm, name) == 0) return YES;
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int got = proc_pidpath(proc->kp_proc.p_pid, pathbuf, sizeof(pathbuf));
    if (got <= 0) return NO;
    const char *base = strrchr(pathbuf, '/');
    base = base ? base + 1 : pathbuf;
    return strcmp(base, name) == 0;
}

static void TLinkHelperKillProcessNamed(const char *name)
{
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) return;
    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) return;
    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        free(procs);
        return;
    }
    int count = (int)(len / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == getpid()) continue;
        if (TLinkHelperProcessHasName(&procs[i], name)) kill(pid, SIGKILL);
    }
    free(procs);
    usleep(200000);
}

static void TLinkHelperKillClipboardd(void)
{
    TLinkHelperKillProcessNamed("clipboardd");
}

static BOOL TLinkClipboarddProbeIsCurrent(NSString *probe)
{
    return [probe hasPrefix:@"0;;clipboardd_ready"] && [probe containsString:@"version=16"];
}

static int TLinkEnsureClipboardd(NSString *streamdPath, BOOL replaceExisting)
{
    NSString *clipboarddPath = [[streamdPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"clipboardd"];
    if (![[clipboarddPath lastPathComponent] isEqualToString:@"clipboardd"] ||
        ![clipboarddPath hasSuffix:@"/StreamControl.app/clipboardd"] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:clipboarddPath]) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: invalid path=%@", clipboarddPath ?: @""]);
        return 50;
    }

    NSString *probe = TLinkHelperSendLoopbackLine(@"1;;OQ==\n", 6012, 1);
    if (TLinkClipboarddProbeIsCurrent(probe) && !replaceExisting) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: already responding %@",
                        [probe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
        return 0;
    }

    TLinkHelperKillClipboardd();
    const char *path = [clipboarddPath fileSystemRepresentation];
    char *arg0 = strdup(path);
    char *arg1 = strdup("--daemon");
    if (!arg0 || !arg1) {
        free(arg0); free(arg1);
        return 51;
    }
    char *const argv[] = { arg0, arg1, NULL };
    pid_t pid = -1;
    int rc = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    free(arg0); free(arg1);
    if (rc != 0 || pid <= 0) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: spawn failed rc=%d path=%@", rc, clipboarddPath]);
        return 52;
    }

    TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: spawned pid=%d uid=%d euid=%d", pid, getuid(), geteuid()]);
    for (int i = 0; i < 12; i++) {
        usleep(250000);
        probe = TLinkHelperSendLoopbackLine(@"1;;OQ==\n", 6012, 1);
        if (TLinkClipboarddProbeIsCurrent(probe)) {
            TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: probe ok %@",
                            [probe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
            return 0;
        }
    }
    TLinkHelperLog([NSString stringWithFormat:@"ensure-clipboardd: pid=%d did not become ready", pid]);
    return 53;
}

static BOOL TLinkUIServiceProbeIsCurrent(NSString *probe)
{
    return [probe hasPrefix:@"0;;uiservice_ready"] &&
           [probe containsString:@"version=24"] &&
           [probe containsString:@"launch_mode=UIKitPluginSBSAccessibilityContextHosting"] &&
           [probe containsString:@"plugin_complete=1"] &&
           [probe containsString:@"window_scene_attachment_enabled=0"] &&
           [probe containsString:@"system_window_override_installed=1"] &&
           [probe containsString:@"window_level_hook_installed=1"] &&
           [probe containsString:@"accessibility_hosting_controller_available=1"] &&
           [probe containsString:@"host_window_registered=1"] &&
           [probe containsString:@"host_window_ready=1"] &&
           [probe containsString:@"vision_ocr_port=6018"] &&
           [probe containsString:@"vision_ocr_started=1"] &&
           [probe containsString:@"vision_ocr_listening=1"] &&
           [probe containsString:@"vision_ocr_protocol=4"] &&
           [probe containsString:@"vision_ocr_transport=inline_rgba8888"] &&
           [probe containsString:@"vision_ocr_fallback_protocol=3"] &&
           [probe containsString:@";;uid=501;;"] &&
           [probe containsString:@";;euid=501;;"];
}

static int TLinkEnsureUIService(NSString *streamdPath, BOOL replaceExisting)
{
    NSString *appPath = [streamdPath stringByDeletingLastPathComponent];
    NSString *servicePath = [appPath stringByAppendingPathComponent:@"TLinkUIService.app/TLinkUIService"];
    if (![servicePath hasSuffix:@"/StreamControl.app/TLinkUIService.app/TLinkUIService"] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:servicePath]) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: invalid path=%@", servicePath ?: @""]);
        return 80;
    }

    NSString *probe = TLinkHelperSendLoopbackLine(@"ping\n", 6017, 1);
    if (TLinkUIServiceProbeIsCurrent(probe) && !replaceExisting) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: already responding %@",
                        [probe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]);
        return 0;
    }

    TLinkHelperKillProcessNamed("TLinkUIService");
    TLinkHelperLog(@"ensure-uiservice: starting hosted UIKit plugin with mobile persona");

    const char *path = [servicePath fileSystemRepresentation];
    char *arg0 = strdup(path);
    char *arg1 = strdup("--daemon");
    if (!arg0 || !arg1) {
        free(arg0); free(arg1);
        return 81;
    }
    char *const argv[] = { arg0, arg1, NULL };
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int persona = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaUid = posix_spawnattr_set_persona_uid_np(&attr, 501);
    int personaGid = posix_spawnattr_set_persona_gid_np(&attr, 501);
    if (persona != 0 || personaUid != 0 || personaGid != 0) {
        posix_spawnattr_destroy(&attr);
        free(arg0); free(arg1);
        TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: mobile persona failed persona=%d uid=%d gid=%d",
                        persona, personaUid, personaGid]);
        return 82;
    }
    pid_t pid = -1;
    int rc = posix_spawn(&pid, path, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1);
    if (rc != 0 || pid <= 0) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: spawn failed rc=%d path=%@", rc, servicePath]);
        return 83;
    }

    TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: spawned pid=%d persona=mobile uid=501 gid=501", pid]);
    for (int i = 0; i < 12; i++) {
        usleep(250000);
        probe = TLinkHelperSendLoopbackLine(@"ping\n", 6017, 1);
        if (TLinkUIServiceProbeIsCurrent(probe)) {
            TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: probe ok %@",
                            [probe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]);
            return 0;
        }
    }
    TLinkHelperLog([NSString stringWithFormat:@"ensure-uiservice: pid=%d did not become ready", pid]);
    return 84;
}

static BOOL TLinkVPNAgentProbeIsCurrent(NSString *probe)
{
    return [probe hasPrefix:@"0;;vpnagent_ready"] &&
           [probe containsString:@"version=9"] &&
           [probe containsString:@"phase=5"] &&
           [probe containsString:@" uid=501 "] &&
           [probe containsString:@" euid=501 "] &&
           [probe containsString:@" gid=501 "] &&
           [probe containsString:@" egid=501"];
}

static int TLinkEnsureVPNAgent(NSString *streamdPath, BOOL replaceExisting)
{
    NSString *vpnagentPath = [[streamdPath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"vpnagent"];
    if (![[vpnagentPath lastPathComponent] isEqualToString:@"vpnagent"] ||
        ![vpnagentPath hasSuffix:@"/StreamControl.app/vpnagent"] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:vpnagentPath]) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-vpnagent: invalid path=%@",
                        vpnagentPath ?: @""]);
        return 54;
    }

    NSString *probe = TLinkHelperSendLoopbackLine(@"ping\n", 6016, 1);
    if (TLinkVPNAgentProbeIsCurrent(probe) && !replaceExisting) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-vpnagent: already responding %@",
                        [probe stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
        return 0;
    }

    TLinkHelperKillProcessNamed("vpnagent");
    const char *path = [vpnagentPath fileSystemRepresentation];
    char *arg0 = strdup(path);
    char *arg1 = strdup("--daemon");
    if (!arg0 || !arg1) {
        free(arg0); free(arg1);
        return 55;
    }
    char *const argv[] = { arg0, arg1, NULL };
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int persona = posix_spawnattr_set_persona_np(
        &attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaUid = posix_spawnattr_set_persona_uid_np(&attr, 501);
    int personaGid = posix_spawnattr_set_persona_gid_np(&attr, 501);
    if (persona != 0 || personaUid != 0 || personaGid != 0) {
        posix_spawnattr_destroy(&attr);
        free(arg0); free(arg1);
        TLinkHelperLog([NSString stringWithFormat:
            @"ensure-vpnagent: mobile persona failed persona=%d uid=%d gid=%d",
            persona, personaUid, personaGid]);
        return 56;
    }

    pid_t pid = -1;
    int rc = posix_spawn(&pid, path, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1);
    if (rc != 0 || pid <= 0) {
        TLinkHelperLog([NSString stringWithFormat:
            @"ensure-vpnagent: spawn failed rc=%d path=%@", rc, vpnagentPath]);
        return 57;
    }

    TLinkHelperLog([NSString stringWithFormat:
        @"ensure-vpnagent: spawned pid=%d persona=mobile uid=501 gid=501", pid]);
    for (int i = 0; i < 12; i++) {
        usleep(250000);
        probe = TLinkHelperSendLoopbackLine(@"ping\n", 6016, 1);
        if (TLinkVPNAgentProbeIsCurrent(probe)) {
            TLinkHelperLog([NSString stringWithFormat:@"ensure-vpnagent: probe ok %@",
                            [probe stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
            return 0;
        }
    }
    TLinkHelperLog([NSString stringWithFormat:
        @"ensure-vpnagent: pid=%d did not become ready", pid]);
    return 58;
}

static BOOL TLinkHelperStreamdPathAllowed(NSString *streamdPath)
{
    NSString *normalized = TLinkHelperNormalizedPath(streamdPath);
    if (normalized.length == 0) return NO;
    if (![[normalized lastPathComponent] isEqualToString:@"streamd"]) return NO;
    return [normalized hasSuffix:@"/StreamControl.app/streamd"];
}

static void TLinkSpawnAuxiliaryEnsure(NSString *streamdPath, BOOL replaceExisting)
{
    NSString *helperPath = [[streamdPath stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"privhelper"];
    if (![helperPath hasSuffix:@"/StreamControl.app/privhelper"] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
        TLinkHelperLog([NSString stringWithFormat:
            @"ensure-streamd: auxiliary helper unavailable path=%@", helperPath ?: @""]);
        return;
    }

    char *arg0 = strdup([helperPath fileSystemRepresentation]);
    char *arg1 = strdup("--ensure-auxiliaries");
    char *arg2 = strdup([streamdPath fileSystemRepresentation]);
    char *arg3 = replaceExisting ? strdup("--replace") : NULL;
    if (!arg0 || !arg1 || !arg2 || (replaceExisting && !arg3)) {
        free(arg0); free(arg1); free(arg2); free(arg3);
        TLinkHelperLog(@"ensure-streamd: auxiliary argv alloc failed");
        return;
    }
    char *const argv[] = { arg0, arg1, arg2, arg3, NULL };
    pid_t pid = -1;
    int rc = posix_spawn(&pid, arg0, NULL, NULL, argv, environ);
    free(arg0); free(arg1); free(arg2); free(arg3);
    TLinkHelperLog([NSString stringWithFormat:
        @"ensure-streamd: core_ready_auxiliary_ensure_spawned pid=%d rc=%d replace=%d",
        pid, rc, replaceExisting ? 1 : 0]);
}

static int TLinkEnsureStreamd(NSString *streamdPath, BOOL replaceExisting)
{
    NSString *normalized = TLinkHelperNormalizedPath(streamdPath);
    if (!TLinkHelperStreamdPathAllowed(normalized)) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: refused path=%@", streamdPath ?: @""]);
        return 40;
    }
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:normalized]) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: not executable path=%@", normalized]);
        return 41;
    }

    NSString *uiProbe = TLinkHelperSendLoopbackLine(@"ping\n", 6017, 1);
    if (replaceExisting || !TLinkUIServiceProbeIsCurrent(uiProbe)) {
        // Release an old, unresponsive, or explicitly replaced hosted UI
        // service before core recovery. v17 is relaunched by the detached
        // auxiliary ensure or on demand by clipboardd.
        TLinkHelperKillProcessNamed("TLinkUIService");
        TLinkHelperLog([NSString stringWithFormat:
            @"ensure-streamd: uiservice reset_and_deferred replace=%d probe=%@",
            replaceExisting ? 1 : 0,
            [uiProbe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                ?: @"<none>"]);
    }

    NSString *before = TLinkHelperSendLocalTaskLine(@"97\n", 1);
    if (before.length > 0 && !replaceExisting) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: already responding %@", [before stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
        TLinkSpawnAuxiliaryEnsure(normalized, NO);
        return 0;
    }

    if (before.length > 0) {
        NSString *shutdown = TLinkHelperSendLocalTaskLine(@"96\n", 1);
        TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: task96 response %@", [shutdown stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"<nil>"]);
        usleep(400000);
    }

    int killExit = TLinkKillStreamd(-1);
    TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: cleanup exit=%d replace=%d", killExit, replaceExisting ? 1 : 0]);
    usleep(250000);

    const char *cpath = [normalized fileSystemRepresentation];
    char *arg0 = strdup(cpath);
    char *arg1 = strdup("--daemon");
    if (!arg0 || !arg1) {
        free(arg0); free(arg1);
        TLinkHelperLog(@"ensure-streamd: argv alloc failed");
        return 42;
    }
    char *const spawnArgv[] = { arg0, arg1, NULL };

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, &attr, spawnArgv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1);

    if (rc != 0) {
        TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: spawn failed rc=%d path=%@", rc, normalized]);
        return 43;
    }

    TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: spawned pid=%d path=%@ uid=%d euid=%d", pid, normalized, getuid(), geteuid()]);
    for (int i = 0; i < 12; i++) {
        usleep(250000);
        NSString *probe = TLinkHelperSendLocalTaskLine(@"97\n", 1);
        if (probe.length > 0) {
            TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: probe ok attempt=%d %@", i + 1, [probe stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]]);
            TLinkSpawnAuxiliaryEnsure(normalized, replaceExisting);
            return 0;
        }
    }

    TLinkHelperLog([NSString stringWithFormat:@"ensure-streamd: spawned pid=%d but tcp/6000 did not respond", pid]);
    return 44;
}

static pid_t TLinkHelperPidForBundleId(NSString *bundleId)
{
    NSString *bundlePath = TLinkHelperBundlePathForBundleId(bundleId);
    if (bundlePath.length == 0) {
        TLinkHelperLog([NSString stringWithFormat:@"pid-for-bundle: bundle path unavailable bundle=%@", bundleId]);
        return 0;
    }

    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        TLinkHelperLog([NSString stringWithFormat:@"pid-for-bundle: sysctl sizing failed bundle=%@ errno=%d", bundleId, errno]);
        return 0;
    }

    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) {
        TLinkHelperLog([NSString stringWithFormat:@"pid-for-bundle: alloc failed bundle=%@", bundleId]);
        return 0;
    }

    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        TLinkHelperLog([NSString stringWithFormat:@"pid-for-bundle: sysctl list failed bundle=%@ errno=%d", bundleId, errno]);
        free(procs);
        return 0;
    }

    pid_t found = 0;
    int count = (int)(len / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1) continue;
        char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
        int got = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
        if (got <= 0) continue;
        NSString *procPath = TLinkHelperNormalizedPath([NSString stringWithUTF8String:pathbuf] ?: @"");
        if (procPath.length > 0 && [procPath hasPrefix:bundlePath]) {
            found = pid;
            break;
        }
    }

    free(procs);
    TLinkHelperLog([NSString stringWithFormat:@"pid-for-bundle: bundle=%@ path=%@ pid=%d", bundleId, bundlePath, found]);
    return found;
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

static int TLinkKillBundle(NSString *bundleId)
{
    if (bundleId.length == 0) {
        TLinkHelperLog(@"kill-bundle: missing bundle id");
        return 22;
    }
    if ([bundleId isEqualToString:@"com.apple.springboard"]) {
        TLinkHelperLog(@"kill-bundle: refusing SpringBoard");
        return 23;
    }

    pid_t pid = TLinkHelperPidForBundleId(bundleId);
    if (pid <= 0) {
        TLinkHelperLog([NSString stringWithFormat:@"kill-bundle: app not running bundle=%@", bundleId]);
        return 24;
    }

    errno = 0;
    int termRc = kill(pid, SIGTERM);
    TLinkHelperLog([NSString stringWithFormat:@"kill-bundle: SIGTERM bundle=%@ pid=%d rc=%d errno=%d", bundleId, pid, termRc, errno]);
    if (termRc != 0 && errno != ESRCH) return 25;

    usleep(500000);
    if (TLinkHelperPidIsAlive(pid)) {
        errno = 0;
        int killRc = kill(pid, SIGKILL);
        TLinkHelperLog([NSString stringWithFormat:@"kill-bundle: SIGKILL bundle=%@ pid=%d rc=%d errno=%d", bundleId, pid, killRc, errno]);
        if (killRc != 0 && errno != ESRCH) return 26;
    }
    return 0;
}

static int TLinkClearBundleData(NSString *bundleId)
{
    if (bundleId.length == 0) {
        TLinkHelperLog(@"clear-data: missing bundle id");
        return 50;
    }
    if ([bundleId isEqualToString:@"com.apple.springboard"] ||
        [bundleId isEqualToString:@"com.tlinkauto.streamcontrol"]) {
        TLinkHelperLog([NSString stringWithFormat:@"clear-data: refusing protected bundle=%@", bundleId]);
        return 51;
    }

    NSString *dataPath = TLinkHelperDataPathForBundleId(bundleId);
    if (!TLinkHelperDataPathAllowed(dataPath)) {
        TLinkHelperLog([NSString stringWithFormat:@"clear-data: refused unsafe data path bundle=%@ path=%@", bundleId, dataPath ?: @""]);
        return 52;
    }

    int killExit = TLinkKillBundle(bundleId);
    if (killExit != 0 && killExit != 24) {
        TLinkHelperLog([NSString stringWithFormat:@"clear-data: kill failed bundle=%@ exit=%d", bundleId, killExit]);
        return 53;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dataPath isDirectory:&isDir] || !isDir) {
        TLinkHelperLog([NSString stringWithFormat:@"clear-data: data path missing bundle=%@ path=%@", bundleId, dataPath]);
        return 54;
    }

    NSError *listError = nil;
    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:dataPath error:&listError];
    if (!items) {
        TLinkHelperLog([NSString stringWithFormat:@"clear-data: list failed bundle=%@ path=%@ error=%@", bundleId, dataPath, listError.localizedDescription ?: @"unknown"]);
        return 55;
    }

    int removed = 0;
    int failed = 0;
    NSSet<NSString *> *preserve = [NSSet setWithObjects:
        @".com.apple.mobile_container_manager.metadata.plist",
        @".com.apple.mobile_container_manager.metadata.plist.lockfile",
        nil];
    for (NSString *item in items) {
        if ([preserve containsObject:item]) continue;
        NSString *child = [dataPath stringByAppendingPathComponent:item];
        NSString *normalizedChild = TLinkHelperNormalizedPath(child);
        if (![normalizedChild hasPrefix:[dataPath stringByAppendingString:@"/"]]) {
            TLinkHelperLog([NSString stringWithFormat:@"clear-data: skipped suspicious child=%@", child]);
            failed++;
            continue;
        }
        NSError *removeError = nil;
        if ([fm removeItemAtPath:child error:&removeError]) {
            removed++;
        } else {
            failed++;
            TLinkHelperLog([NSString stringWithFormat:@"clear-data: remove failed child=%@ error=%@", child, removeError.localizedDescription ?: @"unknown"]);
        }
    }

    TLinkHelperLog([NSString stringWithFormat:@"clear-data: bundle=%@ path=%@ removed=%d failed=%d killExit=%d", bundleId, dataPath, removed, failed, killExit]);
    return failed == 0 ? 0 : 56;
}

static BOOL TLinkHelperOpenURLWithWorkspace(NSString *rawURL)
{
    if (rawURL.length == 0) return NO;
    NSURL *url = [NSURL URLWithString:rawURL];
    if (!url) return NO;

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

    SEL openSel = NSSelectorFromString(@"openURL:");
    if (![workspace respondsToSelector:openSel]) return NO;
    @try {
        return ((BOOL (*)(id, SEL, NSURL *))objc_msgSend)(workspace, openSel, url);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static int TLinkOpenURL(NSString *rawURL)
{
    if (rawURL.length == 0) {
        TLinkHelperLog(@"open-url: missing url");
        return 30;
    }

    NSString *lowerRaw = [rawURL lowercaseString];
    NSString *fallback = nil;
    BOOL preferencesURL = NO;
    if ([lowerRaw hasPrefix:@"prefs:"]) {
        fallback = [@"App-Prefs:" stringByAppendingString:[rawURL substringFromIndex:6]];
        preferencesURL = YES;
    } else if ([lowerRaw hasPrefix:@"app-prefs:"]) {
        preferencesURL = YES;
    }

    if (TLinkHelperOpenURLWithWorkspace(rawURL)) {
        TLinkHelperLog([NSString stringWithFormat:@"open-url: workspace ok url=%@", rawURL]);
        return 0;
    }

    if (fallback.length > 0 && TLinkHelperOpenURLWithWorkspace(fallback)) {
        TLinkHelperLog([NSString stringWithFormat:@"open-url: fallback ok url=%@", fallback]);
        return 0;
    }

    if (preferencesURL && TLinkOpenBundle(@"com.apple.Preferences") == 0) {
        TLinkHelperLog([NSString stringWithFormat:@"open-url: opened Preferences fallback for url=%@", rawURL]);
        return 0;
    }

    TLinkHelperLog([NSString stringWithFormat:@"open-url: failed url=%@", rawURL]);
    return 31;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc >= 2 && strcmp(argv[1], "--version") == 0) {
            TLinkHelperLog(@"privhelper version=11 scope=ensure-streamd,ensure-auxiliaries,ensure-clipboardd,ensure-uiservice-mobile,ensure-vpnagent-mobile,configure-vpn-root,kill-streamd,open-bundle,kill-bundle,open-url,clear-data,respring,license-gate");
            return 0;
        }

        if (argc >= 3 && strcmp(argv[1], "--ensure-streamd") == 0) {
            NSString *streamdPath = [NSString stringWithUTF8String:argv[2]] ?: @"";
            BOOL replaceExisting = NO;
            for (int i = 3; i < argc; i++) {
                if (strcmp(argv[i], "--replace") == 0) replaceExisting = YES;
            }
            return TLinkEnsureStreamd(streamdPath, replaceExisting);
        }

        if (argc >= 3 && strcmp(argv[1], "--ensure-auxiliaries") == 0) {
            NSString *streamdPath = [NSString stringWithUTF8String:argv[2]] ?: @"";
            NSString *normalized = TLinkHelperNormalizedPath(streamdPath);
            if (!TLinkHelperStreamdPathAllowed(normalized)) {
                TLinkHelperLog([NSString stringWithFormat:
                    @"ensure-auxiliaries: refused streamd path=%@", streamdPath]);
                return 60;
            }
            BOOL replaceExisting = NO;
            for (int i = 3; i < argc; i++) {
                if (strcmp(argv[i], "--replace") == 0) replaceExisting = YES;
            }
            int clipboardExit = TLinkEnsureClipboardd(normalized, replaceExisting);
            int vpnagentExit = TLinkEnsureVPNAgent(normalized, replaceExisting);
            TLinkHelperLog([NSString stringWithFormat:
                @"ensure-auxiliaries: clipboardd=%d vpnagent=%d replace=%d core_unblocked=1",
                clipboardExit, vpnagentExit, replaceExisting ? 1 : 0]);
            return clipboardExit != 0 ? clipboardExit : vpnagentExit;
        }

        if (argc >= 3 && strcmp(argv[1], "--ensure-vpnagent") == 0) {
            NSString *streamdPath = [NSString stringWithUTF8String:argv[2]] ?: @"";
            NSString *normalized = TLinkHelperNormalizedPath(streamdPath);
            if (!TLinkHelperStreamdPathAllowed(normalized)) {
                TLinkHelperLog([NSString stringWithFormat:
                    @"ensure-vpnagent: refused streamd path=%@", streamdPath]);
                return 59;
            }
            return TLinkEnsureVPNAgent(normalized, NO);
        }

        if (argc == 3 &&
            (strcmp(argv[1], "--configure-vpn") == 0 ||
             strcmp(argv[1], "--configure-legacy-vpn") == 0)) {
            NSString *requestPath =
                [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkHelperConfigureVPN(requestPath);
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
            int licenseExit = TLinkHelperRequireLicense(@"automation", @"open-bundle");
            if (licenseExit != 0) return licenseExit;
            NSString *bundleId = [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkOpenBundle(bundleId);
        }

        if (argc >= 3 && strcmp(argv[1], "--kill-bundle") == 0) {
            int licenseExit = TLinkHelperRequireLicense(@"admin", @"kill-bundle");
            if (licenseExit != 0) return licenseExit;
            NSString *bundleId = [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkKillBundle(bundleId);
        }

        if (argc >= 3 && strcmp(argv[1], "--open-url") == 0) {
            int licenseExit = TLinkHelperRequireLicense(@"automation", @"open-url");
            if (licenseExit != 0) return licenseExit;
            NSString *rawURL = [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkOpenURL(rawURL);
        }

        if (argc >= 3 && strcmp(argv[1], "--clear-data") == 0) {
            int licenseExit = TLinkHelperRequireLicense(@"admin", @"clear-data");
            if (licenseExit != 0) return licenseExit;
            NSString *bundleId = [NSString stringWithUTF8String:argv[2]] ?: @"";
            return TLinkClearBundleData(bundleId);
        }

        if (argc >= 2 && strcmp(argv[1], "--respring") == 0) {
            int licenseExit = TLinkHelperRequireLicense(@"admin", @"respring");
            if (licenseExit != 0) return licenseExit;
            return TLinkRespring();
        }

        TLinkHelperLog(@"usage: privhelper --version | --ensure-streamd /path/to/streamd [--replace] | --ensure-auxiliaries /path/to/streamd [--replace] | --ensure-vpnagent /path/to/streamd | --configure-vpn /var/mobile/Library/TLinkauto/tmp/vpn-private-requests/vpnconf-UUID.plist | --kill-streamd [--except-pid pid] | --open-bundle bundle.id | --kill-bundle bundle.id | --open-url url | --clear-data bundle.id | --respring");
        return 64;
    }
}
