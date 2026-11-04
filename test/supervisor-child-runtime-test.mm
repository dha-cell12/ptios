#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include "../shared/TLinkSupervisorWatch.h"
#include <sys/wait.h>
#include <spawn.h>
#include <unistd.h>
#include <cerrno>
#include <cassert>
#include <cstdio>
#include <cstdint>
#include <cstring>
extern char **environ;
#include "ChildThrottle.inc"
static uint64_t fixtureNow(){return 100;}
@interface ChildHarness:NSObject {
@protected
    dispatch_queue_t _queue;
    pid_t _pid;
    BOOL _running;
    BOOL _autoRespawn;
    BOOL _requiresReplacement;
    uint64_t _lastSpawnContinuous;
}
@property(nonatomic,strong) NSMutableArray *backgroundJobs;
@property(nonatomic,strong) NSMutableArray *ownerJobs;
@property(nonatomic,strong) NSMutableArray *logs;
@property(nonatomic,strong) NSMutableArray *events;
@property(nonatomic,strong) NSMutableArray *arguments;
@property(nonatomic,strong) dispatch_group_t work;
@property BOOL realScheduler;
@property BOOL helperBusy;
@property BOOL pending;
@property int nextSpawnError;
@property unsigned waitCalls;
@property unsigned interrupts;
@property unsigned schedules;
@property unsigned cancellations;
@property(nonatomic,readonly) dispatch_queue_t ownerQueue;
@property(nonatomic,readonly) pid_t childPid;
@property(nonatomic,readonly) BOOL running;
- (void)spawnLocked;
- (NSString *)streamdPath;
- (BOOL)helperBusyLocked:(NSString *)operation;
- (BOOL)preparePortForSpawnLocked;
- (void)emitLog:(NSString *)message;
- (void)emitRunning:(BOOL)running pid:(pid_t)pid;
- (void)cancelPendingRespawnLocked;
- (void)scheduleRespawnLockedWithDelay:(NSTimeInterval)delay;
- (void)enableAuto:(BOOL)enabled;
- (void)handleChildExit:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid;
- (void)runBackground;
- (void)runOwner;
- (void)drain;
- (NSDictionary *)snapshot;
@end
static void fixtureAsync(ChildHarness *owner,dispatch_queue_t queue,dispatch_block_t block){
    if(owner.realScheduler){
        dispatch_group_enter(owner.work);
        dispatch_async(queue,^{@autoreleasepool{block();dispatch_group_leave(owner.work);}});return;
    }
    [(queue==owner.ownerQueue?owner.ownerJobs:owner.backgroundJobs) addObject:[block copy]];
}
static int fixtureSpawn(ChildHarness *owner,pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,const posix_spawnattr_t *attr,char *const argv[],char *const envp[]){
    assert(std::strcmp(path,"/bin/sh")==0&&actions==nullptr&&attr==nullptr&&envp==environ);
    assert(argv[0]&&argv[1]&&std::strcmp(argv[1],"--daemon")==0&&!argv[2]);
    [owner.arguments addObject:@[[NSString stringWithUTF8String:argv[0]],[NSString stringWithUTF8String:argv[1]]]];
    if(owner.nextSpawnError){const int error=owner.nextSpawnError;owner.nextSpawnError=0;return error;}
    if(!owner.realScheduler){*pid=42;return 0;}
    char shell[]="/bin/sh",flag[]="-c",command[]="exit 7";char *args[]={shell,flag,command,nullptr};
    return ::posix_spawn(pid,shell,nullptr,nullptr,args,environ);
}
static pid_t fixtureWait(ChildHarness *owner,pid_t pid,int *status,int flags){
    assert(pid>0&&flags==0);owner.waitCalls++;
    if(owner.interrupts){owner.interrupts--;errno=EINTR;return -1;}
    if(owner.realScheduler)return ::waitpid(pid,status,flags);
    *status=7<<8;return pid;
}
static void runJob(NSMutableArray *jobs){assert(jobs.count);dispatch_block_t block=(dispatch_block_t)jobs[0];[jobs removeObjectAtIndex:0];block();}
@implementation ChildHarness
- (instancetype)init{self=[super init];if(self){_queue=dispatch_queue_create("fixture.direct.child",DISPATCH_QUEUE_SERIAL);_pid=-1;_autoRespawn=YES;_backgroundJobs=[NSMutableArray array];_ownerJobs=[NSMutableArray array];_logs=[NSMutableArray array];_events=[NSMutableArray array];_arguments=[NSMutableArray array];_work=dispatch_group_create();}return self;}
- (dispatch_queue_t)ownerQueue{return _queue;}
- (pid_t)childPid{return _pid;}
- (BOOL)running{return _running;}
- (NSString *)streamdPath{return @"/bin/sh";}
- (BOOL)helperBusyLocked:(NSString *)operation{assert([operation isEqualToString:@"spawn"]);return _helperBusy;}
- (BOOL)preparePortForSpawnLocked{return YES;}
- (void)spawnLocked{assert(false);}
- (void)emitLog:(NSString *)message{[_logs addObject:message];}
- (void)emitRunning:(BOOL)running pid:(pid_t)pid{[_events addObject:@{@"running":@(running),@"pid":@(pid)}];}
- (void)enableAuto:(BOOL)enabled{_autoRespawn=enabled;}
- (void)cancelPendingRespawnLocked{if(_pending)++_cancellations;_pending=NO;}
- (void)scheduleRespawnLockedWithDelay:(NSTimeInterval)delay{assert(delay>=0&&delay<=3);++_schedules;_pending=YES;}
- (void)runBackground{runJob(_backgroundJobs);}
- (void)runOwner{runJob(_ownerJobs);}
- (void)drain{while(_backgroundJobs.count)[self runBackground];while(_ownerJobs.count)[self runOwner];}
- (NSDictionary *)snapshot{return @{@"running":@(_running),@"pid":@(_pid),@"pending":@(_pending),@"schedules":@(_schedules),@"cancellations":@(_cancellations),@"logs":[_logs copy],@"events":[_events copy],@"argv":[_arguments copy]};}
#include "ChildExitPolicy.inc"
@end
@interface CurrentChild:ChildHarness {
    NSObject *_directChildIdentity;
}
- (NSObject *)token;
- (void)invalidateDirectChild;
- (void)retireDirectChildLocked:(NSObject *)identity waitResult:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid;
@end
@implementation CurrentChild
#include "ChildUnderTest.inc"
- (NSObject *)token{return _directChildIdentity;}
- (void)invalidateDirectChild{_directChildIdentity=nil;}
@end
@interface LegacyChild:ChildHarness
@end
@implementation LegacyChild
#include "ChildLegacy.inc"
@end
static void parityCases(){
    for(unsigned failure=0;failure<2;++failure){@autoreleasepool{
        CurrentChild *current=[CurrentChild new];LegacyChild *old=[LegacyChild new];
        if(failure){current.nextSpawnError=EACCES;old.nextSpawnError=EACCES;}
        [current spawnLocked];[old spawnLocked];[current drain];[old drain];
        assert([[current snapshot] isEqual:[old snapshot]]&&![current token]);
    }}
    CurrentChild *owner=[CurrentChild new];[owner spawnLocked];NSObject *token=[owner token];
    owner.nextSpawnError=EACCES;[owner spawnLocked];assert([owner token]==token&&owner.childPid==42);
    [owner drain];assert(![owner token]&&!owner.running&&owner.schedules==1);
}
static void identityCases(){
    @autoreleasepool{
        CurrentChild *owner=[CurrentChild new];[owner spawnLocked];NSObject *first=[owner token];[owner runBackground];
        [owner spawnLocked];NSObject *second=[owner token];assert(first!=second&&owner.childPid==42);
        owner.pending=YES;NSDictionary *before=[owner snapshot];[owner runOwner];
        assert([[owner snapshot] isEqual:before]&&[owner token]==second);
        [owner runBackground];dispatch_block_t secondDelivery=(dispatch_block_t)owner.ownerJobs[0];[owner runOwner];
        assert(![owner token]&&!owner.running&&owner.schedules==1);
        [owner spawnLocked];NSObject *third=[owner token];before=[owner snapshot];secondDelivery();
        assert([owner token]==third&&[[owner snapshot] isEqual:before]);[owner drain];assert(![owner token]);
        LegacyChild *old=[LegacyChild new];[old spawnLocked];[old runBackground];[old spawnLocked];[old runOwner];
        assert(!old.running&&old.schedules==1);[old drain];
    }
    __weak NSObject *weakToken;
    @autoreleasepool{
        CurrentChild *owner=[CurrentChild new];[owner spawnLocked];weakToken=[owner token];
        [owner invalidateDirectChild];NSDictionary *before=[owner snapshot];[owner drain];
        assert([[owner snapshot] isEqual:before]&&![owner token]);
    }
    assert(!weakToken);
    @autoreleasepool{
        CurrentChild *owner=[CurrentChild new];[owner spawnLocked];NSObject *token=[owner token];
        owner.helperBusy=YES;[owner spawnLocked];assert([owner token]==token&&owner.backgroundJobs.count==1);
        [owner retireDirectChildLocked:nil waitResult:42 status:0 expectedPid:42];assert([owner token]==token);
        owner.helperBusy=NO;[owner drain];assert(![owner token]);
    }
}
static void realCases(){
    for(unsigned n=0;n<32;++n){@autoreleasepool{
        CurrentChild *owner=[CurrentChild new];owner.realScheduler=YES;owner.interrupts=3;
        __block pid_t child=-1;
        dispatch_sync(owner.ownerQueue,^{[owner enableAuto:NO];[owner spawnLocked];child=owner.childPid;assert(child>0&&[owner token]);});
        assert(dispatch_group_wait(owner.work,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
        dispatch_sync(owner.ownerQueue,^{assert(![owner token]&&!owner.running&&owner.waitCalls>=4&&owner.schedules==0);});
        int status=0;assert(::waitpid(child,&status,WNOHANG)==-1&&errno==ECHILD);
    }}
}
int main(){@autoreleasepool{
    parityCases();identityCases();realCases();
    puts("Supervisor child passed: actual/frozen spawn/wait/exit policy, success-only token adoption, failed-spawn ownership, same-PID replacement/stale/duplicate/nil refusal, invalidation/lifetime, busy retention and 32 real GCD/disposable-child reaps after EINTR. No real service spawned; process identity/device qualification pending.");
}return 0;}
