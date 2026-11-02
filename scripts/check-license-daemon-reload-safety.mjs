import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {legacyLicensePublish,reloadProperties,reloadMethods,licensePublish,restoreReloadCoalescing} from './lib/license-reload-coalescing-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('stream-app/app/LicenseLifecycleCoordinator.mm');restoreReloadCoalescing(source);
const methods=reloadMethods(source);
assert.match(methods,/if \(self.daemonReloadIdentity\) \{\s*self.daemonReloadPending = YES;\s*return;/);
assert.match(methods,/if \(self.daemonReloadPending\) retry = NO;/);
assert.match(methods,/if \(!pending && \(success \|\| retry\)\)/);
assert.equal((methods.match(/SCLicenseRequestDaemonReload\(\)/g)||[]).length,1);
assert.match(methods,/1\.0 \* NSEC_PER_SEC/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-license-daemon-reload-safety\.mjs/);
const adapt=s=>s.replaceAll('dispatch_async(','fixtureAsync(self,').replaceAll('dispatch_after(','fixtureAfter(self,')
    .replaceAll('SCLicenseRequestDaemonReload()','[self transport]').replaceAll('TLinkLicenseInvalidateCache()','[self invalidateCache]');
const initialization='        _daemonReloadQueue = dispatch_queue_create("com.tlinkauto.license-daemon-reload", DISPATCH_QUEUE_SERIAL);\n';
assert.equal(source.split(initialization).length,2);
console.log('License daemon reload source passed: admission before enqueue, one serial attempt/pending bit, fresh retry promotion, exception retirement and complete per-publication/prior coordinator source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-license-daemon-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await Promise.all([writeFile(join(temp,'DaemonReloadUnderTest.inc'),adapt(methods+licensePublish(source))),writeFile(join(temp,'DaemonReloadLegacy.inc'),adapt(legacyLicensePublish)),
        writeFile(join(temp,'DaemonReloadProperties.inc'),reloadProperties(source)),writeFile(join(temp,'DaemonReloadInit.inc'),initialization)]);
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(process.env.CXX||'clang++',['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/license-daemon-reload-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen reload Foundation/GCD/ARC/sanitizer parity, burst/race/retry/exception fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-license-daemon-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
