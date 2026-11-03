#include <cassert>
#include <cerrno>
#if defined(_WIN32)
using pid_t=int;
#else
#include <sys/types.h>
#endif
static pid_t (*watchWaitProvider)(pid_t,int *,int)=nullptr;
static inline pid_t fixtureWatcherWait(pid_t pid,int *status,int flags){assert(watchWaitProvider);return watchWaitProvider(pid,status,flags);}
struct WatchWaitResult {pid_t pid;int status;};
static inline WatchWaitResult runWatcherWait(pid_t pid){
#define waitpid fixtureWatcherWait
#include "WatchWaitUnderTest.inc"
#undef waitpid
    return {w,status};
}
