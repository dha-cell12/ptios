#ifndef TLINK_BACKGROUND_TASK_RUN_H
#define TLINK_BACKGROUND_TASK_RUN_H
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <memory>
#include <mutex>

// Admission is linearized against completion. Already admitted external work is not preempted.
class TLinkBackgroundTaskRun {
    enum class Phase { Ready, Refreshing, Ensuring, Finished };
    mutable std::mutex mutex_;
    Phase phase_=Phase::Ready;
    dispatch_source_t timer_=nullptr;
    void (^completion_)(BOOL, NSString *, NSDictionary *);
    static void cancelTimer(dispatch_source_t timer) {
        if (!timer) return;
        dispatch_source_set_event_handler(timer, ^{});
        dispatch_source_cancel(timer);
    }
public:
    explicit TLinkBackgroundTaskRun(void (^completion)(BOOL, NSString *, NSDictionary *))
        : completion_([completion copy]) {}
    TLinkBackgroundTaskRun(const TLinkBackgroundTaskRun &)=delete;
    TLinkBackgroundTaskRun &operator=(const TLinkBackgroundTaskRun &)=delete;
    bool finished() const {
        std::lock_guard<std::mutex> guard(mutex_);
        return phase_==Phase::Finished;
    }
    bool beginRefresh() {
        std::lock_guard<std::mutex> guard(mutex_);
        if (phase_!=Phase::Ready) return false;
        phase_=Phase::Refreshing;
        return true;
    }
    bool beginEnsure() {
        std::lock_guard<std::mutex> guard(mutex_);
        if (phase_!=Phase::Refreshing) return false;
        phase_=Phase::Ensuring;
        return true;
    }
    // The caller resumes an initially unarmed source before transferring ownership.
    void installTimer(dispatch_source_t timer) {
        bool retired;
        {
            std::lock_guard<std::mutex> guard(mutex_);
            if (phase_!=Phase::Finished && timer_==timer) return;
            retired=phase_==Phase::Finished || timer_!=nullptr;
            if (!retired) timer_=timer;
        }
        if (retired) cancelTimer(timer);
    }
    void arm(int64_t nanoseconds) {
        std::lock_guard<std::mutex> guard(mutex_);
        if (phase_!=Phase::Finished && timer_)
            dispatch_source_set_timer(timer_,dispatch_time(DISPATCH_TIME_NOW,nanoseconds),DISPATCH_TIME_FOREVER,0);
    }
    void finish(BOOL success, NSString *detail, NSDictionary *license) {
        dispatch_source_t timer=nullptr;
        void (^completion)(BOOL, NSString *, NSDictionary *)=nil;
        {
            std::lock_guard<std::mutex> guard(mutex_);
            if (phase_==Phase::Finished) return;
            phase_=Phase::Finished;
            timer=timer_; timer_=nullptr;
            completion=completion_; completion_=nil;
        }
        // Break source/callback/task ownership before delivery, outside the mutex for reentry.
        cancelTimer(timer);
        if (completion) completion(success,detail,license);
    }
};
#endif
