#ifndef TLINK_SUPERVISOR_WATCH_H
#define TLINK_SUPERVISOR_WATCH_H
#include <cstdint>
namespace TLinkSupervisorWatch {
// Invalid/regressed clocks keep one full throttle instead of scheduling an
// unbounded wall-clock delay or bypassing the crash-loop protection.
static inline uint64_t remainingMs(uint64_t started,uint64_t now,uint64_t throttle){
    if(started==UINT64_MAX||now==UINT64_MAX||now<started)return throttle;
    const uint64_t age=now-started;return age>=throttle?0:throttle-age;
}
}
#endif
