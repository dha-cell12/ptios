#ifndef TLINK_H264_SOCKET_H
#define TLINK_H264_SOCKET_H
#include "TLinkH264Timing.h"
#include <sys/socket.h>
#include <poll.h>
#include <errno.h>
// Socket lifetime belongs to the stream loop. All chunks of one access unit
// share its send window, including tables, PES and raw framing headers.
class TLinkH264Socket {
    int fd_;
    TLinkH264SendWindow window_;
public:
    explicit TLinkH264Socket(int fd, uint64_t idle = 2000000000ULL, uint64_t whole = 5000000000ULL) : fd_(fd), window_(idle, whole) { begin(); }
    void begin() { window_.begin(TLinkH264NowNs()); }
    bool send(const uint8_t *bytes, size_t length) {
        const int fd = fd_;
        return TLinkH264Send(window_, bytes, length, [] { return TLinkH264NowNs(); },
            [fd](const uint8_t *p, size_t n) -> long long {
                int flags = MSG_DONTWAIT;
#ifdef MSG_NOSIGNAL
                flags |= MSG_NOSIGNAL;
#endif
                const ssize_t result = ::send(fd, p, n, flags);
                if (result < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) return -2;
                return result;
            }, [fd](uint64_t remaining) {
                struct pollfd item = {fd, POLLOUT, 0};
                const int milliseconds = static_cast<int>((remaining + 999999) / 1000000);
                const int result = poll(&item, 1, milliseconds);
                if (result < 0) return errno == EINTR;
                return result == 0 || !(item.revents & (POLLERR | POLLHUP | POLLNVAL));
            });
    }
};
#endif
