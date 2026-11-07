// Store the exact emitted native blocks for direct calls. This measures their
// own pools without relying on JavaScriptCore's internal call/GC pools.
@interface FileBindingObject:NSObject {
@public NSMutableDictionary *values;
}
- (void)setObject:(id)object forKeyedSubscript:(id)key;
@end
@implementation FileBindingObject
- (instancetype)init {self=[super init];if(self)values=[NSMutableDictionary dictionary];return self;}
- (void)setObject:(id)object forKeyedSubscript:(id)key {values[key]=[object copy];}
@end
static JSValue *FixtureFileBindingObject(JSContext *context){(void)context;return (JSValue *)[FileBindingObject new];}
#include "FilePlanBindings-Current.inc"
#include "FilePlanBindings-Before.inc"
static bool fileBindingCreation=false,fileBindingCalls=false;
static unsigned fileBindingFault=0,fileBindingCloseFault=0;
static NSDictionary *fileBindingResult(NSString *kind,id value){
    if(fileBindingCalls)TLinkAXFixtureAutoreleaseOwner();
    if(fileBindingFault==1)[NSException raise:@"FileBindingFixture" format:@"call"];
    if(fileBindingFault==2)throw std::runtime_error("call");
    return @{@"ok":@YES,@"kind":kind,@"value":value?:[NSNull null]};
}
@interface FileBindingHandle:TLinkJSFileHandle {
@public BOOL bindingClosed;
}
@end
@implementation FileBindingHandle
- (NSUInteger)handleId {if(fileBindingCreation)TLinkAXFixtureAutoreleaseOwner();return 7;}
- (NSString *)path {if(fileBindingCreation)TLinkAXFixtureAutoreleaseOwner();return @"ảnh/测试";}
- (NSString *)mode {if(fileBindingCreation)TLinkAXFixtureAutoreleaseOwner();return @"r+";}
- (NSDictionary *)readRequest:(id)value {return fileBindingResult(@"read",value);}
- (NSDictionary *)readLine {return fileBindingResult(@"readLine",@"line");}
- (NSDictionary *)writeText:(NSString *)value {return fileBindingResult(@"write",value);}
- (NSDictionary *)writeBase64:(NSString *)value {return fileBindingResult(@"writeBase64",value);}
- (NSDictionary *)seekWhence:(NSString *)value offset:(long long)offset {return fileBindingResult(@"seek",@[value,@(offset)]);}
- (NSDictionary *)tell {return fileBindingResult(@"tell",@3);}
- (NSDictionary *)flush {return fileBindingResult(@"flush",@YES);}
- (BOOL)isClosed {if(fileBindingCalls)TLinkAXFixtureAutoreleaseOwner();return bindingClosed;}
- (NSDictionary *)close {bindingClosed=YES;return fileBindingResult(@"close",@YES);}
@end
static NSDictionary *fileBindingInvoke(FileBindingObject *object,NSUInteger operation,JSValue *input){
    if(operation==0){NSDictionary *(^call)(JSValue *)=object->values[@"read"];return call(input);}
    if(operation==1){NSDictionary *(^call)(void)=object->values[@"readLine"];return call();}
    if(operation==2){NSDictionary *(^call)(JSValue *)=object->values[@"write"];return call(input);}
    if(operation==3){NSDictionary *(^call)(NSString *)=object->values[@"writeBase64"];return call(nil);}
    if(operation==4){NSDictionary *(^call)(NSString *,double)=object->values[@"seek"];return call(nil,-3.75);}
    if(operation==5){NSDictionary *(^call)(void)=object->values[@"tell"];return call();}
    if(operation==6){NSDictionary *(^call)(void)=object->values[@"flush"];return call();}
    if(operation==7){BOOL (^call)(void)=object->values[@"isClosed"];return @{@"closed":@(call())};}
    NSDictionary *(^call)(void)=object->values[@"close"];return call();
}
static void filePlanBindingCases(){
    JSContext *context=[JSContext new];NSDictionary *beforeMetadata=nil;NSMutableArray *expected=[NSMutableArray array];
    NSArray *inputs=@[[JSValue valueWithUndefinedInContext:context],[JSValue valueWithNullInContext:context],[JSValue valueWithObject:@"ảnh\0tail" inContext:context],[JSValue valueWithObject:@42 inContext:context]];
    for(bool modern:{false,true}){
        FileBindingHandle *handle=[FileBindingHandle new];FileBindingObject *object=nil;__block unsigned closes=0;
        void (^closed)(NSUInteger)=^(NSUInteger identifier){
            assert(identifier==7);++closes;if(fileBindingCalls)TLinkAXFixtureAutoreleaseOwner();
            if(fileBindingCloseFault==1)[NSException raise:@"FileBindingFixture" format:@"close callback"];
            if(fileBindingCloseFault==2)throw std::runtime_error("close callback");
        };
        @autoreleasepool {
            TLinkAXFixtureResetOwners();fileBindingCreation=true;
            object=(FileBindingObject *)(modern?FixtureCurrentFileBindings(context,handle,closed):FixtureBeforeFileBindings(context,handle,closed));
            fileBindingCreation=false;assert(TLinkAXFixtureCreatedOwners()==3);
            assert(TLinkAXFixtureLiveOwners()==(modern?0U:3U));
        }
        assert(TLinkAXFixtureLiveOwners()==0&&[object->values[@"path"] isEqual:@"ảnh/测试"]);
        NSDictionary *metadata=@{@"id":object->values[@"id"],@"path":object->values[@"path"],@"mode":object->values[@"mode"]};
        if(modern)assert([metadata isEqual:beforeMetadata]);else beforeMetadata=metadata;
        for(NSUInteger operation=0;operation<9;++operation){
            for(JSValue *input in inputs){
                NSDictionary *held=nil;
                @autoreleasepool {
                    TLinkAXFixtureResetOwners();fileBindingCalls=true;
                    held=fileBindingInvoke(object,operation,input);
                    const NSUInteger owners=operation==8?2:1;
                    assert(TLinkAXFixtureCreatedOwners()==owners&&TLinkAXFixtureLiveOwners()==(modern?0U:owners));
                    fileBindingCalls=false;
                }
                assert(held&&TLinkAXFixtureLiveOwners()==0);
                const NSUInteger index=operation*inputs.count+[inputs indexOfObjectIdenticalTo:input];
                if(modern)assert([expected[index] isEqual:held]);else [expected addObject:held];
            }
        }
        assert(closes==inputs.count&&handle->bindingClosed);
        // Exceptions keep the preceding propagation; an outer pool supplies
        // cleanup, with no claim about independent exceptional pool draining.
        for(unsigned fault=1;fault<=2;++fault){
            bool caught=false;
            @autoreleasepool {
                TLinkAXFixtureResetOwners();fileBindingCalls=true;fileBindingFault=fault;
                @try {try {(void)fileBindingInvoke(object,1,inputs[0]);}catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"FileBindingFixture"]);caught=true;}
                fileBindingCalls=false;fileBindingFault=0;
            }
            assert(caught&&TLinkAXFixtureLiveOwners()==0);
        }
        for(unsigned fault=1;fault<=2;++fault){
            bool caught=false;
            @autoreleasepool {
                TLinkAXFixtureResetOwners();fileBindingCalls=true;fileBindingCloseFault=fault;
                @try {try {(void)fileBindingInvoke(object,8,inputs[0]);}catch(const std::runtime_error &){caught=true;}}
                @catch(NSException *exception){assert([exception.name isEqual:@"FileBindingFixture"]);caught=true;}
                fileBindingCalls=false;fileBindingCloseFault=0;
            }
            assert(caught&&handle->bindingClosed&&TLinkAXFixtureLiveOwners()==0);
        }
        assert(closes==inputs.count+2);
    }
    assert(!context.exception&&fileFDs.empty());
}
