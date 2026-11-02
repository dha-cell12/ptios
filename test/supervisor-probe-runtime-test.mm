#import <Foundation/Foundation.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <sys/types.h>
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif
#include "SupervisorProbeConstants.inc"
static unsigned parses=0,procReads=0,procMode=0;
static NSString *const expectedPath=@"/Applications/Fixture.app/streamd";
static int fixtureProcPath(int pid,void *buffer,uint32_t size){
    assert(pid>0);++procReads;
    if(!procMode)return 0;
    if(procMode==3){assert(size>=2);static_cast<char *>(buffer)[0]=char(0xff);return 1;}
    const char *path=procMode==1?expectedPath.UTF8String:"/Applications/Old.app/streamd";
    const size_t count=std::strlen(path);assert(count+1<=size);std::memcpy(buffer,path,count+1);return int(count);
}
@interface FixtureJSON:NSObject
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
@end
@implementation FixtureJSON
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {
    ++parses;return [NSJSONSerialization JSONObjectWithData:data options:options error:error];
}
@end
@protocol ProbeAPI <NSObject>
- (BOOL)probeTaskServerAndUpdateLocked:(NSString *)reason;
- (pid_t)streamdPidFromHelloStatusLocked;
- (NSString *)streamdLaunchPathFromHelloStatusLocked;
- (NSDictionary *)snapshot;
@end
@interface ProbeHarness:NSObject
@property(nonatomic,copy) NSString *status;
@property(nonatomic,copy) NSArray *helloWires;
@property NSUInteger helloReads;
@property NSUInteger statusReads;
@property(nonatomic,strong) NSMutableArray *logs;
@property(nonatomic,strong) NSMutableArray *events;
- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)seconds;
- (NSString *)streamdPath;
- (void)emitLog:(NSString *)message;
- (void)emitRunning:(BOOL)running pid:(pid_t)pid;
@end
@implementation ProbeHarness
- (instancetype)init {
    self=[super init];if(self){_logs=[NSMutableArray array];_events=[NSMutableArray array];}return self;
}
- (NSString *)sendLocalTaskLineLocked:(NSString *)line timeout:(int)seconds {
    assert(seconds==2);
    if([line isEqualToString:@"97\n"]){++_statusReads;return _status;}
    assert([line isEqualToString:@"60\n"]&&_helloWires.count>0);
    const NSUInteger index=MIN(_helloReads,_helloWires.count-1);++_helloReads;
    id wire=_helloWires[index];return wire==[NSNull null]?nil:wire;
}
- (NSString *)streamdPath{return expectedPath;}
- (void)emitLog:(NSString *)message{[_logs addObject:message];}
- (void)emitRunning:(BOOL)running pid:(pid_t)pid{[_events addObject:@{@"running":@(running),@"pid":@(pid)}];}
@end
#define PROBE_IVARS {BOOL _running;pid_t _pid;BOOL _requiresReplacement;}
#define PROBE_SNAPSHOT \
- (instancetype)init{self=[super init];if(self){_pid=-1;}return self;} \
- (NSDictionary *)snapshot{return @{@"running":@(_running),@"pid":@(_pid),@"replacement":@(_requiresReplacement),@"logs":[self.logs copy],@"events":[self.events copy]};}
@interface CurrentProbe:ProbeHarness <ProbeAPI> PROBE_IVARS
@end
@implementation CurrentProbe
#include "SupervisorProbeUnderTest.inc"
PROBE_SNAPSHOT
@end
@interface LegacyProbe:ProbeHarness <ProbeAPI> PROBE_IVARS
@end
@implementation LegacyProbe
#include "SupervisorProbeLegacy.inc"
PROBE_SNAPSHOT
@end
#undef PROBE_SNAPSHOT
#undef PROBE_IVARS
static NSString *wire(id object){
    NSData *data=[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingFragmentsAllowed error:nil];assert(data);
    return [@"0;;" stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}
static ProbeHarness<ProbeAPI> *owner(bool legacy,NSString *status,NSArray *hellos){
    ProbeHarness<ProbeAPI> *value;
    if(legacy)value=[LegacyProbe new];else value=[CurrentProbe new];
    value.status=status;value.helloWires=hellos;return value;
}
static NSDictionary *run(ProbeHarness<ProbeAPI> *value){
    @try{BOOL running=[value probeTaskServerAndUpdateLocked:@"fixture"];return @{@"return":@(running),@"snapshot":[value snapshot]};}
    @catch(NSException *exception){return @{@"exception":exception.name};}
}
static NSString *currentStatus(){return [NSString stringWithFormat:@"0;;%@ %@\r\n",kSCRequiredStreamdServiceMarker,kSCRequiredVPNServiceMarker];}
static void parityCases(){
    NSArray *pids=@[@42,@0,@(-1),@2147483647,@4294967295ULL,@1.9,@"42",@"invalid",[NSNull null],@[]];
    NSArray *paths=@[expectedPath,@"/Applications/Old.app/streamd",@"",@"/Applications/Fixture.app/../Fixture.app/streamd",@42,[NSNull null]];
    for(id pid in pids){
        for(id path in paths){
            for(unsigned mode=0;mode<4;++mode){@autoreleasepool{
                procMode=mode;NSString *hello=wire(@{@"pid":pid,@"launch_executable_path":path});
                ProbeHarness<ProbeAPI> *old=owner(true,currentStatus(),@[hello]);
                parses=procReads=0;NSDictionary *expected=run(old);const unsigned oldParses=parses,oldProc=procReads;
                ProbeHarness<ProbeAPI> *actual=owner(false,currentStatus(),@[hello]);
                parses=procReads=0;NSDictionary *result=run(actual);
                assert([result isEqual:expected]&&actual.statusReads==1&&actual.helloReads==1&&procReads==oldProc);
                assert(parses==1&&oldParses==old.helloReads);
                assert(old.helloReads==1||(!mode&&old.helloReads==2));
            }}
        }
    }
    for(NSString *status in @[@"",@"old-service",@"serviceVersion=23 only",@"vpnPhase=5 only"]){
        for(NSString *hello in @[@"",@"-1;;denied",@"0;;!!!",@"0;;eA==",wire(@[]),wire(@{}),wire(@42)]){@autoreleasepool{
            procMode=0;ProbeHarness<ProbeAPI> *old=owner(true,status,@[hello]);NSDictionary *expected=run(old);
            ProbeHarness<ProbeAPI> *actual=owner(false,status,@[hello]);assert([run(actual) isEqual:expected]);
            assert(actual.helloReads==(status.length?1:0));
        }}
    }
    // Keep the independent selector contracts; they intentionally read fresh hello.
    NSString *hello=wire(@{@"pid":@42,@"launch_executable_path":expectedPath});
    ProbeHarness<ProbeAPI> *old=owner(true,currentStatus(),@[hello]);
    ProbeHarness<ProbeAPI> *actual=owner(false,currentStatus(),@[hello]);
    assert([old streamdPidFromHelloStatusLocked]==[actual streamdPidFromHelloStatusLocked]);
    assert([[old streamdLaunchPathFromHelloStatusLocked] isEqual:[actual streamdLaunchPathFromHelloStatusLocked]]);
    assert(actual.helloReads==2&&old.helloReads==2);
}
static void coherenceCases(){
    procMode=0;
    NSString *first=wire(@{@"pid":@41,@"launch_executable_path":expectedPath});
    NSString *second=wire(@{@"pid":@42,@"launch_executable_path":@"/Applications/Old.app/streamd"});
    ProbeHarness<ProbeAPI> *actual=owner(false,currentStatus(),@[first,second]);
    parses=0;assert([actual probeTaskServerAndUpdateLocked:nil]);
    NSDictionary *state=[actual snapshot];assert([state[@"pid"] intValue]==41&&actual.helloReads==1&&parses==1);
    assert(![actual probeTaskServerAndUpdateLocked:nil]);
    state=[actual snapshot];assert([state[@"pid"] intValue]==42&&[state[@"replacement"] boolValue]&&actual.helloReads==2&&parses==2);
    // The frozen reader mixes first PID with second path during this race.
    ProbeHarness<ProbeAPI> *old=owner(true,currentStatus(),@[first,second]);assert(![old probeTaskServerAndUpdateLocked:nil]&&old.helloReads==2);
    for(unsigned n=0;n<1000;++n){@autoreleasepool{
        ProbeHarness<ProbeAPI> *value=owner(false,currentStatus(),@[first]);
        parses=0;assert([value probeTaskServerAndUpdateLocked:@"repeat"]&&value.helloReads==1&&parses==1);
    }}
}
int main(){@autoreleasepool{
    parityCases();coherenceCases();
    puts("Supervisor probe passed: frozen PID/path/version/invalid-hello decisions and effects, 3-to-2 task/2-to-1 JSON fallback counts, same-response coherence, fresh later probes and 1000 lifecycles. Process/socket providers controlled; device qualification pending.");
}return 0;}
