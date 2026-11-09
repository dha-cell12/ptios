import {consoleRetentionSpecs,restoreConsoleRetention} from './lib/console-retention-baseline.mjs';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
for(const [kind,spec] of Object.entries(consoleRetentionSpecs))restoreConsoleRetention(await read(spec.file),kind);
const core=await read(consoleRetentionSpecs.core.file),helper=await read(consoleRetentionSpecs.helper.file);
assert.match(core,/\[self finishConsoleLogging\];\s*\/\/[^\n]*\n\s*TLinkConsoleLogRetention::Complete\(_consoleLogPath.fileSystemRepresentation\)/);
assert.match(helper,/\[header writeToFile:latestPath[^\n]*\n(?:\s*\/\/[^\n]*\n){2}\s*TLinkConsoleLogRetention::Completion completedLog\(logPath.fileSystemRepresentation\)/);
const policy=await read('shared/TLinkConsoleLogRetention.h');
assert.doesNotMatch(policy,/removeItemAtPath|rmdir\(|system\(/);
console.log('Console retention source passed: complete prior root/helper sources, root completion after drain and helper scope after headers; no logger/wire/authority source changed.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-console-retention-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed signal=${r.signal}`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/console-retention-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',file,'-o',binary]);run(binary,[]);
    if(process.platform==='darwin'){
        const native=join(temp,'posix');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',join(root,'test/console-retention-runtime-test.cpp'),'-o',native]);run(native,[temp]);
    }else console.log('macOS console retention POSIX/xattr/flock/process/unwind runtime included in CI; not executed here.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-console-retention-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
