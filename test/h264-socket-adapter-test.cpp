#include "../shared/TLinkH264Timing.h"
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <vector>
#ifdef _WIN32
using ssize_t = long long;
enum { F_GETFL = 1, F_SETFL = 2, O_NONBLOCK = 4, MSG_DONTWAIT = 8, POLLOUT = 16,
       POLLERR = 32, POLLHUP = 64, POLLNVAL = 128 };
struct pollfd { int fd; short events; short revents; };
#else
#include <fcntl.h>
#include <sys/socket.h>
#include <poll.h>
#endif
static int currentFlags, getCalls, setCalls, sendCalls, pollCalls;
static bool failGet, failSet, retrySend;
static std::vector<uint8_t> received;
static int fixtureFcntl(int fd, int operation, int value) {
    assert(fd == 7);
    if (operation == F_GETFL) { ++getCalls; return failGet ? -1 : currentFlags; }
    assert(operation == F_SETFL); ++setCalls;
    assert((value & currentFlags) == currentFlags); // Preserve every pre-existing flag.
    if (failSet) return -1;
    currentFlags = value; return 0;
}
static ssize_t fixtureSend(int fd, const void *bytes, size_t length, int flags) {
    assert(fd == 7 && (flags & MSG_DONTWAIT));
    assert(currentFlags & O_NONBLOCK); // Deadline loop must never enter a blocking FD.
    ++sendCalls;
    if (retrySend) { retrySend = false; errno = EAGAIN; return -1; }
    const uint8_t *p = static_cast<const uint8_t *>(bytes);
    size_t n = std::min(size_t(3), length); received.insert(received.end(), p, p + n);
    return static_cast<ssize_t>(n);
}
static int fixturePoll(struct pollfd *item, unsigned long count, int milliseconds) {
    assert(count == 1 && item->fd == 7 && item->events == POLLOUT);
    assert(milliseconds > 0 && milliseconds <= 50);
    ++pollCalls; item->revents = POLLOUT; return 1;
}
#include "H264SocketUnderTest.inc"
static void reset(int flags) {
    currentFlags = flags; getCalls = setCalls = sendCalls = pollCalls = 0;
    failGet = failSet = retrySend = false; received.clear();
}
int main() {
    const uint8_t bytes[] = {1, 2, 3, 4, 5, 6, 7};
    reset(0x10000000); failGet = true;
    TLinkH264Socket failedGet(7); assert(!failedGet.send(bytes, sizeof(bytes)));
    assert(getCalls == 1 && setCalls == 0 && sendCalls == 0);
    reset(0x10000000); failSet = true;
    TLinkH264Socket failedSet(7); assert(!failedSet.send(bytes, sizeof(bytes)));
    assert(getCalls == 1 && setCalls == 1 && sendCalls == 0);
    reset(0x10000000);
    TLinkH264Socket writer(7);
    assert(getCalls == 1 && setCalls == 1 && currentFlags == (0x10000000 | O_NONBLOCK));
    retrySend = true; assert(writer.send(bytes, sizeof(bytes)));
    assert(sendCalls == 4 && pollCalls == 1 && received == std::vector<uint8_t>(bytes, bytes + sizeof(bytes)));
    reset(O_NONBLOCK);
    TLinkH264Socket existing(7); existing.begin(); assert(existing.send(bytes, sizeof(bytes)));
    assert(getCalls == 1 && setCalls == 0 && received == std::vector<uint8_t>(bytes, bytes + sizeof(bytes)));
    puts("H264 socket adapter passed: O_NONBLOCK setup/flag preservation, existing mode, fail-closed fcntl errors and exact partial/EAGAIN writes.");
}
