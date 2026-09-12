#import "TLinkVPNPrivateRequest.h"

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

extern "C" {
int posix_spawnattr_set_persona_np(
    posix_spawnattr_t *attr, uid_t persona_id, uint32_t flags);
int posix_spawnattr_set_persona_uid_np(posix_spawnattr_t *attr, uid_t uid);
int posix_spawnattr_set_persona_gid_np(posix_spawnattr_t *attr, uid_t gid);
}

static NSString *const kTLinkVPNRequestDirectory =
    @"/var/mobile/Library/TLinkauto/tmp/vpn-private-requests";

static NSDictionary *TLinkVPNRequestResult(
    BOOL ok,
    NSString *code,
    NSDictionary *extra)
{
    NSMutableDictionary *result = extra
        ? [extra mutableCopy] : [NSMutableDictionary dictionary];
    result[@"ok"] = @(ok);
    result[@"code"] = code ?: (ok ? @"ok" : @"unknown_error");
    return result;
}

static BOOL TLinkVPNRequestWriteAll(int fd, NSData *data)
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

NSDictionary *TLinkVPNRunPrivateConfigurationHelper(
    NSString *helperPath,
    NSDictionary *configuration)
{
    uid_t callerUID = geteuid();
    gid_t callerGID = getegid();
    BOOL trustedIdentity = callerUID == 0 ||
        (callerUID == 501 && callerGID == 501);
    if (!trustedIdentity) {
        return TLinkVPNRequestResult(NO,
            @"vpn_private_request_trusted_identity_required", @{
                @"caller_uid": @(callerUID),
                @"caller_gid": @(callerGID),
            });
    }
    if (![helperPath hasSuffix:@"/StreamControl.app/privhelper"] ||
        ![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
        return TLinkVPNRequestResult(
            NO, @"vpn_private_helper_missing", nil);
    }
    if (![configuration isKindOfClass:[NSDictionary class]]) {
        return TLinkVPNRequestResult(
            NO, @"vpn_private_request_invalid", nil);
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    if (![fm createDirectoryAtPath:kTLinkVPNRequestDirectory
       withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0700}
                             error:&directoryError]) {
        return TLinkVPNRequestResult(NO,
            @"vpn_private_request_directory_failed", @{
                @"native_error":
                    directoryError.localizedDescription ?: @"unknown",
            });
    }
    if (callerUID == 0) {
        chown(kTLinkVPNRequestDirectory.fileSystemRepresentation, 501, 501);
    }
    chmod(kTLinkVPNRequestDirectory.fileSystemRepresentation, 0700);
    struct stat directoryStat = {};
    if (lstat(kTLinkVPNRequestDirectory.fileSystemRepresentation,
              &directoryStat) != 0 ||
        !S_ISDIR(directoryStat.st_mode) ||
        directoryStat.st_uid != 501 ||
        (directoryStat.st_mode & 077) != 0) {
        return TLinkVPNRequestResult(
            NO, @"vpn_private_request_directory_unsafe", nil);
    }

    NSString *requestID = [[NSUUID UUID] UUIDString];
    NSString *requestPath = [kTLinkVPNRequestDirectory
        stringByAppendingPathComponent:[NSString stringWithFormat:
            @"vpnconf-%@.plist", requestID]];
    NSString *resultPath = [requestPath stringByAppendingString:@".result"];

    NSMutableDictionary *request = [@{
        @"version": @2,
        @"request_id": requestID,
        @"created_at": @([[NSDate date] timeIntervalSince1970]),
    } mutableCopy];
    NSArray<NSString *> *allowedFields = @[
        @"profile_type", @"server", @"remote_identifier", @"username",
        @"password", @"shared_secret", @"group_name", @"display_name",
        @"encryption_level", @"send_all_traffic",
    ];
    for (NSString *key in allowedFields) {
        id value = configuration[key];
        if (value && value != (id)kCFNull) request[key] = value;
    }

    NSError *serializeError = nil;
    NSData *requestData = [NSPropertyListSerialization
        dataWithPropertyList:request
                     format:NSPropertyListBinaryFormat_v1_0
                    options:0
                      error:&serializeError];
    if (!requestData || requestData.length > 16384) {
        return TLinkVPNRequestResult(NO,
            @"vpn_private_request_serialize_failed", @{
                @"native_error":
                    serializeError.localizedDescription ?: @"unknown",
            });
    }

    int requestFd = open(requestPath.fileSystemRepresentation,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (requestFd < 0) {
        return TLinkVPNRequestResult(NO,
            @"vpn_private_request_create_failed", @{
                @"native_errno": @(errno),
            });
    }
    BOOL requestWritten = fchmod(requestFd, 0600) == 0 &&
        (callerUID != 0 || fchown(requestFd, 501, 501) == 0) &&
        TLinkVPNRequestWriteAll(requestFd, requestData);
    if (requestWritten) requestWritten = fsync(requestFd) == 0;
    close(requestFd);
    if (!requestWritten) {
        [fm removeItemAtPath:requestPath error:nil];
        return TLinkVPNRequestResult(
            NO, @"vpn_private_request_write_failed", nil);
    }

    const char *cpath = helperPath.fileSystemRepresentation;
    char *arg0 = strdup(cpath);
    char *arg1 = strdup("--configure-vpn");
    char *arg2 = strdup(requestPath.fileSystemRepresentation);
    if (!arg0 || !arg1 || !arg2) {
        free(arg0); free(arg1); free(arg2);
        [fm removeItemAtPath:requestPath error:nil];
        return TLinkVPNRequestResult(
            NO, @"vpn_private_helper_argv_failed", nil);
    }
    char *const argv[] = {arg0, arg1, arg2, NULL};
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int persona = posix_spawnattr_set_persona_np(
        &attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int personaUid = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int personaGid = posix_spawnattr_set_persona_gid_np(&attr, 0);
    pid_t pid = -1;
    int spawnResult = posix_spawn(
        &pid, cpath, NULL, &attr, argv, environ);
    posix_spawnattr_destroy(&attr);
    free(arg0); free(arg1); free(arg2);
    if (spawnResult != 0) {
        [fm removeItemAtPath:requestPath error:nil];
        return TLinkVPNRequestResult(NO,
            @"vpn_private_helper_spawn_failed", @{
                @"spawn_result": @(spawnResult),
                @"persona_result": @(persona),
                @"persona_uid_result": @(personaUid),
                @"persona_gid_result": @(personaGid),
            });
    }

    int status = 0;
    pid_t waited = -1;
    do {
        waited = waitpid(pid, &status, 0);
    } while (waited < 0 && errno == EINTR);
    [fm removeItemAtPath:requestPath error:nil];

    struct stat resultStat = {};
    NSDictionary *result = nil;
    if (lstat(resultPath.fileSystemRepresentation, &resultStat) == 0 &&
        S_ISREG(resultStat.st_mode) &&
        resultStat.st_uid == 501 &&
        (resultStat.st_mode & 077) == 0 &&
        resultStat.st_nlink == 1 &&
        resultStat.st_size > 0 && resultStat.st_size <= 65536) {
        NSDictionary *candidate =
            [NSDictionary dictionaryWithContentsOfFile:resultPath];
        if ([candidate isKindOfClass:[NSDictionary class]] &&
            [candidate[@"request_id"] isEqualToString:requestID] &&
            [candidate[@"version"] integerValue] == 2) {
            result = candidate;
        }
    }
    [fm removeItemAtPath:resultPath error:nil];
    if (!result) {
        return TLinkVPNRequestResult(NO,
            @"vpn_private_helper_result_missing", @{
                @"helper_exit": @(
                    waited == pid && WIFEXITED(status)
                        ? WEXITSTATUS(status) : -1),
                @"helper_wait": @(waited),
            });
    }
    NSMutableDictionary *clean = [result mutableCopy];
    [clean removeObjectForKey:@"request_id"];
    [clean removeObjectForKey:@"version"];
    clean[@"helper_exit"] = @(
        waited == pid && WIFEXITED(status) ? WEXITSTATUS(status) : -1);
    return clean;
}
