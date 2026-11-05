static NSDictionary *admissionCall(unsigned method){
    if(method==0)return TLinkAXCopySnapshot(123,@"fixture.bundle",@{});
    if(method==1)return TLinkAXFindElement(123,@"fixture.bundle",@{@"identifier":@"identifier"});
    return TLinkAXElementAtPoint(123,@"fixture.bundle",CGPointMake(30,30));
}
static void admissionBusy(NSDictionary *value){
    hitErrorCode(value,@"ui_ax_busy");
    assert([value[@"partial"] boolValue]&&[value[@"retryable"] boolValue]&&!TLinkAXResultCompleteForAction(value));
}
static void admissionManualCases(){
    @autoreleasepool{
        reset();std::vector<std::unique_ptr<TLinkAXAdmission::Lease>> held;
        for(unsigned n=0;n<8;++n)held.emplace_back(new TLinkAXAdmission::Lease(TLinkAXAdmissionState()));
        assert(TLinkAXAdmissionState().pending()==8);
        for(unsigned method=0;method<3;++method){admissionBusy(admissionCall(method));assert(TLinkAXAdmissionState().pending()==8);}
        assert(hitDispatches==0&&hitCreates==0&&rootQueries==0&&hitCalls==0&&keys.empty());
        cancelled=true;
        for(unsigned method=0;method<3;++method)hitErrorCode(admissionCall(method),@"ui_cancelled_or_timed_out");
        hitErrorCode(TLinkAXFindElement(123,@"fixture.bundle",@{}),@"ui_selector_requires_text_identifier_or_role");
        hitErrorCode(TLinkAXElementAtPoint(0,@"fixture.bundle",CGPointMake(30,30)),@"ui_hit_test_invalid_request");
        assert(TLinkAXAdmissionState().pending()==8&&hitDispatches==0);
        cancelled=false;held[2]->release();
        for(unsigned method=0;method<3;++method){
            assert([admissionCall(method)[@"ok"] boolValue]);assert(TLinkAXAdmissionState().pending()==7);
        }
        held.clear();assert(TLinkAXAdmissionState().pending()==0);hitOwnersRetired();
    }
    assert(boxes==0&&!lastBox);
}
static void admissionUnwindCases(){
    for(unsigned method=0;method<3;++method){
        for(unsigned kind:{1U,2U}){
            @autoreleasepool{
                reset();hitFaultPhase=1;hitFaultKind=kind;bool caught=false;
                @try{try{admissionCall(method);}catch(const std::runtime_error &){caught=kind==2;}}
                @catch(NSException *exception){caught=kind==1&&[exception.name isEqualToString:@"AXHitFixture"];}
                assert(caught&&TLinkAXAdmissionState().pending()==0);hitOwnersRetired();
            }
            @autoreleasepool{
                reset();hitFaultPhase=5;hitFaultKind=kind;
                // Snapshot/find exercise preparation refusal; hit exercises
                // its NS mapping/C++ unwind after acquiring the hit owner.
                if(method!=2)hitPrepared=false;
                bool caught=false;NSDictionary *value=nil;
                try{value=admissionCall(method);}catch(const std::runtime_error &){caught=true;}
                assert(caught==(method==2&&kind==2));
                if(value)assert(![value[@"ok"] boolValue]);
                assert(TLinkAXAdmissionState().pending()==0);hitOwnersRetired();
            }
            assert(boxes==0&&!lastBox);
        }
    }
}
static void admissionRealQueueCases(){
    for(unsigned cycle=0;cycle<16;++cycle){
        @autoreleasepool{
            reset();admissionDispatches=0;
            admissionQueue=dispatch_queue_create("fixture.ax.admission",DISPATCH_QUEUE_SERIAL);
            admissionEnqueued=dispatch_semaphore_create(0);admissionRootEntered=dispatch_semaphore_create(0);admissionRootRelease=dispatch_semaphore_create(0);
            admissionHoldRoot=true;std::atomic<unsigned> successes{0};std::vector<std::thread> threads;
            for(unsigned n=0;n<8;++n)threads.emplace_back([n,&successes]{@autoreleasepool{
                NSDictionary *value=admissionCall(n%3);assert([value[@"ok"] boolValue]);++successes;
            }});
            assert(dispatch_semaphore_wait(admissionRootEntered,dispatch_time(DISPATCH_TIME_NOW,10LL*NSEC_PER_SEC))==0);
            for(unsigned n=0;n<8;++n)assert(dispatch_semaphore_wait(admissionEnqueued,dispatch_time(DISPATCH_TIME_NOW,10LL*NSEC_PER_SEC))==0);
            assert(TLinkAXAdmissionState().pending()==8&&admissionDispatches==8&&rootRetains==1&&rootDrops==0);
            for(unsigned method=0;method<3;++method){admissionBusy(admissionCall(method));assert(TLinkAXAdmissionState().pending()==8&&admissionDispatches==8);}
            dispatch_semaphore_signal(admissionRootRelease);
            for(auto &thread:threads)thread.join();
            assert(successes==8&&TLinkAXAdmissionState().pending()==0&&admissionDispatches==8);hitOwnersRetired();
            assert(boxes==0&&!lastBox&&!queryArray);
            admissionQueue=nil;admissionEnqueued=nil;admissionRootEntered=nil;admissionRootRelease=nil;
        }
    }
}
static void admissionCases(){
    std::puts("AX admission Foundation: actual snapshot/find/hit entries, shared production leases and real held serial GCD queue; AX/providers controlled");
    admissionManualCases();admissionUnwindCases();admissionRealQueueCases();
    reset();parent.reset();node=nil;rootObject=nil;
    std::puts("AX admission passed: mixed shared saturation, immediate ninth refusal/no enqueue, validation/cancel precedence, retained-owner isolation/recovery, controlled NS/C++ unwind and 16 real-queue/eight-caller cycles with balanced CF/leases. Queue preemption/device qualification pending.");
}
