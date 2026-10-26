#ifndef TLINK_HELPER_WAIT_PEER_H
#define TLINK_HELPER_WAIT_PEER_H
#include "TLinkHelperChangeWait.h"
#if defined(__APPLE__) && defined(__OBJC__)
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <cerrno>

// One borrowed, prepared socket. The caller must keep it open until stop/destruction
// has joined source cancellation. Event/cancel handlers never use the command queue.
// Only opt-in, one-request wait connections promise EOF means cancellation rather
// than legacy half-close framing. Additional post-request input is also invalid.
class TLinkHelperWaitPeer {
    void *changes_,*cancellation_;
    void (*cancel_)(void *,void *);
    dispatch_source_t source_=nullptr;
    dispatch_semaphore_t completed_=nullptr;
    int descriptor_=-1;
public:
    template<class Changes>
    TLinkHelperWaitPeer(Changes &changes,typename Changes::Cancellation &cancellation)
        :changes_(&changes),cancellation_(&cancellation),cancel_([](void *owner,void *token){
            static_cast<Changes *>(owner)->cancel(*static_cast<typename Changes::Cancellation *>(token));
        }){}
    TLinkHelperWaitPeer(const TLinkHelperWaitPeer &)=delete;
    TLinkHelperWaitPeer &operator=(const TLinkHelperWaitPeer &)=delete;
    bool start(int descriptor){
        if(descriptor<0||source_)return false;
        completed_=dispatch_semaphore_create(0);
        if(!completed_)return false;
        // A separate queue never sits behind the waiting client queue/barrier.
        static dispatch_queue_t queue;
        static dispatch_once_t once;
        dispatch_once(&once, ^{queue=dispatch_queue_create("com.tlinkauto.helper.wait-peer",DISPATCH_QUEUE_SERIAL);});
        source_=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,static_cast<uintptr_t>(descriptor),0,queue);
        if(!source_){completed_=nullptr;return false;}
        descriptor_=descriptor;
        TLinkHelperWaitPeer *owner=this;
        dispatch_source_set_event_handler(source_, ^{
            uint8_t byte=0;
            const ssize_t count=::recv(owner->descriptor_,&byte,1,MSG_PEEK|MSG_DONTWAIT);
            if(count<0&&(errno==EAGAIN||errno==EWOULDBLOCK||errno==EINTR))return;
            owner->cancel_(owner->changes_,owner->cancellation_);
            dispatch_source_cancel(owner->source_); // One event, no EOF/data busy loop.
        });
        dispatch_semaphore_t completed=completed_;
        dispatch_source_set_cancel_handler(source_, ^{dispatch_semaphore_signal(completed);});
        dispatch_resume(source_);
        return true;
    }
    void stop(){
        if(!source_)return;
        dispatch_source_cancel(source_);
        // Apple requires the cancellation handler to run before closing/reusing a
        // tracked descriptor. Its signal also joins all uses of the borrowed token.
        dispatch_semaphore_wait(completed_,DISPATCH_TIME_FOREVER);
        source_=nullptr;completed_=nullptr;descriptor_=-1;
    }
    ~TLinkHelperWaitPeer(){stop();}
};
#endif
#endif
