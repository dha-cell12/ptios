import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const source=await read('pccontrol/jsruntime/TLinkJSRuntimeCore.mm');
const between=(text,a,b)=>{const x=text.indexOf(a),y=text.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return text.slice(x,y);};
const methods=between(source,'- (void)prepareConsoleLogFiles {','- (NSDictionary *)bundleTextForRelativePath:');
const append=methods.slice(methods.indexOf('- (void)appendConsoleLogWithLevel:'));
assert.match(append,/TLinkConsoleLogPermit::acquire[\s\S]*TLinkConsoleLogPrefix[\s\S]*dataUsingEncoding:NSUTF8StringEncoding[\s\S]*data.length>TLinkConsoleLogLineBytes[\s\S]*generation!=_logGeneration[\s\S]*dispatch_async[\s\S]*@finally \{permit->finish\(\);\}/);
assert.match(append,/@finally \{os_unfair_lock_unlock\(&_logStateLock\);\}/);
assert.match(append,/@autoreleasepool[\s\S]*TLinkConsoleLogPermit::acquire/,'drain temporary formatter objects on the caller as well as the worker');
assert.doesNotMatch(append,/dispatch_sync|appendLine:|NSLog/);
assert.equal([...append.matchAll(/dataUsingEncoding/g)].length,1,'encode once before publishing to both files');
assert.match(methods,/_acceptingLogs=NO;[\s\S]*dispatch_sync\(_logQueue[\s\S]*console logger lifetime totals/);
assert.match(source,/\[self prepareConsoleLogFiles\];\s*\[self beginConsoleLogging\];/);
assert.match(source,/\[self finishConsoleLogging\];\s*_running = NO;/);
assert.match(source,/NSLog\(@"com.tlinkauto.jsruntime\[%@\]\[%@\]: %@"[\s\S]*appendConsoleLogWithLevel:level message:message/);
assert.ok((await read('pccontrol/jsruntime/TLinkJSRuntimeCore.h')).includes('- (NSDictionary *)currentConsoleLogStats;'));
const frozenText=await read('test/fixtures/console-log-legacy-v1.inc'),frozen=frozenText.slice(frozenText.indexOf('\n')+1);
const prepare=between(methods,'- (void)prepareConsoleLogFiles {','- (BOOL)appendConsoleData:');
assert.equal(prepare.replace('    _consoleLogPath = nil;\n    _consoleLatestLogPath = nil;\n','').trim(),between(frozen,'- (void)prepareConsoleLogFiles {','- (void)appendLine:').trim());
let writer=between(frozen,'- (void)appendLine:','- (void)appendConsoleLogWithLevel:');
writer=writer.replace('- (void)appendLine:(NSString *)line','- (BOOL)appendConsoleData:(NSData *)data').replace('![line isKindOfClass:[NSString class]]','![data isKindOfClass:[NSData class]]').replace('        return;','        return NO;').replace('    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];\n    if (!data) return;\n\n','').replace('        [data writeToFile:path atomically:YES];\n        return;','        return [data writeToFile:path atomically:YES];').replace('    if (!handle) return;','    if (!handle) return NO;').replace(/\n}\s*$/,'\n    return YES;\n}\n');
assert.equal(between(methods,'- (BOOL)appendConsoleData:','- (BOOL)writeConsoleData:').trim(),writer.trim(),'file size/rotation/append/close policy remains unchanged apart from returned status and shared encoded input');
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.ok((await read(path)).includes('node scripts/check-console-log-safety.mjs'));
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-console-log-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await writeFile(join(temp,'ConsoleLogMethods.inc'),methods);
    const helper=between(source,'static NSString *TLinkautoJSSanitizeFileComponent','@interface TLinkJSRuntimeCore');
    await writeFile(join(temp,'ConsoleLogHelpers.inc'),helper);
    const constant=source.match(/^static const unsigned long long kTLinkautoJSMaxConsoleLogBytes = 512 \* 1024;$/m);assert.ok(constant);
    await writeFile(join(temp,'ConsoleLogConstants.h'),constant[0]);
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'console-log.exe':'console-log'),file=join(root,'test/console-log-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-pthread','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const runtime=join(temp,'console-log-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/console-log-runtime-test.mm'),'-o',runtime]);
        run(runtime,[temp]);
    }else console.log('macOS actual/frozen console formatter/queue/file/lifecycle integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-console-log-'));await rm(temp,{recursive:true,force:true});}
