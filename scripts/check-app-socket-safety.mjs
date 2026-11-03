import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {appTaskRequest,legacyAppSocket,restoreAppSocket} from './lib/app-socket-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/TLinkSocketClient.mm');restoreAppSocket(source);
assert.doesNotMatch(source,/SO_RCVTIMEO|SO_SNDTIMEO|connectSocketWithTimeout|\brecv\(|\bsend\(/);
const entry=appTaskRequest(source);assert.match(entry,/htons\(6000\)/);assert.match(entry,/"127.0.0.1"/);
assert.ok(entry.indexOf('TaskIO::window(')<entry.indexOf('socket(AF_INET'));
assert.match(source,/TLinkAppTaskRequest\(line, 2\.0, NO\)/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-app-socket-safety\.mjs/);
const start=entry.indexOf('    connectOps.begin ='),end=entry.indexOf('    auto reply',start);assert.ok(start>=0&&end>start);
const fixture=source.slice(source.indexOf('// BEGIN bounded app task request.')).replace(entry,entry.slice(0,start)+'    connectOps = fixture.connectOps();\n'+entry.slice(end));
const adapted=fixture.replaceAll('TLinkHelperIO::posixOps()','fixtureOps()').replaceAll('TLinkHelperIO::Socket descriptor','FixtureSocket descriptor').replace('socket(AF_INET, SOCK_STREAM, 0)','fixtureSocket(AF_INET, SOCK_STREAM, 0)');
console.log('App socket source passed: one continuous transaction, exact write/send-only path, scoped descriptors, existing endpoint/API/task codec and complete frozen class contract.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-app-socket-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/app-socket-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all([writeFile(join(temp,'AppSocketUnderTest.inc'),adapted),writeFile(join(temp,'AppSocketLegacy.inc'),legacyAppSocket.slice(legacyAppSocket.indexOf('@implementation')).replaceAll('TLinkSocketClient','LegacySocketClient')),
        writeFile(join(temp,'LegacySocketClient.h'),(await read('stream-app/app/TLinkSocketClient.h')).replaceAll('TLinkSocketClient','LegacySocketClient'))]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/app-socket-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS complete actual/frozen app client Foundation/POSIX/ARC/sanitizer parity/fault/runtime fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-app-socket-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
