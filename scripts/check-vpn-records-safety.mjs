import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {vpnRecords,legacyVPNRecords,restoreVPNRecords} from './lib/vpn-records-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkVPNManager.mm');restoreVPNRecords(source);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-vpn-records-safety\.mjs/);
const adapt=s=>s.replaceAll('[existing[@"identifier"] isEqualToString:identifier]','fixtureDuplicateEqual(existing[@"identifier"],identifier)')
    .replaceAll('[knownIdentifiers containsObject:identifier]','fixtureSeenContains(knownIdentifiers,identifier)');
const fixtures={
    'VPNIdentifierUnderTest.inc':source.slice(source.indexOf('static NSString *TLinkVPNPrivateIdentifierString('),source.indexOf('static id TLinkVPNPrivateStore(')),
    'VPNRecordsUnderTest.inc':adapt(vpnRecords(source)),
    'VPNRecordsLegacy.inc':adapt(legacyVPNRecords).replaceAll('TLinkVPNPrivateConfigurationRecords','LegacyPrivateConfigurationRecords'),
};
console.log('VPN records source passed: per-call immutable membership index, aliased mutable fallback, primary duplicates/order and complete preceding manager source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vpn-records-'));
try{
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const binary=join(temp,'runtime'),compiler=process.env.CXX||'clang++';
        function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/vpn-records-runtime-test.mm'),'-o',binary]);run(binary,[]);
    }else console.log('macOS actual/frozen VPN records Foundation/ARC/sanitizer runtime included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vpn-records-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
