#ifndef TLINK_SUPERVISOR_HELPER_H
#define TLINK_SUPERVISOR_HELPER_H
#include <atomic>

// A helper owns this process-local lane until its child/reaper state retires.
namespace TLinkSupervisorHelper {
inline std::atomic<bool> &pending(){static std::atomic<bool> value{false};return value;}
class Lease {
    bool held_;
public:
    Lease():held_(!pending().exchange(true)){}
    ~Lease(){if(held_)pending().store(false);}
    bool held()const{return held_;}
    Lease(const Lease &)=delete;
    Lease &operator=(const Lease &)=delete;
};
inline bool busy(){return pending().load();}
}
#endif
