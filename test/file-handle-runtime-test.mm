#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import "../shared/TLinkJSFileHandle.h"
#import "LegacyFileHandle.h"
#include "../shared/TLinkJSFileLine.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cassert>
#include <algorithm>
#include <cstdio>
#include <set>
#include <string>
#include <vector>
#include <stdexcept>
#include <cstdlib>
#include <cstring>
#include "ax-node-pool-owner.h"
void TLinkAXFixtureOwnerDidDrain(void){}
static bool fileTrackPools=false;
static unsigned fileIOThrow=0,fileWrites=0,fileWriteInterrupts=0;
static size_t fileMaxWrite=SIZE_MAX;
static off_t fileWriteFaultAt=-1;
static bool fileZeroWrite=false,fileWriteOverrun=false;
static bool fileReadOverrun=false;
static const char *fileUTF8Pointer(CFStringRef string,CFStringEncoding encoding);
#define CFStringGetCStringPtr fileUTF8Pointer
#include "../shared/TLinkUTF8Data.h"
#undef CFStringGetCStringPtr
static std::set<int> fileFDs;
static size_t fileReads=0,fileRewinds=0,fileMaxRead=8192;
static unsigned fileInterrupts=0;
static off_t fileFaultAt=-1;
static bool fileStatFails=false,fileRewindFails=false,fileProbeFails=false,fileOpening=false;
static int fileInjected=-1,fileLastFD=-1;
static int fileTestOpen(const char *path,int flags,mode_t mode){
    const int fd=fileInjected>=0 ? fileInjected : ::open(path,flags,mode);fileInjected=-1;
    if(fd>=0){assert(fileFDs.insert(fd).second);fileLastFD=fd;}return fd;
}
static int fileTestClose(int fd){assert(fileFDs.erase(fd)==1);if(fileLastFD==fd)fileLastFD=-1;return ::close(fd);}
static int fileTestStat(int fd,struct stat *st){if(fileStatFails){errno=EIO;return -1;}return ::fstat(fd,st);}
static off_t fileTestSeek(int fd,off_t offset,int whence){
    if(fileOpening&&fileProbeFails&&whence==SEEK_CUR&&offset==0){errno=ESPIPE;return -1;}
    if(whence==SEEK_CUR&&offset<0){++fileRewinds;if(fileRewindFails){errno=EIO;return -1;}}
    return ::lseek(fd,offset,whence);
}
static ssize_t fileTestRead(int fd,void *out,size_t count){
    if(fileTrackPools)TLinkAXFixtureAutoreleaseOwner();
    if(fileIOThrow==1)[NSException raise:@"FilePayloadFixture" format:@"read"];
    if(fileIOThrow==2)throw std::runtime_error("read");
    ++fileReads;if(fileInterrupts){--fileInterrupts;errno=EINTR;return -1;}
    if(fileReadOverrun)return ssize_t(count+1);
    count=std::min(count,fileMaxRead);
    if(fileFaultAt>=0){const off_t offset=::lseek(fd,0,SEEK_CUR);assert(offset>=0);
        if(offset>=fileFaultAt){errno=EIO;return -1;}count=std::min(count,size_t(fileFaultAt-offset));}
    return ::read(fd,out,count);
}
static ssize_t fileTestWrite(int fd,const void *bytes,size_t count){
    ++fileWrites;if(fileTrackPools)TLinkAXFixtureAutoreleaseOwner();
    if(fileWriteInterrupts){--fileWriteInterrupts;errno=EINTR;return -1;}
    if(fileWriteOverrun)return ssize_t(count+1);
    if(fileZeroWrite)return 0;
    if(fileIOThrow==1)[NSException raise:@"FilePayloadFixture" format:@"write"];
    if(fileIOThrow==2)throw std::runtime_error("write");
    count=std::min(count,fileMaxWrite);
    if(fileWriteFaultAt>=0){const off_t offset=::lseek(fd,0,SEEK_CUR);assert(offset>=0);if(offset>=fileWriteFaultAt){errno=EIO;return -1;}count=std::min(count,size_t(fileWriteFaultAt-offset));}
    return ::write(fd,bytes,count);
}
#define open(path,flags,mode) fileTestOpen(path,flags,mode)
#define close(fd) fileTestClose(fd)
#define read(fd,bytes,count) fileTestRead(fd,bytes,count)
#define write(fd,bytes,count) fileTestWrite(fd,bytes,count)
#define lseek(fd,offset,whence) fileTestSeek(fd,offset,whence)
#define fstat(fd,st) fileTestStat(fd,st)
#include "../shared/TLinkJSFileHandle.mm"
#define TLinkJSFileHandle LegacyTLinkJSFileHandle
#define TLinkJSFileModeIsValid LegacyTLinkJSFileModeIsValid
#define TLinkJSFileModeWrites LegacyTLinkJSFileModeWrites
#define TLinkJSFileHandleCreateJSObject LegacyTLinkJSFileHandleCreateJSObject
#define TLinkJSFileNormalizeMode LegacyTLinkJSFileNormalizeMode
#define TLinkJSFileError LegacyTLinkJSFileError
#define TLinkJSFileDataResult LegacyTLinkJSFileDataResult
#include "fixtures/js-file-handle-legacy-v1.inc"
#undef TLinkJSFileDataResult
#undef TLinkJSFileError
#undef TLinkJSFileNormalizeMode
#undef TLinkJSFileHandleCreateJSObject
#undef TLinkJSFileModeWrites
#undef TLinkJSFileModeIsValid
#undef TLinkJSFileHandle
#undef fstat
#undef lseek
#undef read
#undef write
#undef close
#undef open
struct FileTrace {
    NSArray *results=nil;NSData *contents=nil;size_t reads=0;
    FileTrace(NSArray *values,NSData *bytes,size_t count):results(values),contents(bytes),reads(count){}
};
static void fileReset(){assert(fileFDs.empty());fileReads=fileRewinds=0;fileMaxRead=8192;fileInterrupts=0;fileFaultAt=-1;fileStatFails=fileRewindFails=fileProbeFails=fileOpening=false;fileInjected=fileLastFD=-1;fileTrackPools=false;fileIOThrow=fileWrites=fileWriteInterrupts=0;fileMaxWrite=SIZE_MAX;fileWriteFaultAt=-1;fileZeroWrite=fileWriteOverrun=fileReadOverrun=false;}
static TLinkJSFileHandle *fileOpen(bool legacy,NSString *path,NSString *mode,NSUInteger cap){
    NSString *error=nil;
    fileOpening=true;
    id handle=legacy?[LegacyTLinkJSFileHandle openPath:path mode:mode handleId:1 maxTransferBytes:cap error:&error]:[TLinkJSFileHandle openPath:path mode:mode handleId:1 maxTransferBytes:cap error:&error];
    fileOpening=false;
    assert(handle&&!error);return (TLinkJSFileHandle *)handle;
}
static FileTrace fileSequence(bool legacy,NSString *path,NSData *bytes,NSUInteger cap,NSString *mode,unsigned scenario){
    fileReset();assert([bytes writeToFile:path atomically:YES]);fileStatFails=scenario==1;fileProbeFails=scenario==4;
    TLinkJSFileHandle *handle=fileOpen(legacy,path,mode,cap);if(scenario==2){fileMaxRead=7;fileInterrupts=3;}if(scenario==3)fileFaultAt=5;
    NSMutableArray *trace=[NSMutableArray array];
    [trace addObject:[handle readLine]];[trace addObject:[handle tell]];
    [trace addObject:[handle readRequest:@3]];[trace addObject:[handle tell]];
    [trace addObject:[handle seekWhence:@"cur" offset:-2]];[trace addObject:[handle readLine]];
    [trace addObject:[handle writeText:@"XY\n"]];[trace addObject:[handle flush]];[trace addObject:[handle tell]];
    [trace addObject:[handle seekWhence:@"set" offset:0]];[trace addObject:[handle readRequest:@"*l"]];
    [trace addObject:[handle readRequest:@0]];[trace addObject:[handle readRequest:@"*a"]];[trace addObject:[handle tell]];
    [trace addObject:[handle seekWhence:@"end" offset:0]];[trace addObject:[handle readLine]];
    [trace addObject:[handle close]];[trace addObject:[handle readLine]];[trace addObject:[handle close]];
    assert(fileFDs.empty());return {[trace copy],[NSData dataWithContentsOfFile:path],fileReads};
}
static void fileParity(NSString *path,NSData *bytes,NSUInteger cap,NSString *mode=@"r+",unsigned scenario=0){
    const FileTrace expected=fileSequence(true,path,bytes,cap,mode,scenario),actual=fileSequence(false,path,bytes,cap,mode,scenario);
    const bool same=[expected.results isEqual:actual.results]&&[expected.contents isEqual:actual.contents];
    if(!same){fprintf(stdout,"FileHandle parity failed: %s\n",[NSString stringWithFormat:@"cap=%lu mode=%@ scenario=%u expected=%@ actual=%@",(unsigned long)cap,mode,scenario,expected.results,actual.results].UTF8String);fflush(stdout);}assert(same);
    if(scenario==1||scenario==4)assert(actual.reads==expected.reads);
}
static FileTrace filePipe(bool legacy){
    fileReset();int fds[2];assert(::pipe(fds)==0);assert(::write(fds[1],"abc\nrest",8)==8);assert(::close(fds[1])==0);fileInjected=fds[0];
    TLinkJSFileHandle *handle=fileOpen(legacy,@"controlled-pipe",@"r",1024);
    NSArray *trace=@[[handle readLine],[handle readRequest:@2],[handle readLine],[handle tell],[handle readLine],[handle close]];
    assert(fileFDs.empty());return {trace,nil,fileReads};
}
#include "file-handle-payload-runtime-fixture.inc"
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]],*path=[root stringByAppendingPathComponent:@"handle.bin"];
    puts("FileHandle Foundation: actual/frozen complete classes, POSIX descriptors and JSCore");fflush(stdout);
    for(NSString *text in @[@"",@"\n",@"\r\n",@"abc\nnext\r\nlast",@"abc\r",@"ảnh 测试 😀\nnext"]){
        NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];
        for(NSUInteger cap:{NSUInteger(1),NSUInteger(2),NSUInteger(3),NSUInteger(128),NSUInteger(8192)})for(NSString *mode in @[@"r",@"rb",@"r+",@"rb+",@"w",@"wb",@"w+",@"wb+",@"a",@"ab",@"a+",@"ab+"])fileParity(path,data,cap,mode);
    }
    const std::string binary=std::string("a\0b\xff\r\nrest",10);NSData *data=[NSData dataWithBytes:binary.data() length:binary.size()];fileParity(path,data,128);
    const std::string longLine=std::string(32768,'x')+"\r\nnext\n";data=[NSData dataWithBytes:longLine.data() length:longLine.size()];
    for(unsigned scenario=0;scenario<=4;++scenario)fileParity(path,data,65536,@"r+",scenario);
    // No tail cache: an external overwrite/truncate/growth is seen by the next read.
    fileReset();assert([[@"abc\nold\n" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);TLinkJSFileHandle *handle=fileOpen(false,path,@"r+",1024);const int fd=fileLastFD;
    assert([[handle readLine][@"line"] isEqual:@"abc"]);assert(::pwrite(fd,"new",3,4)==3);assert([[handle readLine][@"line"] isEqual:@"new"]);
    assert(::ftruncate(fd,0)==0);assert([[handle readLine][@"eof"] boolValue]);assert(::pwrite(fd,"grown\n",6,0)==6);[handle seekWhence:@"set" offset:0];assert([[handle readLine][@"line"] isEqual:@"grown"]);[handle close];
    const FileTrace oldPipe=filePipe(true),newPipe=filePipe(false);assert([oldPipe.results isEqual:newPipe.results]&&oldPipe.reads==newPipe.reads);
    fileReset();assert([[@"abc\nrest" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);handle=fileOpen(false,path,@"r",1024);fileRewindFails=true;
    NSDictionary *failed=[handle readLine];assert(![failed[@"ok"] boolValue]&&[failed[@"error"] hasPrefix:@"file_read_failed"]&&fileRewinds==1);
    fileRewindFails=false;[handle seekWhence:@"set" offset:0];assert([[handle readLine][@"line"] isEqual:@"abc"]);[handle close];
    for(bool legacy:{true,false}){
        fileReset();assert([[@"js\nnext" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);handle=fileOpen(legacy,path,@"r+",1024);
        JSContext *context=[JSContext new];context[@"file"]=legacy?LegacyTLinkJSFileHandleCreateJSObject(context,(LegacyTLinkJSFileHandle *)handle,nil):TLinkJSFileHandleCreateJSObject(context,handle,nil);
        NSDictionary *line=[[context evaluateScript:@"file.readLine()"] toDictionary];assert([line[@"line"] isEqual:@"js"]);
        assert([[[context evaluateScript:@"file.tell()"] toDictionary][@"offset"] intValue]==3);
        [context evaluateScript:@"file.seek('set',0);file.write('XY');file.seek('set',0)"];line=[[context evaluateScript:@"file.read('line')"] toDictionary];assert([line[@"line"] isEqual:@"XY"]);
        [context evaluateScript:@"file.close()"];assert(!context.exception&&fileFDs.empty());context[@"file"]=nil;
    }
    for(unsigned n=0;n<128;++n){@autoreleasepool{fileParity(path,[@"one\r\ntwo\nlast" dataUsingEncoding:NSUTF8StringEncoding],8);}}
    filePayloadRuntimeCases(path);
    assert(fileFDs.empty());assert([[NSFileManager defaultManager] removeItemAtPath:path error:nil]);
    puts("FileHandle Foundation passed: frozen full replies/mixed read-write-seek/tell/append/limits/CR/EOF, real UTF8/binary files, short/EINTR/EIO, stat fallback, real pipe, fresh external edits, rewind failure/recovery, JS bindings and 128 balanced lifecycles.");
}}
