#ifndef TLINK_VPN_HELPER_CHILD_H
#define TLINK_VPN_HELPER_CHILD_H
#include <algorithm>
#include <atomic>
#include <cstdint>

namespace TLinkVPNHelperChild {
enum class Probe {Running, Reaped, Missing, Retry, Error};
enum class Reason {Finished, Timeout, WaitFailed};
enum class Signal {Term, Kill};
struct Ops {
    void *context;
    uint64_t (*now)(void *);
    Probe (*probe)(void *, int, int &, int &);
    int (*signal)(void *, int, Signal);
    void (*sleep)(void *, unsigned);
};
struct Result {
    Reason reason=Reason::Finished;
    int status=0,error=0,signalError=0;
    bool retired=false,termAttempted=false,killAttempted=false;
};
enum : unsigned {TimeoutMs=30000, GraceMs=250, PollMs=10, MaxChildren=4};
inline std::atomic<unsigned> &pending(){static std::atomic<unsigned> count{0};return count;}
class Slot {
    bool held_=false;
public:
    Slot(){
        unsigned count=pending().load();
        while(count<MaxChildren){if(pending().compare_exchange_weak(count,count+1)){held_=true;break;}}
    }
    ~Slot(){if(held_)pending().fetch_sub(1);}
    bool held()const{return held_;}
    Slot(const Slot &)=delete;
    Slot &operator=(const Slot &)=delete;
};
inline unsigned remaining(uint64_t start,uint64_t now,unsigned duration){
    if(now==UINT64_MAX||now<start||now-start>=duration)return 0;
    return static_cast<unsigned>(duration-(now-start));
}
inline Probe observe(const Ops &ops,int pid,Result &result){
    int error=0;
    const Probe probe=ops.probe(ops.context,pid,result.status,error);
    if(probe==Probe::Reaped||probe==Probe::Missing)result.retired=true;
    if(error)result.error=error;
    return probe;
}
inline void signal(const Ops &ops,int pid,Signal kind,Result &result){
    if(kind==Signal::Term)result.termAttempted=true;else result.killAttempted=true;
    const int error=ops.signal(ops.context,pid,kind);
    if(error)result.signalError=error;
}
// Only the exact positive child PID is probed/signalled. Never wait synchronously
// after SIGKILL: an uninterruptible child must keep its owner and admission slot.
inline Result wait(const Ops &ops,int pid,unsigned timeout=TimeoutMs,unsigned grace=GraceMs){
    Result result;
    if(pid<=0){result.reason=Reason::WaitFailed;result.retired=true;return result;}
    const uint64_t start=ops.now(ops.context);
    for(;;){
        if(!remaining(start,ops.now(ops.context),timeout)){result.reason=Reason::Timeout;break;}
        const Probe probe=observe(ops,pid,result);
        if(!remaining(start,ops.now(ops.context),timeout)){result.reason=Reason::Timeout;break;}
        if(probe==Probe::Reaped)return result;
        if(probe==Probe::Missing||probe==Probe::Error){result.reason=Reason::WaitFailed;break;}
        ops.sleep(ops.context,std::min<unsigned>(PollMs,remaining(start,ops.now(ops.context),timeout)));
    }
    for(unsigned phase=0;phase<2&&!result.retired;++phase){
        const uint64_t began=ops.now(ops.context);
        bool attempted=false;
        while(remaining(began,ops.now(ops.context),grace)){
            const Probe probe=observe(ops,pid,result);
            if(result.retired)break;
            if(probe==Probe::Error)break;
            if(probe==Probe::Running&&!attempted){
                signal(ops,pid,phase==0?Signal::Term:Signal::Kill,result);attempted=true;
            }
            ops.sleep(ops.context,std::min<unsigned>(PollMs,remaining(began,ops.now(ops.context),grace)));
        }
    }
    if(!result.retired)observe(ops,pid,result);
    return result;
}
}

