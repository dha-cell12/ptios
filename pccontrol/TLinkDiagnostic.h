#ifndef TLINK_DIAGNOSTIC_H
#define TLINK_DIAGNOSTIC_H

#import <Foundation/Foundation.h>
#import <fcntl.h>
#import <unistd.h>
#import <pthread.h>
#import <mach/mach_time.h>
#import <stdarg.h>
#import <stdio.h>

static inline void TLinkWriteDiagnostic(const char *checkpoint,
                                 const char *format, ...)
{
    const char *path =
        "/var/mobile/Library/Logs/tlinkauto-js-diagnostic.log";

    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        // Fallback nếu thư mục Logs không tồn tại/quyền không phù hợp.
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
        "[%llu] [%s] pid=%d tid=%llu main=%d %s\n",
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

        // O_APPEND + một lần write giúp các dòng ngắn không đè lên nhau.
        write(fd, line, writeLength);
    }

    close(fd);
}

#define JS_DIAG(checkpoint, format, ...) \
    TLinkWriteDiagnostic(                \
        checkpoint,                      \
        format,                          \
        ##__VA_ARGS__                    \
    )

#endif
