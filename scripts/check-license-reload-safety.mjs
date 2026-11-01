import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {rootReload,restoreLicenseReload} from './lib/license-reload-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/LicenseLifecycleCoordinator.mm');restoreLicenseReload(source);
const entry=rootReload(source);
assert.match(entry,/htons\(6000\)/);assert.match(entry,/"127.0.0.1"/);
assert.doesNotMatch(entry,/SO_RCVTIMEO|SO_SNDTIMEO|\brecv\(|\bsend\(/);
assert.ok(entry.indexOf('ReloadIO::window(')<entry.indexOf('socket(AF_INET'));
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-license-reload-safety.mjs/);
const start=entry.indexOf('    connectOps.begin ='),end=entry.indexOf('    auto reply',start);assert.ok(start>=0&&end>start);
const fixture=entry.slice(0,start)+'    connectOps = fixture.connectOps();\n'+entry.slice(end);
const adapted=fixture.replaceAll('TLinkHelperIO::posixOps()','fixtureOps()').replaceAll('TLinkHelperIO::Socket descriptor','FixtureSocket descriptor')
    .replace('socket(AF_INET, SOCK_STREAM, 0)','fixtureSocket(AF_INET, SOCK_STREAM, 0)');
console.log('License reload source passed: bounded root 6000 endpoint, shared window, scoped socket and complete prior coordinator/TrollStore/retry source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-license-reload-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/license-reload-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await writeFile(join(temp,'LicenseReloadUnderTest.inc'),adapted);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/license-reload-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS reload Foundation/POSIX/ARC/sanitizer runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-license-reload-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
