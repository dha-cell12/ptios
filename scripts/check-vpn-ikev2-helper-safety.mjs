import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {ikev2Sync,legacyIKEv2Sync,restoreIKEv2Sync} from './lib/vpn-ikev2-sync-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkVPNManager.mm');restoreIKEv2Sync(source);
const actual=ikev2Sync(source);
assert.doesNotMatch(actual,/__block|timeIntervalSinceNow\]|NSDate \*deadline/);
assert.match(actual,/finishChecked\([\s\S]*window.remaining/);
assert.match(actual,/if \(!ran && !state->ready\(\) && remaining > 0\) state->wait\(remaining\)/);
assert.ok(actual.indexOf('Window window(')<actual.indexOf('    TLinkVPNConfigureIKEv2('));
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-vpn-ikev2-helper-safety\.mjs/);
const adapt=s=>s.replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replaceAll('geteuid()','fixtureUID()').replaceAll('getegid()','fixtureGID()');
const fixtures={
    'IKEv2SyncUnderTest.inc':adapt(actual).replaceAll('TLinkVPNConfigureIKEv2SynchronouslyForHelper','CurrentSyncIKEv2').replaceAll('std::make_shared<TLinkVPNBrokerCompletion>()','std::make_shared<FixtureCompletion>()'),
    'IKEv2SyncLegacy.inc':adapt(legacyIKEv2Sync).replaceAll('TLinkVPNConfigureIKEv2SynchronouslyForHelper','LegacySyncIKEv2'),
};
console.log('IKEv2 helper source passed: first-result synchronized completion, continuous pre-starter window, main-loop/empty-mode/off-main waits and complete preceding manager/result contract.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ikev2-sync-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/vpn-broker-budget-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-ikev2-helper-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen IKEv2 helper Foundation/GCD/ARC/sanitizer runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ikev2-sync-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
