import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {privateTransition,privatePollingAdapter,legacyPrivateTransition,restoreVPNPrivatePolling} from './lib/vpn-private-polling-baseline.mjs';
import {privateConfigure,privateVerificationAdapter,privateVerificationLoop,legacyPrivateConfigure} from './lib/vpn-private-verification-baseline.mjs';
import {privateCleanup,privateCleanupAdapter,legacyPrivateCleanup} from './lib/vpn-private-cleanup-baseline.mjs';
import {legacyVerificationSnapshot} from './lib/vpn-verification-snapshot-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkVPNManager.mm');restoreVPNPrivatePolling(source);
const current=privatePollingAdapter(source)+privateTransition(source);
assert.doesNotMatch(current,/NSDate|timeIntervalSinceReferenceDate|__block/);
assert.match(current,/Window window\(TLinkHelperIO::nowMs\(\), timeout\)/);
assert.match(current,/@autoreleasepool[\s\S]*if \(!window.remaining\(TLinkHelperIO::nowMs\(\)\)\) break;/);
assert.ok(current.indexOf('Window window(')<current.indexOf('objc_msgSend)(connection, action)'));
assert.match(current,/usleep\(milliseconds \* 1000U\) == 0 \|\| errno == EINTR/);
const verification=privateVerificationAdapter(source)+privateConfigure(source),loop=privateVerificationLoop(source);
assert.match(loop,/maximumVerificationAttempts = 50/);
assert.match(loop,/Window verificationWindow\(TLinkHelperIO::nowMs\(\), 5.0\)/);
assert.match(loop,/@autoreleasepool/);assert.doesNotMatch(loop,/NSMutableArray|delta addObject|NSDate|usleep/);
assert.match(loop,/if \(deltaCount == 1\)/);
assert.match(loop,/if \(!verificationWindow.remaining\(TLinkHelperIO::nowMs\(\)\)\) \{\s*newRecord = nil;/);
assert.match(verification,/milliseconds \/ 1000.0/);
const cleanup=privateCleanupAdapter(source)+privateCleanup(source);
assert.doesNotMatch(cleanup,/timeIntervalSinceReferenceDate/);
assert.match(cleanup,/if \(!window.remaining\(TLinkHelperIO::nowMs\(\)\)\) break;[\s\S]*disconnectedInTime = true;/);
assert.match(cleanup,/if \(!disconnectedInTime\) \{[\s\S]*vpn_private_cleanup_disconnect_timeout/);
const adaptVerification=s=>s.replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replaceAll('usleep(','fixtureSleep(')
    .replaceAll('[[NSUUID UUID] UUIDString]','fixtureUUID()');
for(const path of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(path),/node scripts\/check-vpn-private-polling-safety\.mjs/);
const fixtures={
    'PrivateVPNTransitionUnderTest.inc':current.replaceAll('TLinkHelperIO::nowMs()','fixtureNow()').replaceAll('usleep(','fixtureSleep('),
    'PrivateVPNTransitionLegacy.inc':legacyPrivateTransition.replaceAll('TLinkVPNPrivateSetConnectedSync','LegacyPrivateSetConnectedSync')
        .replaceAll('[NSDate timeIntervalSinceReferenceDate]','fixtureWallNow()').replaceAll('usleep(','fixtureSleep('),
    'PrivateVPNVerificationUnderTest.inc':adaptVerification(verification),
    'PrivateVPNVerificationLegacy.inc':adaptVerification(legacyPrivateConfigure.replaceAll('TLinkVPNPrivateConfigureLegacySync','LegacyPrivateConfigureSync')),
    'PrivateVPNVerificationSnapshotLegacy.inc':adaptVerification(legacyVerificationSnapshot.replaceAll('TLinkVPNPrivateConfigureLegacySync','LegacySnapshotConfigureSync')),
    'PrivateVPNStatusFields.inc':source.slice(source.indexOf('static NSDictionary *TLinkVPNPrivateStatusFields('),source.indexOf('static NSDictionary *TLinkVPNPrivateReadStatusSync(')),
    'PrivateVPNCleanupUnderTest.inc':adaptVerification(cleanup),
    'PrivateVPNCleanupLegacy.inc':adaptVerification(legacyPrivateCleanup.replaceAll('TLinkVPNPrivateRemoveOwnedProfileSync','LegacyPrivateRemoveOwnedProfileSync')),
};
assert.ok(!fixtures['PrivateVPNTransitionUnderTest.inc'].includes('TLinkHelperIO::nowMs()'));
console.log('Private VPN polling source passed: continuous transition/creation-verification windows, scoped initial snapshot/count, unique candidate parity without delta array, main-run-loop wait, scoped probe pools and complete previous manager source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-private-poll-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'core.exe':'core'),file=join(root,'test/vpn-private-polling-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform!=='darwin')console.log('macOS actual/frozen private transition Foundation/ARC/sanitizer runtime included in CI; not run on this host.');
    else{
        const native=join(temp,'runtime');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-private-polling-runtime-test.mm'),'-o',native]);run(native,[]);
        const verify=join(temp,'verification');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-private-verification-runtime-test.mm'),'-o',verify]);run(verify,[]);
    }
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-private-poll-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
