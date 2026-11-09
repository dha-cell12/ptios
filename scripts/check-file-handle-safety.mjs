import {restoreFileReadStorage,checkFileReadStorageCore} from './lib/file-read-storage-baseline.mjs';
import {restoreFileRepresentation} from './lib/file-representation-baseline.mjs';
import {restoreFileLineFill,checkFileLineFillCore} from './lib/file-line-fill-baseline.mjs';
import {restoreStorageJSONWrites,storageJSONWriteSpecs,storageJSONWriteBefore,checkPreparedJSONText} from './lib/storage-json-write-baseline.mjs';
import {restoreFilePlan,restoreFilePlanHeader,restoreFilePlanFrontend,checkFileModePlan,filePlanSpecs} from './lib/file-plan-baseline.mjs';
import {restoreStorageOperations,storageOperationSpecs,storageOperationPart,storageOperationBefore} from './lib/storage-operations-baseline.mjs';
import assert from 'node:assert/strict';
import {access,readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {restoreVPNPrivateCaller} from './lib/vpn-private-stop-baseline.mjs';
import {restoreFileLifecycle} from './lib/file-lifecycle-baseline.mjs';
import {restoreFilePayload,checkFileIOHeader} from './lib/file-handle-payload-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [actualFileSource,currentHeader,frozen]=await Promise.all(['shared/TLinkJSFileHandle.mm','shared/TLinkJSFileHandle.h','test/fixtures/js-file-handle-legacy-v1.inc'].map(read));
const beforeReadStorage=restoreFileReadStorage(actualFileSource);
checkFileReadStorageCore(await read('shared/TLinkJSFileReadStorage.h'));
const beforeRepresentation=restoreFileRepresentation(actualFileSource);
const lifecycleSource=restoreFilePlan(actualFileSource),header=restoreFilePlanHeader(currentHeader);
checkFileModePlan(await read('shared/TLinkJSFileModePlan.h'));
checkPreparedJSONText(await read('shared/TLinkPreparedJSONText.inc'));
checkFileLineFillCore(await read('shared/TLinkJSFileLineInto.h'));
const beforeLineFill=restoreFileLineFill(actualFileSource);
const beforeOpenPlan=await read('test/fixtures/file-plan-open-before-c03al.inc');
const physicalMarker='    const char *filePath = [path fileSystemRepresentation];';
const commonStart=actualFileSource.indexOf('             normalizedMode:(NSString *)normalizedMode\n');
assert.ok(commonStart>=0);
assert.equal(actualFileSource.slice(actualFileSource.indexOf(physicalMarker,commonStart),actualFileSource.indexOf('- (instancetype)init',commonStart)),beforeOpenPlan.slice(beforeOpenPlan.indexOf(physicalMarker)),'complete physical open/metadata/constructor/descriptor retirement body unchanged');
const payloadSource=restoreFileLifecycle(lifecycleSource);
const openOwner=await read('shared/TLinkJSFileOpen.h');
assert.equal(createHash('sha256').update(openOwner).digest('hex'),'4ab1fe07e7b436cb8c57a1ac4ceba1109adda18b9278e2c4cd89983e19bd5187','complete descriptor handoff policy');
assert.match(lifecycleSource,/TLinkJSFileOpenOwner pending\(fd\)[\s\S]*@try[\s\S]*handle->_fd = pending.release\(\)[\s\S]*@finally[\s\S]*pending.retire/);
assert.match(lifecycleSource,/- \(instancetype\)init[\s\S]*_fd = -1;[\s\S]*_closed = YES;/);
console.log('File lifecycle source passed: normalized mode reuse, canonical whence, nil/default init, late descriptor handoff/finally retirement and lifecycle pools; complete prior class retained.');
const source=restoreFilePayload(payloadSource);
checkFileIOHeader(await read('shared/TLinkJSFileIO.h'));
assert.match(payloadSource,/TLinkJSFileIO::ReadInto[\s\S]*setLength:used\+amount[\s\S]*mutableBytes[\s\S]*setLength:input.bytes/);
assert.match(payloadSource,/TLinkJSFileIO::WriteAll/);
assert.match(payloadSource,/TLinkUTF8DataFromString\(text \?: @""\)/);
const between=(text,a,b)=>{const x=text.indexOf(a),y=text.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return text.slice(x,y);};
const old=frozen.slice(frozen.indexOf('\n')+1);
const line=between(source,'- (NSDictionary *)readLine','- (NSDictionary *)writeData:');
const oldLine=between(old,'- (NSDictionary *)readLine','- (NSDictionary *)writeData:');
const oldLoop=between(oldLine,'        BOOL eof = NO;','        if (data.length > 0)');
const loop=between(line,'        const int fd = _fd;','        if (data.length > 0)');
const restored=source.replace('#include "TLinkJSFileLine.h"\n','').replace('    BOOL _lineReadChunked;\n','').replace('    struct stat lineStat;\n    handle->_lineReadChunked = handle->_readable && fstat(fd, &lineStat) == 0 && S_ISREG(lineStat.st_mode) && lseek(fd, 0, SEEK_CUR) >= 0;\n','').replace(loop,oldLoop);
assert.equal(restored.trim(),old.trim(),'only readLine I/O and once-open regular-file selection change');
assert.match(line,/TLinkJSFileReadLine\(_maxTransferBytes, _lineReadChunked,[\s\S]*::read\(fd, bytes, count\)[\s\S]*::lseek\(fd, -static_cast<off_t>\(count\), SEEK_CUR\)[\s\S]*appendBytes:bytes length:count/);
assert.doesNotMatch(line,/read\(_fd, &byte, 1\)|NoCopy/);
const storageSpecs=[
    ['pccontrol/jsruntime/TLinkInProcessNativeBridge.mm','    else if ([method isEqualToString:TLinkJSNativeMethodWriteText])','    else if ([method isEqualToString:TLinkJSNativeMethodReadJSON])','storage-write-text-legacy-v1.inc','StorageWriteTextUnderTest.inc','1c64feba57b0f3c09981c7c483b8b0355b6b8c9998429ae3d7b404326f3ad9cc'],
    ['tlinkauto-jsd/TLinkJSHelperServer.mm','- (NSDictionary *)writeText:','- (void)closeActiveFileHandles','storage-helper-write-text-legacy-v1.inc','StorageHelperWriteTextUnderTest.inc','fef72ddec3d5eac5ba56453432b46683f8df4fe40f36a2c1314ab8dc1b6ddeb6'],
    ['stream-app/streamd/POCSocketServer.mm','    device[@"writeText"] =','    device[@"openFile"] =','storage-trollstore-write-text-legacy-v1.inc','StorageTrollWriteTextUnderTest.inc','e024f141e29eaa6cd08d28804595a86e537e8e15cd3c964409309d641b66f1d4'],
];
const storageChunks=[];
const readJSONSpecs=[
    ['pccontrol/jsruntime/TLinkInProcessNativeBridge.mm','    else if ([method isEqualToString:TLinkJSNativeMethodReadJSON])','    else if ([method isEqualToString:TLinkJSNativeMethodWriteJSON])','storage-read-json-legacy-v1.inc','StorageReadJSONUnderTest.inc','#include "../../shared/TLinkUTF8Data.h"\n','0cbea81bce778d20f580f34730c41a81d6e111ccb752ff6dbf561e1d66a4397e'],
    ['tlinkauto-jsd/TLinkJSHelperServer.mm','- (NSDictionary *)readJSONAtRelativePath:','- (NSDictionary *)writeJSONValue:','storage-helper-read-json-legacy-v1.inc','StorageHelperReadJSONUnderTest.inc','#include "../shared/TLinkUTF8Data.h"\n','6432c8f1b7d0e1b032c13b6f864d5a37e5d1ea6339a8c8a9a1cdc6c513035af3'],
];
const storageBeforeJSON=new Map();
for(const [path,start,end,legacyName,output,include,hash] of readJSONSpecs){
    const current=await read(path),text=restoreStorageOperations(current,path.startsWith('pccontrol/')?'root':'helper',true),chunk=between(text,start,end),legacy=(await read('test/fixtures/'+legacyName)).split('\n').slice(1).join('\n');
    assert.equal(chunk.replace('TLinkUTF8DataFromString(textResult[@"text"])','[textResult[@"text"] dataUsingEncoding:NSUTF8StringEncoding]').trim(),legacy.trim());
    const previous=text.replace(include,'').replace(chunk,legacy);
    assert.equal(createHash('sha256').update(previous.trim()).digest('hex'),hash,'only readJSON data view/header changes complete user-passed C03z source at 54991dd3: '+path);
    storageBeforeJSON.set(path,previous);storageChunks.push([output,between(current,start,end)]);
}
const utf8View=await read('shared/TLinkUTF8Data.h');
const previousUTF8=await read('test/fixtures/storage-utf8-before-c03ai.inc');
assert.equal(utf8View.replace('    @autoreleasepool {\n','').replace('    }\n}\n#endif','}\n#endif'),previousUTF8,'only normal UTF8-view pool changes; complete ownership/encoding fallback retained');
assert.match(utf8View,/snapshot = \[text copy\][\s\S]*CFStringGetCStringPtr[\s\S]*if \(!bytes\) return \[snapshot dataUsingEncoding:NSUTF8StringEncoding\]/);
assert.match(utf8View,/initWithBytesNoCopy:[\s\S]*deallocator:[\s\S]*\[snapshot length\]/);
assert.doesNotMatch(utf8View,/\[snapshot UTF8String\]|strlen|free\(/);
console.log('Storage readJSON source passed: direct immutable CF UTF8 storage with retained owner, original encoder fallback and complete previous reader/policy source.');
for(const [path,start,end,legacyName,output,hash] of storageSpecs){
    const actual=await read(path);
    const currentText=storageBeforeJSON.get(path)||restoreStorageOperations(actual,'troll',true);
    const text=path==='stream-app/streamd/POCSocketServer.mm'?restoreVPNPrivateCaller(currentText):currentText;
    const chunk=between(text,start,end),legacy=(await read('test/fixtures/'+legacyName)).split('\n').slice(1).join('\n');
    const restoredChunk=chunk.replace('NSUInteger bytes = [safeText lengthOfBytesUsingEncoding:NSUTF8StringEncoding];','NSData *data = [safeText dataUsingEncoding:NSUTF8StringEncoding];')
        .replace('if (bytes >','if ([data length] >').replace('@(bytes)','@([data length])')
        .replace('NSUInteger byteCount = [safeText lengthOfBytesUsingEncoding:NSUTF8StringEncoding];','NSUInteger byteCount = [[safeText dataUsingEncoding:NSUTF8StringEncoding] length];');
    assert.equal(restoredChunk.trim(),legacy.trim(),'only writeText byte counting changes: '+path);
    assert.equal(createHash('sha256').update(text.replace(chunk,legacy).trim()).digest('hex'),hash,'complete user-passed source at adaf252c: '+path);
    assert.match(chunk,/lengthOfBytesUsingEncoding:NSUTF8StringEncoding/);
    assert.doesNotMatch(chunk,/dataUsingEncoding:/);
    storageChunks.push([output,between(actual,start,end)]);
}
console.log('Storage writeText source passed: root/helper/TrollStore byte counts without bridge-owned NSData, complete original writer/path/error/gate source retained.');
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.ok((await read(path)).includes('node scripts/check-file-handle-safety.mjs'));
const constructed=actualFileSource.replace('[[self alloc] init]','fileLifecycleConstruct(self)')
    .replaceAll('[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]','fileRepresentationDecode(data)')
    .replaceAll('[data base64EncodedStringWithOptions:0]','fileRepresentationEncode(data)')
    .replace('return storage.destination(used,count);','uint8_t *bytes=storage.destination(used,count); fileRawGrowWitness(bytes,count); return bytes;')
    .replace('auto owner=std::make_shared<TLinkJSFileReadStorage::Buffer>(std::move(storage));','auto owner=std::make_shared<TLinkJSFileReadStorage::Buffer>(std::move(storage)); fileReadOwnerWitness(owner);')
    .replace('NSData *data=factory(owner);','NSData *data=fileReadDataFactory(factory,owner);')
    .replace('    @autoreleasepool {\n    NSString *value = [[mode','    @autoreleasepool {\n    fileLifecycleNormalizationProbe();\n    NSString *value = [[mode')
    .replace('            NSString *value = [[whence','            fileLifecycleSeekNormalizationProbe();\n            NSString *value = [[whence');
const legacyLifecycle=frozen.replace('static NSString *TLinkJSFileNormalizeMode(NSString *mode)\n{','static NSString *TLinkJSFileNormalizeMode(NSString *mode)\n{\n    fileLifecycleNormalizationProbe();')
    .replace('        NSString *value = [[whence','        fileLifecycleSeekNormalizationProbe();\n        NSString *value = [[whence');
assert.notEqual(constructed,actualFileSource);
assert.equal((constructed.match(/fileLifecycleConstruct\(self\)/g)||[]).length,1);
assert.equal((constructed.match(/fileRepresentationDecode\(data\)/g)||[]).length,3);
assert.equal((constructed.match(/fileRepresentationEncode\(data\)/g)||[]).length,3);
assert.equal((constructed.match(/fileRawGrowWitness\(bytes,count\)/g)||[]).length,1);
assert.equal((constructed.match(/fileReadOwnerWitness\(owner\)/g)||[]).length,1);
assert.equal((constructed.match(/fileReadDataFactory\(factory,owner\)/g)||[]).length,1);
console.log('File raw read source passed: complete numeric/all/line storage replacement with bounded geometric capacity, no explicit zero-fill/trim/copy, immutable NSData ownership and complete preceding class reversal.');
console.log('File direct line source passed: retained chunk/rewind/error policy and mutable final result; preceding direct NSMutableData class restored.');
console.log('File explicit reads source passed: shared reader/line IO, legacy reply preservation, text-only/base64-only paths and complete previous class/header restoration.');
for(const fixture of [constructed,legacyLifecycle]){
    assert.equal((fixture.match(/fileLifecycleNormalizationProbe\(\)/g)||[]).length,1);
    assert.equal((fixture.match(/fileLifecycleSeekNormalizationProbe\(\)/g)||[]).length,1);
}
for(const [kind,spec] of Object.entries(storageOperationSpecs)){
    const actual=await read(spec.file);restoreStorageOperations(actual,kind,true);
    for(const part of spec.parts){
        storageChunks.push([`StorageOperations-${kind}-${part.name}.inc`,storageOperationPart(actual,part)]);
        storageChunks.push([`StorageOperationsBefore-${kind}-${part.name}.inc`,storageOperationBefore(part)]);
    }
}
for(const kind of ['root','helper']){
    const spec=storageJSONWriteSpecs[kind],actual=await read(spec.file);restoreStorageJSONWrites(actual,kind);
    const current=storageOperationPart(actual,spec),before=storageJSONWriteBefore(kind);
    assert.equal(current.replace('[[TLinkPreparedJSONText alloc] initWithJSONData:data]','[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]'),before,'only the prepared string constructor changes; recursive request/authority/count/error source retained');
    storageChunks.push([`StorageJSONWriteBefore-${kind}.inc`,before]);
}
console.log('Storage JSON write source passed: immutable encoded bytes with NSString-compatible arguments, original recursive gates/path/error/count source, and complete preceding root/helper files.');
console.log('Storage operation source passed: twelve scoped routes, root parse/preparation boundaries, child NSError outside pools and exact preceding root/helper/TrollStore sources.');
for(const kind of ['root','helper','troll']){
    const spec=filePlanSpecs[kind],actual=await read(spec.file);restoreFilePlanFrontend(actual,kind,true);
    const start=actual.indexOf(spec.start),end=actual.indexOf(spec.end,start+spec.start.length);
    const current=actual.slice(start,end);
    storageChunks.push([`FilePlan-${kind}.inc`,current]);
    storageChunks.push([`FilePlanBefore-${kind}.inc`,await read('test/fixtures/file-plan-'+kind+'-before-c03al.inc')]);
    assert.equal((current.match(/TLinkJSFilePrepareMode\(openMode\)/g)||[]).length,1);
    assert.equal((current.match(/preparedMode:modePlan/g)||[]).length,1);
}
const bindings=beforeRepresentation.slice(beforeRepresentation.indexOf('JSValue *TLinkJSFileHandleCreateJSObject('));
assert.equal((bindings.match(/@autoreleasepool/g)||[]).length,10);
for(const [label,text] of [['Current',bindings],['Before',await read('test/fixtures/file-plan-bindings-before-c03al.inc')]]){
    const measured=text.replace('TLinkJSFileHandleCreateJSObject(',`Fixture${label}FileBindings(`).replace('[JSValue valueWithNewObjectInContext:context]','FixtureFileBindingObject(context)');
    assert.equal((measured.match(/FixtureFileBindingObject\(context\)/g)||[]).length,1);
    storageChunks.push([`FilePlanBindings-${label}.inc`,measured]);
}
const constants=[];
for(const kind of ['root','helper','troll']){
    const text=await read(filePlanSpecs[kind].file);
    const names=kind==='root'?['kTLinkautoJSMaxOpenFiles','kTLinkautoJSMaxStorageFileBytes']:kind==='helper'?['kTLinkJSHelperMaxOpenFiles','kTLinkJSHelperMaxStorageFileBytes']:['kTLinkScriptMaxOpenFiles','kTLinkScriptMaxFileTransferBytes'];
    for(const name of names){const line=text.match(new RegExp('^static const [^\\n]+ '+name+' = [^\\n]+;','m'));assert.ok(line,name);constants.push(line[0]);}
}
storageChunks.push(['FilePlanConstants.inc',constants.join('\n')+'\n']);
console.log('File mode/binding source passed: one owned prepared mode across three frontends, shared physical-open owner/error policy and nine callback/creation pools; complete previous class/header/frontends retained.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-file-handle-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'file-line.exe':'file-line'),file=join(root,'test/file-handle-line-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);
    run(binary,[]);
    const names=['TLinkJSFileHandleCreateJSObject','TLinkJSFileModeIsValid','TLinkJSFileModeWrites','TLinkJSFileHandle'];
    const legacyHeader=header.replace(new RegExp(`\\b(${names.join('|')})\\b`,'g'),name=>`Legacy${name}`);
    assert.ok(legacyHeader.includes('@interface LegacyTLinkJSFileHandle : NSObject')&&legacyHeader.includes('JSValue *LegacyTLinkJSFileHandleCreateJSObject('));
    assert.doesNotMatch(legacyHeader,/LegacyLegacy/,'rename each complete legacy symbol once');
    await writeFile(join(temp,'LegacyFileHandle.h'),legacyHeader);
    const previousNames=['TLinkJSFileHandleCreateJSObject','TLinkJSFileHandle','TLinkJSFileModeIsValid','TLinkJSFileModeWrites','TLinkJSFileNormalizeMode','TLinkJSFileNormalizedModeIsValid','TLinkJSFileError','TLinkJSFileDataResult','TLinkJSFileSelectedDataResult','TLinkJSFileRepresentation'];
    const previousRename=text=>text.replace(new RegExp(`\\b(${previousNames.join('|')})\\b`,'g'),name=>'Previous'+name);
    const prepareStart=beforeLineFill.indexOf('// BEGIN prepared file mode.'),prepareEnd=beforeLineFill.indexOf('static NSDictionary *TLinkJSFileError(',prepareStart);
    assert.ok(prepareStart>=0&&prepareEnd>prepareStart);
    const previousClass=previousRename((beforeLineFill.slice(0,prepareStart)+beforeLineFill.slice(prepareEnd)).replace('#import "TLinkJSFileHandle.h"','#import "PreviousFileHandle.h"'));
    assert.equal((previousClass.match(/@implementation PreviousTLinkJSFileHandle/g)||[]).length,1);
    assert.doesNotMatch(previousClass,/TLinkJSFilePrepareMode\(NSString \*mode\)/,'reuse the unchanged shared mode factory instead of redefining its private friend');
    await writeFile(join(temp,'PreviousFileHandle.h'),previousRename(currentHeader));
    await writeFile(join(temp,'PreviousLineFileHandle.inc'),previousClass);
    const storageNames=[...previousNames,'TLinkJSFileLineDataResult'];
    const storageRename=text=>text.replace(new RegExp(`\\b(${storageNames.join('|')})\\b`,'g'),name=>'BeforeReadStorage'+name);
    const oldStorageClass=storageRename(beforeReadStorage.replace(beforeReadStorage.slice(beforeReadStorage.indexOf('// BEGIN prepared file mode.'),beforeReadStorage.indexOf('static NSDictionary *TLinkJSFileError(')),'')
        .replace('#import "TLinkJSFileHandle.h"','#import "BeforeReadStorageFileHandle.h"'));
    assert.equal((oldStorageClass.match(/@implementation BeforeReadStorageTLinkJSFileHandle/g)||[]).length,1);
    assert.doesNotMatch(oldStorageClass,/TLinkJSFilePrepareMode\(NSString \*mode\)/);
    await writeFile(join(temp,'BeforeReadStorageFileHandle.h'),storageRename(currentHeader));
    await writeFile(join(temp,'BeforeReadStorageFileHandle.inc'),oldStorageClass);
    await Promise.all(storageChunks.map(([name,chunk])=>writeFile(join(temp,name),chunk)));
    await writeFile(join(temp,'FileHandleLifecycleUnderTest.inc'),constructed);
    await writeFile(join(temp,'LegacyFileHandleLifecycle.inc'),legacyLifecycle);
    // Resolve native fixture dependencies on every host, even when Apple
    // compilation is unavailable. Symbol renaming must not rename filenames.
    for(const name of ['LegacyFileHandle.h','PreviousFileHandle.h','BeforeReadStorageFileHandle.h',
        'FileHandleLifecycleUnderTest.inc','LegacyFileHandleLifecycle.inc','PreviousLineFileHandle.inc','BeforeReadStorageFileHandle.inc']){
        const text=await readFile(join(temp,name),'utf8');
        for(const [,dependency] of text.matchAll(/^#(?:import|include)\s+"([^"]+)"/gm)){
            const candidates=[join(temp,dependency),join(root,'shared',dependency)];
            const found=await Promise.allSettled(candidates.map(path=>access(path)));
            assert.ok(found.some(result=>result.status==='fulfilled'),`${name}: missing quoted dependency "${dependency}"`);
        }
    }
    console.log('FileHandle fixture dependencies passed: current and three historical classes/headers resolve before native compilation.');
    if(process.platform==='darwin'){
        const runtime=join(temp,'file-handle-runtime');
        const owner=join(temp,'pool-owner.o');
        run(compiler,['-x','objective-c','-Wall','-Wextra','-Werror','-fno-objc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-c',join(root,'test/ax-node-pool-owner.m'),'-o',owner]);
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/file-handle-runtime-test.mm'),owner,'-o',runtime]);
        run(runtime,[temp]);
        const storageRuntime=join(temp,'storage-codec-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/storage-codec-runtime-test.mm'),'-o',storageRuntime]);
        run(storageRuntime,[temp]);
        const jsonRuntime=join(temp,'storage-json-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/storage-json-runtime-test.mm'),owner,'-o',jsonRuntime]);
        run(jsonRuntime,[temp]);
    }else console.log('macOS actual/frozen FileHandle Foundation/POSIX/JSCore integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-file-handle-'));await rm(temp,{recursive:true,force:true});}
