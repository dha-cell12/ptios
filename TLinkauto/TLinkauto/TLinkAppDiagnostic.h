#ifndef TLINK_APP_DIAGNOSTIC_H
#define TLINK_APP_DIAGNOSTIC_H

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <unistd.h>
#import <pthread.h>
#import <mach/mach_time.h>
#import <stdarg.h>
#import <stdio.h>

static inline void TLinkAppWriteDiagnostic(const char *checkpoint,
                                            const char *format, ...)
{
    // App ghi cùng file với tweak, dùng prefix [APP] để phân biệt
    const char *path =
        "/var/mobile/Library/Logs/tlinkauto-js-diagnostic.log";

    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        fd = open("/tmp/tlinkauto-js-diagnostic.log",
                  O_WRONLY | O_CREAT | O_APPEND,
                  0644);
    }

    if (fd < 0) {
        return;
    }

    char message[2048] = {0};

    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);

    uint64_t timestamp = mach_absolute_time();
    uint64_t threadId = 0;
    pthread_threadid_np(NULL, &threadId);

    char line[2560] = {0};

    int length = snprintf(
        line,
        sizeof(line),
        "[%llu] [APP][%s] pid=%d tid=%llu main=%d %s\n",
        (unsigned long long)timestamp,
        checkpoint ? checkpoint : "UNKNOWN",
        getpid(),
        (unsigned long long)threadId,
        [NSThread isMainThread] ? 1 : 0,
        message
    );

    if (length > 0) {
        size_t writeLength =
            (size_t)MIN(length, (int)sizeof(line) - 1);
        write(fd, line, writeLength);
    }

    close(fd);
}

#define APP_DIAG(checkpoint, format, ...) \
    TLinkAppWriteDiagnostic(              \
        checkpoint,                       \
        format,                           \
        ##__VA_ARGS__                     \
    )

#endif