// The GCD owner uses ARC-managed source references and Objective-C blocks.
#if defined(__APPLE__) && defined(__OBJC__)
#include <dispatch/dispatch.h>
#include <cerrno>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
namespace TLinkVPNHelperChild {
inline Ops posixOps(){
    return {nullptr,
        [](void *){return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());},
        [](void *,int pid,int &status,int &error){
            const pid_t waited=::waitpid(pid,&status,WNOHANG);
            if(waited==pid)return Probe::Reaped;
            if(waited==0)return Probe::Running;
            error=errno;return error==ECHILD?Probe::Missing:(error==EINTR?Probe::Retry:Probe::Error);
        },
        [](void *,int pid,Signal kind){return ::kill(pid,kind==Signal::Term?SIGTERM:SIGKILL)==0?0:errno;},
        [](void *,unsigned ms){std::this_thread::sleep_for(std::chrono::milliseconds(ms));}};
}
inline dispatch_queue_t reaperQueue(){
    static dispatch_queue_t queue=dispatch_queue_create("com.tlinkauto.vpn.helper-reaper",DISPATCH_QUEUE_SERIAL);
    return queue;
}
class Owner {
    struct State {
        Slot slot;
        Ops ops;
        std::mutex mutex;
        int pid=0;
        Result result;
        dispatch_source_t timer=nullptr;
        std::string requestPath,resultPath;
        bool requestOwned=false,resultOwned=false;
        explicit State(Ops value):ops(value){}
        void removeFiles(){
            if(requestOwned)::unlink(requestPath.c_str());
            if(resultOwned)::unlink(resultPath.c_str());
        }
        void retire(){
            removeFiles();
            dispatch_source_t source=timer;timer=nullptr;
            if(source){dispatch_source_set_event_handler(source,^{});dispatch_source_cancel(source);}
        }
        void reap(){
            std::lock_guard<std::mutex> guard(mutex);
            if(pid<=0)return;
            const Probe probe=observe(ops,pid,result);
            if(result.retired){pid=0;retire();}
            else if(probe==Probe::Running&&!result.killAttempted)signal(ops,pid,Signal::Kill,result);
        }
    };
    std::shared_ptr<State> state_;
public:
    explicit Owner(Ops ops=posixOps()):state_(std::make_shared<State>(ops)){
        const auto state=state_;
        if(!state->slot.held())return;
        state->timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,reaperQueue());
        if(!state->timer)return;
        dispatch_source_set_timer(state->timer,DISPATCH_TIME_FOREVER,DISPATCH_TIME_FOREVER,0);
        dispatch_source_set_event_handler(state->timer,^{state->reap();});
        dispatch_resume(state->timer);
    }
    ~Owner(){
        const auto state=state_;
        if(!state->timer)return;
        std::lock_guard<std::mutex> guard(state->mutex);
        state->removeFiles(); // Remove credential paths immediately; repeat after a late child exit.
        if(state->pid<=0){state->retire();return;}
        const Probe probe=observe(state->ops,state->pid,state->result);
        if(state->result.retired){state->pid=0;state->retire();return;}
        if(probe==Probe::Running&&!state->result.killAttempted)signal(state->ops,state->pid,Signal::Kill,state->result);
        dispatch_source_set_timer(state->timer,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),250*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
    }
    bool admitted()const{return state_->slot.held();}
    bool ready()const{return state_->timer!=nullptr;}
    void paths(const char *request,const char *result){state_->requestPath=request;state_->resultPath=result;}
    void createdRequest(){state_->requestOwned=true;}
    void adopted(int pid){state_->pid=pid;state_->resultOwned=true;}
    Result wait(unsigned timeout=TimeoutMs,unsigned grace=GraceMs){
        state_->result=TLinkVPNHelperChild::wait(state_->ops,state_->pid,timeout,grace);
        if(state_->result.retired)state_->pid=0;
        return state_->result;
    }
    Owner(const Owner &)=delete;
    Owner &operator=(const Owner &)=delete;
};
}
#endif
#endif
