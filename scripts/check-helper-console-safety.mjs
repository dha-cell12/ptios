import {restoreHelperConsole,helperConsoleSpecs,helperConsoleBeforeHook,helperConsoleBeforeWriter} from './lib/helper-console-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const source=await read(helperConsoleSpecs.file);restoreHelperConsole(source);
const moduleSource=await read('shared/TLinkHelperConsoleLog.inc');
assert.match(moduleSource,/TLinkConsoleLogPrefix[\s\S]*substringToIndex:count[\s\S]*copy/);
assert.equal((moduleSource.match(/dataUsingEncoding:/g)||[]).length,1);
assert.equal((moduleSource.match(/appendPreparedConsoleData:line.data/g)||[]).length,2);
const prepared=helperConsoleSpecs.writer.replaceAll('NSFileHandle *handle','HelperOwnedHandle *handle')
    .replace('[NSFileHandle fileHandleForWritingAtPath:path]','HelperOpen(path)')
    .replace('    NSDictionary *attrs=', '    HelperObserve(data,path);\n    NSDictionary *attrs=');
assert.equal((prepared.match(/HelperObserve\(data,path\)/g)||[]).length,1);
const before=helperConsoleBeforeWriter.replaceAll('NSFileHandle *handle','HelperOwnedHandle *handle')
    .replace('[NSFileHandle fileHandleForWritingAtPath:path]','HelperOpen(path)').replace('[line dataUsingEncoding:NSUTF8StringEncoding]','HelperEncode(line)');
const measured=moduleSource.replace('[NSDate date]','HelperDate()').replace('[line dataUsingEncoding:NSUTF8StringEncoding]','HelperEncode(line)').replace('NSLog(','HelperSystem(');
for(const name of ['HelperDate()','HelperEncode(line)','HelperSystem('])assert.equal(measured.split(name).length,2);
const hook=(body,name)=>`static void ${name}(JSContext *ctx,id owner,NSString *runId,NSString *logPath,NSString *latestPath){\n__weak id weakSelf=owner;\n${body}}\n`;
const beforeHook=helperConsoleBeforeHook.replace('[NSDate date]','HelperDate()').replace('NSLog(','HelperSystem(');
assert.equal(beforeHook.split('HelperDate()').length,2);assert.equal(beforeHook.split('HelperSystem(').length,2);
console.log('Helper console source passed: complete preceding helper source/callback/writer, owned bounded UTF16 snapshots, one encoded payload for both paths and independent sink exceptions.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-console-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    await Promise.all([writeFile(join(temp,'HelperConsoleUnderTest.inc'),measured),writeFile(join(temp,'HelperConsoleWriter.inc'),prepared),writeFile(join(temp,'HelperConsoleBeforeWriter.inc'),before),
        writeFile(join(temp,'HelperConsoleHooks.inc'),hook(beforeHook,'InstallBefore')+hook(helperConsoleSpecs.hook,'InstallCurrent'))]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','JavaScriptCore','-I',temp,'-I',join(root,'shared'),join(root,'test/helper-console-runtime-test.mm'),'-o',native]);run(native,[temp]);
    }else console.log('macOS actual/frozen helper console Foundation/POSIX/JSCore/ARC/sanitizer runtime included in CI; not executed here.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-console-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
