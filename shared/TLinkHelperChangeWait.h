#ifndef TLINK_HELPER_CHANGE_WAIT_H
#define TLINK_HELPER_CHANGE_WAIT_H
#include "TLinkHelperRequestDeadline.h"
#include <condition_variable>
#include <mutex>
// Level-triggered wake hints for one helper instance, not an event/replay journal.
class TLinkHelperChangeWait {
    std::mutex mutex_;std::condition_variable changed_;
    uint64_t sequence_=1;size_t waiters_=0;bool open_=true;
public:
    enum : size_t {Limit=4};
    enum : int {MaxWaitMs=750,OutputReserveMs=25};
    enum class Code {Changed,Timeout,Busy,Stopped,InvalidCursor,Cancelled};
    struct Result {Code code;uint64_t sequence;};
    // The same notifier owns every access; cancellation cannot race registration.
    class Cancellation {
        friend class TLinkHelperChangeWait;
        bool cancelled_=false;
    public:
        Cancellation()=default;
        Cancellation(const Cancellation &)=delete;
        Cancellation &operator=(const Cancellation &)=delete;
    };
    uint64_t sequence(){std::lock_guard<std::mutex> lock(mutex_);return sequence_;}
    size_t waiters(){std::lock_guard<std::mutex> lock(mutex_);return waiters_;}
    void publish(){
        {std::lock_guard<std::mutex> lock(mutex_);
         if(!open_)return;
         if(sequence_==TLinkHelperIO::MaxWireTime)open_=false;else ++sequence_;}
        changed_.notify_all();
    }
    void stop(){{std::lock_guard<std::mutex> lock(mutex_);open_=false;}changed_.notify_all();}
    void cancel(Cancellation &cancellation){
        {std::lock_guard<std::mutex> lock(mutex_);cancellation.cancelled_=true;}
        changed_.notify_all(); // Other waiters recheck their own predicate without advancing sequence.
    }
    Result wait(uint64_t after,const TLinkHelperIO::Deadline &deadline,Cancellation *cancellation=nullptr,
                uint64_t (*clock)()=TLinkHelperIO::nowMs){
        std::unique_lock<std::mutex> lock(mutex_);
        if(after>sequence_)return {Code::InvalidCursor,sequence_};
        if(!open_)return {Code::Stopped,sequence_};
        if(cancellation&&cancellation->cancelled_)return {Code::Cancelled,sequence_};
        if(after!=sequence_)return {Code::Changed,sequence_};
        if(!deadline.remaining(clock()))return {Code::Timeout,sequence_};
        if(waiters_>=Limit)return {Code::Busy,sequence_};
        ++waiters_;
        struct Count {size_t &value;~Count(){--value;}} count{waiters_};
        while(open_&&after==sequence_&&!(cancellation&&cancellation->cancelled_)){
            const int remaining=deadline.remaining(clock());if(!remaining)break;
            changed_.wait_for(lock,std::chrono::milliseconds(remaining));
        }
        if(!open_)return {Code::Stopped,sequence_};
        if(cancellation&&cancellation->cancelled_)return {Code::Cancelled,sequence_};
        return {after==sequence_?Code::Timeout:Code::Changed,sequence_};
    }
};
#ifdef __OBJC__
static inline bool TLinkHelperReadChangeWait(NSDictionary *request,uint64_t &after,uint64_t &waitMs){
    id payload=request[@"payload"];
    id peerEOF=request[@"waitPeerEOFContract"];
    if(peerEOF&&(![peerEOF isKindOfClass:[NSString class]]||![peerEOF isEqual:@"cancel_v1"]))return false;
    return [payload isKindOfClass:[NSDictionary class]]&&[payload count]==2&&
        TLinkHelperWireTime(payload[@"afterSequence"],after)&&TLinkHelperWireTime(payload[@"waitMs"],waitMs)&&
        waitMs>0&&waitMs<=TLinkHelperChangeWait::MaxWaitMs;
}
#endif
#endif
