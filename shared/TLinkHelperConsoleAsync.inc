#include "TLinkHelperConsoleWriter.inc"
#include "TLinkConsoleLogRetention.h"
namespace TLinkHelperConsoleAsync {
static char QueueKey;
static dispatch_queue_t Queue(){
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.tlinkauto.helper.console",DISPATCH_QUEUE_SERIAL);if(queue)dispatch_queue_set_specific(queue,&QueueKey,&QueueKey,nullptr);});return queue;
}
static std::shared_ptr<TLinkConsoleLogBudget> GlobalBudget(){
    static auto budget=std::make_shared<TLinkConsoleLogBudget>();return budget;
}
class Owner:public std::enable_shared_from_this<Owner> {
    TLinkHelperConsoleState state_;
    std::shared_ptr<TLinkConsoleLogBudget> budget_,global_;
    NSString *path_,*latest_;
    TLinkHelperConsoleBatchSink *sink_;
    dispatch_queue_t queue_;
    std::atomic<bool> finished_{false};
    std::recursive_mutex consumerMutex_;
    static Owner *&Consumer(){static thread_local Owner *owner=nullptr;return owner;}
    struct ConsumerScope {
        Owner *previous;
        explicit ConsumerScope(Owner *owner):previous(Consumer()){Consumer()=owner;}
        ~ConsumerScope(){Consumer()=previous;}
    };
    struct Ticket {
        std::shared_ptr<Owner> owner;uint64_t token;
        Ticket(std::shared_ptr<Owner> value,uint64_t id):owner(std::move(value)),token(id){}
        ~Ticket(){owner->abandon(token);}
        void run() noexcept {owner->drain(token);}
    };
    static void schedule(dispatch_queue_t queue,std::shared_ptr<Ticket> ticket){dispatch_async(queue,^{ticket->run();});}
    void abandon(uint64_t token) noexcept {
        @autoreleasepool {@try {try {
            auto retired=state_.abandon(token);
            for(size_t n=0;n<retired.count;++n)budget_->dropped();
        }catch(...) {}} @catch(NSException *exception){(void)exception;}}
    }
    void consume(const TLinkHelperConsoleState::Batch &batch){
        TLinkHelperConsoleState::Batch files;
        for(size_t n=0;n<batch.count;++n){
            const auto &entry=batch.entries[n];
            @autoreleasepool {
                @try {try {NSLog(@"tlinkauto-jsd[%@][%@]: %@",entry->line.run,entry->line.level,entry->line.message);}
                    catch(...) {budget_->systemFailed();}} @catch(NSException *exception){(void)exception;budget_->systemFailed();}
            }
            if(entry->line.data)files.entries[files.count++]=entry;else budget_->failed();
        }
        if(!files.count)return;
        uint64_t run=TLinkConsoleLogBatchMask(0,files.count),latest=run;
        @try {try {run=[sink_ writeConsoleBatch:files toConsolePath:path_];}catch(...) {}} @catch(NSException *exception){(void)exception;}
        @try {try {latest=[sink_ writeConsoleBatch:files toConsolePath:latest_];}catch(...) {}} @catch(NSException *exception){(void)exception;}
        const uint64_t failed=run|latest;
        for(size_t n=0;n<files.count;++n)if(failed&(uint64_t(1)<<n))budget_->failed();
    }
    void drain(uint64_t token) noexcept {
        @try {try {
            std::lock_guard<std::recursive_mutex> lock(consumerMutex_);ConsumerScope consumer(this);
            for(;;){
                @autoreleasepool {
                    auto batch=state_.take(token);if(!batch.count)return;
                    @try {try {consume(batch);}catch(...) {for(size_t n=0;n<batch.count;++n)budget_->failed();}}
                    @catch(NSException *exception){(void)exception;for(size_t n=0;n<batch.count;++n)budget_->failed();}
                }
            }
        }catch(...) {abandon(token);}} @catch(NSException *exception){(void)exception;abandon(token);}
    }
    bool forceClose() noexcept {
        @try {try {
            std::lock_guard<std::recursive_mutex> lock(consumerMutex_);
            const auto value=state_.snapshot();if(value.scheduled)drain(value.token);
            if(!state_.snapshot().scheduled)finished_=true;
        }catch(...) {}} @catch(NSException *exception){(void)exception;}
        return finished_.load();
    }
public:
    Owner(NSString *path,NSString *latest,dispatch_queue_t queue)
        :budget_(std::make_shared<TLinkConsoleLogBudget>()),global_(GlobalBudget()),path_([path copy]),latest_([latest copy]),sink_([TLinkHelperConsoleBatchSink new]),queue_(queue){}
    bool valid()const{return queue_&&sink_&&path_&&latest_;}
    void submit(NSString *run,NSString *level,NSString *message) noexcept {
        @autoreleasepool {
        @try {try {
            if(!state_.snapshot().accepting){budget_->dropped();return;}
            auto runPermit=TLinkConsoleLogPermit::acquire(budget_);if(!runPermit)return;
            auto globalPermit=TLinkConsoleLogPermit::acquire(global_);if(!globalPermit){budget_->dropped();return;}
            auto line=TLinkHelperConsolePrepare(run,level,message);if(!line.ready){budget_->dropped();return;}
            auto entry=std::make_shared<TLinkHelperConsoleEntry>(std::move(globalPermit),std::move(runPermit),std::move(line));
            // Ticket dies after registration unlocks, including enqueue unwind.
            std::shared_ptr<Ticket> ticket;
            auto registration=state_.insert(entry);if(!registration){budget_->dropped();return;}
            if(registration.schedule()){
                ticket=std::make_shared<Ticket>(shared_from_this(),registration.token());
                schedule(queue_,ticket);
                if(ticket.use_count()==1){budget_->dropped();return;}
            }
            registration.commit();budget_->accepted(entry->line.truncated);
        }catch(...) {budget_->dropped();}} @catch(NSException *exception){(void)exception;budget_->dropped();}
        }
    }
    bool close() noexcept {
        if(finished_.load())return true;
        @autoreleasepool {
        @try {try {
            state_.close();
            // Reentry from a sink only closes admission; the external scope
            // still waits for this consumer to finish before summary/retention.
            if(Consumer())return false;
            if(dispatch_get_specific(&QueueKey))return forceClose();
            auto self=shared_from_this();
            dispatch_sync(queue_,^{self->forceClose();});
        }catch(...) {}} @catch(NSException *exception){(void)exception;}
        }
        // If barrier submission itself fails, serialize with any running drain
        // and settle pending work here. A later queued ticket is then stale.
        if(!finished_.load())return forceClose();
        return true;
    }
    TLinkConsoleLogStats stats(){return budget_->snapshot();}
};
static std::shared_ptr<Owner> Create(NSString *path,NSString *latest) noexcept {
    @try {try {auto queue=Queue();if(!queue)return {};
        auto owner=std::make_shared<Owner>(path,latest,queue);return owner->valid()?owner:std::shared_ptr<Owner>();
    }catch(...) {}} @catch(NSException *exception){(void)exception;}return {};
}
class CloseScope {
    std::shared_ptr<Owner> owner_;
    TLinkConsoleLogRetention::Completion *retention_;
public:
    explicit CloseScope(std::shared_ptr<Owner> owner,TLinkConsoleLogRetention::Completion *retention=nullptr):owner_(std::move(owner)),retention_(retention){}
    CloseScope(const CloseScope &)=delete;CloseScope &operator=(const CloseScope &)=delete;
    ~CloseScope(){if(owner_&&!owner_->close()&&retention_)retention_->cancel();}
};
static NSDictionary *Diagnostics(const std::shared_ptr<Owner> &owner){
    if(!owner)return @{@"mode":@"sync_bounded_fallback_v1"};
    const auto value=owner->stats();
    return @{@"mode":@"async_bounded_batch_v1",@"accepted":@(value.accepted),@"dropped":@(value.dropped),@"truncated":@(value.truncated),
        @"writeFailures":@(value.writeFailures),@"systemFailures":@(value.systemFailures),@"pending":@(value.pending),@"peakPending":@(value.peakPending)};
}
}
