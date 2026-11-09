#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <cassert>
#include <algorithm>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <set>
#include <stdexcept>
#include <fcntl.h>
#include <unistd.h>
static const unsigned long long kTLinkJSHelperMaxConsoleLogBytes=512*1024;
static NSString *runPath,*latestPath,*faultPath;
static NSMutableArray *systemRows,*observed;
static unsigned encodes=0,encodeFault=0,dateFault=0,systemFault=0,ioFault=0,opens=0,closes=0,fallbackCloses=0;
static std::set<int> descriptors;
static NSDate *HelperDate(){
    if(dateFault==1)[NSException raise:@"HelperConsole" format:@"date"];
    if(dateFault==2)throw std::runtime_error("date");
    return [NSDate dateWithTimeIntervalSince1970:1000000];
}
static NSData *HelperEncode(NSString *line){
    ++encodes;if(encodeFault==1)return nil;
    if(encodeFault==2)[NSException raise:@"HelperConsole" format:@"encode"];
    if(encodeFault==3)throw std::runtime_error("encode");
    if(encodeFault==4)return [NSMutableData dataWithLength:16385];
    if(encodeFault==5)return [NSData data];
    return [line dataUsingEncoding:NSUTF8StringEncoding];
}
static void HelperSystem(NSString *format,...){
    if(systemFault==1)[NSException raise:@"HelperConsole" format:@"system"];
    if(systemFault==2)throw std::runtime_error("system");
    va_list args;va_start(args,format);NSString *text=[[NSString alloc] initWithFormat:format arguments:args];va_end(args);
    [systemRows addObject:text?:@""];
}
static void HelperObserve(NSData *data,NSString *path){(void)path;[observed addObject:data];}
static bool faultFor(NSString *path){return [path isEqualToString:faultPath];}
@interface HelperOwnedHandle:NSObject
@property int descriptor;
@property(nonatomic,copy) NSString *path;
- (void)seekToEndOfFile;
- (void)writeData:(NSData *)data;
- (void)closeFile;
@end
@implementation HelperOwnedHandle
- (instancetype)init{self=[super init];if(self)_descriptor=-1;return self;}
- (void)seekToEndOfFile{
    if(faultFor(_path)&&ioFault==6)[NSException raise:@"HelperConsole" format:@"seek"];
    if(faultFor(_path)&&ioFault==7)throw std::runtime_error("seek");
    assert(::lseek(_descriptor,0,SEEK_END)>=0);
}
- (void)writeData:(NSData *)data{
    const bool fail=faultFor(_path);
    if(fail&&ioFault==2)[NSException raise:@"HelperConsole" format:@"write"];
    if(fail&&ioFault==3)throw std::runtime_error("write");
    const size_t count=fail&&(ioFault==4||ioFault==5)?std::min(size_t(3),size_t(data.length)):data.length;
    size_t written=0;while(written<count){const ssize_t n=::write(_descriptor,(const uint8_t *)data.bytes+written,count-written);if(n<0&&errno==EINTR)continue;assert(n>0);written+=n;}
    if(fail&&ioFault==4)[NSException raise:@"HelperConsole" format:@"partial"];
    if(fail&&ioFault==5)throw std::runtime_error("partial");
}
- (void)closeFile{
    const int fd=_descriptor;_descriptor=-1;assert(fd>=0&&descriptors.erase(fd)==1);++closes;assert(::close(fd)==0);
    if(faultFor(_path)&&ioFault==8)[NSException raise:@"HelperConsole" format:@"close"];
    if(faultFor(_path)&&ioFault==9)throw std::runtime_error("close");
}
- (void)dealloc{if(_descriptor>=0){assert(descriptors.erase(_descriptor)==1);::close(_descriptor);++fallbackCloses;}}
@end
static HelperOwnedHandle *HelperOpen(NSString *path){
    if(faultFor(path)&&ioFault==1)return nil;
    const int fd=::open(path.fileSystemRepresentation,O_WRONLY);if(fd<0)return nil;
    assert(descriptors.insert(fd).second);++opens;
    HelperOwnedHandle *handle=[HelperOwnedHandle new];assert(handle);handle.descriptor=fd;handle.path=path;return handle;
}
#include "HelperConsoleUnderTest.inc"
@interface CurrentHelperConsole:NSObject<TLinkHelperConsoleFileSink>
@end
@implementation CurrentHelperConsole
#include "HelperConsoleWriter.inc"
@end
@interface BeforeHelperConsole:NSObject
- (void)appendLine:(NSString *)line toPath:(NSString *)path;
@end
@implementation BeforeHelperConsole
#include "HelperConsoleBeforeWriter.inc"
@end
#include "HelperConsoleHooks.inc"
static void reset(size_t initial){
    assert(descriptors.empty()&&opens==closes&&fallbackCloses==0);
    ioFault=encodeFault=dateFault=systemFault=0;faultPath=nil;encodes=opens=closes=0;
    [systemRows removeAllObjects];[observed removeAllObjects];
    for(NSString *path in @[runPath,latestPath]){[[NSFileManager defaultManager] removeItemAtPath:path error:nil];if(initial!=SIZE_MAX)assert([[NSMutableData dataWithLength:initial] writeToFile:path atomically:YES]);}
}
static NSDictionary *trace(){
    if(!descriptors.empty()||opens!=closes||fallbackCloses)fprintf(stderr,"Helper console resources: io=%u encode=%u date=%u system=%u open=%u close=%u fallback=%u live=%zu\n",ioFault,encodeFault,dateFault,systemFault,opens,closes,fallbackCloses,descriptors.size());
    assert(descriptors.empty()&&opens==closes&&fallbackCloses==0);
    return @{@"run":[NSData dataWithContentsOfFile:runPath]?:[NSData data],@"latest":[NSData dataWithContentsOfFile:latestPath]?:[NSData data],@"system":[systemRows copy]};
}
static void parityCases(){
    for(size_t initial:{SIZE_MAX,size_t(0),size_t(524288),size_t(524289)}){
        for(NSString *level in @[@"log",@"",@"warn",@"ảnh"]){
            for(NSString *message in @[@"",@"plain",@"a\0b",@"ảnh 测试 😀",@"a\r\nb"]){
                @autoreleasepool {
                    reset(initial);__attribute__((objc_precise_lifetime)) BeforeHelperConsole *before=[BeforeHelperConsole new];JSContext *old=[JSContext new];InstallBefore(old,before,@"run",runPath,latestPath);
                    [old[@"_tlinkautoLog"] callWithArguments:@[level,message]];assert(!old.exception);NSDictionary *expected=trace();assert(encodes==2);
                    reset(initial);__attribute__((objc_precise_lifetime)) CurrentHelperConsole *current=[CurrentHelperConsole new];JSContext *now=[JSContext new];InstallCurrent(now,current,@"run",runPath,latestPath);
                    [now[@"_tlinkautoLog"] callWithArguments:@[level,message]];assert(!now.exception);
                    NSDictionary *actual=trace();if(![expected isEqual:actual])fprintf(stderr,"Helper console parity: initial=%zu expected=%.4096s actual=%.4096s\n",initial,expected.description.UTF8String,actual.description.UTF8String);
                    assert([expected isEqual:actual]);assert(encodes==1&&observed.count==2&&observed[0]==observed[1]);
                }
            }
        }
    }
}
@interface HelperBadDescription:NSObject
@property unsigned fault;
@end
@implementation HelperBadDescription
- (NSString *)description{if(_fault==1)[NSException raise:@"HelperConsole" format:@"description"];throw std::runtime_error("description");}
@end
static void boundsAndLifetimeCases(){
    reset(0);TLinkHelperConsoleLine held;
    @autoreleasepool {
        NSMutableString *run=[@"run" mutableCopy],*level=[@"log" mutableCopy],*message=[@"original" mutableCopy];
        held=TLinkHelperConsolePrepare(run,level,message);[run setString:@"changed"];[level setString:@"changed"];[message setString:@"changed"];
    }
    assert(held.ready&&[held.run isEqual:@"run"]&&[held.level isEqual:@"log"]&&[held.message isEqual:@"original"]&&held.data.length>0);
    for(size_t length:{size_t(4095),size_t(4096),size_t(4097),size_t(100000)}){
        NSString *input=[@"x" stringByPaddingToLength:length withString:@"x" startingAtIndex:0];
        auto line=TLinkHelperConsolePrepare(input,input,input);assert(line.ready&&line.run.length==64&&line.level.length==64&&line.message.length==std::min(length,size_t(4096))&&line.data&&line.data.length<=16384);
    }
    const unichar pair[2]={0xd83d,0xde00};NSString *emoji=[NSString stringWithCharacters:pair length:2];
    NSString *edge=[[@"x" stringByPaddingToLength:4095 withString:@"x" startingAtIndex:0] stringByAppendingString:emoji];
    auto boundary=TLinkHelperConsolePrepare(nil,nil,edge);assert(boundary.ready&&boundary.message.length==4095&&[boundary.level isEqual:@"log"]&&boundary.run.length==0);
    for(unsigned fault=1;fault<=2;++fault){HelperBadDescription *bad=[HelperBadDescription new];bad.fault=fault;auto rejected=TLinkHelperConsolePrepare(@"run",@"log",(NSString *)bad);assert(!rejected.ready&&!rejected.data);}
    JSContext *context=[JSContext new];__weak CurrentHelperConsole *weak=nil;
    @autoreleasepool {CurrentHelperConsole *owner=[CurrentHelperConsole new];weak=owner;InstallCurrent(context,owner,@"run",runPath,latestPath);}
    assert(!weak);[context[@"_tlinkautoLog"] callWithArguments:@[@"log",@"late"]];assert(!context.exception&&systemRows.count==1&&observed.count==0);
}
static void faultCases(){
    CurrentHelperConsole *owner=[CurrentHelperConsole new];
    for(unsigned fault=1;fault<=9;++fault){
        reset(0);faultPath=runPath;ioFault=fault;
        TLinkHelperConsoleEmit(owner,@"run",@"log",@"message",runPath,latestPath);NSDictionary *state=trace();
        const bool continued=[state[@"latest"] length]>0&&systemRows.count==1&&encodes==1&&observed.count==2;
        if(!continued)fprintf(stderr,"Helper console sink continuation: io=%u encodes=%u observed=%lu system=%lu state=%.4096s\n",fault,encodes,(unsigned long)observed.count,(unsigned long)systemRows.count,state.description.UTF8String);
        assert(continued);
        const NSUInteger runBytes=[state[@"run"] length];if(fault==4||fault==5)assert(runBytes==3);else if(fault==8||fault==9)assert(runBytes==[state[@"latest"] length]);else assert(runBytes==0);
    }
    for(unsigned fault=1;fault<=5;++fault){
        reset(0);encodeFault=fault;TLinkHelperConsoleEmit(owner,@"run",@"log",@"message",runPath,latestPath);
        assert(encodes==1&&observed.count==0&&systemRows.count==1&&[trace()[@"run"] length]==0&&[trace()[@"latest"] length]==0);
    }
    for(unsigned fault=1;fault<=2;++fault){
        reset(0);dateFault=fault;TLinkHelperConsoleEmit(owner,@"run",@"log",@"message",runPath,latestPath);assert(encodes==0&&observed.count==0&&systemRows.count==1);
        reset(0);systemFault=fault;TLinkHelperConsoleEmit(owner,@"run",@"log",@"message",runPath,latestPath);assert(encodes==1&&observed.count==2&&systemRows.count==0&&[trace()[@"run"] length]>0&&[trace()[@"latest"] length]>0);
    }
    reset(0);TLinkHelperConsoleEmit(owner,@"run",@"log",@"recovered",runPath,latestPath);assert(encodes==1&&systemRows.count==1&&[trace()[@"run"] isEqual:trace()[@"latest"]]);
}
int main(int argc,char **argv){@autoreleasepool{
    setvbuf(stdout,nullptr,_IONBF,0);
    assert(argc==2);systemRows=[NSMutableArray array];observed=[NSMutableArray array];NSString *root=[NSString stringWithUTF8String:argv[1]];
    runPath=[root stringByAppendingPathComponent:@"run.log"];latestPath=[root stringByAppendingPathComponent:@"latest.log"];
    puts("Helper console Foundation: frozen actual hook/writer and real JSCore/POSIX file parity");parityCases();
    puts("Helper console Foundation: bounded snapshots, surrogate boundaries and pool/weak lifetime");boundsAndLifetimeCases();
    puts("Helper console Foundation: independent sink faults, partial writes and recovery");faultCases();assert(descriptors.empty()&&fallbackCloses==0);
    puts("Helper console passed: 80 frozen actual JSCore/file/system/rotation comparisons, one shared encode versus two, bounded surrogate-safe immutable snapshots, pool/weak ownership, NS/C++ path/partial/seek/close/format/encode/system isolation, no prefix replay and recovery. Real system log/device latency remains unqualified.");
}return 0;}
