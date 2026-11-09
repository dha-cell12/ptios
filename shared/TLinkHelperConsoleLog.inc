#if !__has_feature(objc_arc)
#error "TLinkHelperConsoleLog.inc requires ARC"
#endif
#include "TLinkConsoleLogBudget.h"
@protocol TLinkHelperConsoleFileSink <NSObject>
- (void)appendPreparedConsoleData:(NSData *)data toPath:(NSString *)path;
@end
struct TLinkHelperConsoleLine {
    NSString *run=nil,*level=nil,*message=nil;
    NSData *data=nil;
    bool ready=false;
    bool truncated=false;
};
static NSString *TLinkHelperConsolePrefix(id value,NSString *fallback,size_t limit,bool *truncated=nullptr){
    NSString *text=value ? ([value isKindOfClass:[NSString class]] ? value : [value description]) : fallback;
    text=text ?: @"";
    const size_t length=text.length;
    const size_t count=TLinkConsoleLogPrefix(length,limit,[text](size_t n){return [text characterAtIndex:n];});
    if(truncated&&count<length)*truncated=true;
    return [[text substringToIndex:count] copy];
}
static TLinkHelperConsoleLine TLinkHelperConsolePrepare(NSString *run,NSString *level,NSString *message){
    TLinkHelperConsoleLine result;
    @autoreleasepool {
        @try {try {
            result.run=TLinkHelperConsolePrefix(run,@"",TLinkConsoleLogLevelUnits,&result.truncated);
            result.level=TLinkHelperConsolePrefix(level,@"log",TLinkConsoleLogLevelUnits,&result.truncated);
            result.message=TLinkHelperConsolePrefix(message,@"",TLinkConsoleLogMessageUnits,&result.truncated);
            result.ready=true;
            @try {try {
                NSString *line=[NSString stringWithFormat:@"[%@][%@][%@] %@\n",[NSDate date],result.run,result.level,result.message];
                result.data=[line dataUsingEncoding:NSUTF8StringEncoding];
                if(!result.data.length||result.data.length>TLinkConsoleLogLineBytes)result.data=nil;
            }catch(...) {result.data=nil;}} @catch(NSException *exception){(void)exception;result.data=nil;}
        }catch(...) {result=TLinkHelperConsoleLine();}} @catch(NSException *exception){(void)exception;result=TLinkHelperConsoleLine();}
    }
    return result;
}
static void TLinkHelperConsoleEmit(id<TLinkHelperConsoleFileSink> sink,NSString *run,NSString *level,NSString *message,NSString *path,NSString *latest){
    @autoreleasepool {
        const auto line=TLinkHelperConsolePrepare(run,level,message);if(!line.ready)return;
        if(line.data){
            @try {try {[sink appendPreparedConsoleData:line.data toPath:path];}catch(...) {}} @catch(NSException *exception){(void)exception;}
            @try {try {[sink appendPreparedConsoleData:line.data toPath:latest];}catch(...) {}} @catch(NSException *exception){(void)exception;}
        }
        @try {try {NSLog(@"tlinkauto-jsd[%@][%@]: %@",line.run,line.level,line.message);}catch(...) {}} @catch(NSException *exception){(void)exception;}
    }
}
