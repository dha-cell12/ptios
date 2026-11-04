import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {axSnapshot,legacyAXSnapshot,restoreAXSnapshot} from './lib/ax-snapshot-baseline.mjs';
import {axAttributes,legacyAXAttributes,restoreAXAttributes} from './lib/ax-attributes-baseline.mjs';
import {axScanLimits,legacyAXScan} from './lib/ax-scan-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkAccessibilityTree.mm');restoreAXSnapshot(source);
const preceding=restoreAXAttributes(source);
const actual=axSnapshot(source);assert.doesNotMatch(actual,/CFAbsoluteTimeGetCurrent|NSDate \*deadline/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-ax-snapshot-safety\.mjs/);
const adapt=s=>s.replaceAll('TLinkNativeNowNs()','fixtureNow()').replaceAll('CFAbsoluteTimeGetCurrent()','fixtureWall()')
    .replaceAll('[[NSDate date] timeIntervalSince1970]','fixtureEpoch()').replaceAll('[UIScreen mainScreen]','[FixtureScreen mainScreen]')
    .replaceAll('CFRelease(','fixtureRelease(');
const complete=source.slice(source.indexOf('BOOL TLinkAXResultCompleteForAction('),source.indexOf('NSDictionary *TLinkAXElementAtPoint('));
const fixtures={'AXSnapshotUnderTest.inc':adapt(actual),'AXSnapshotLegacy.inc':adapt(legacyAXSnapshot).replaceAll('TLinkAXCopySnapshotUnlocked','LegacyAXCopySnapshotUnlocked'),
    'AXScanLimitsUnderTest.inc':axScanLimits,
    'AXSnapshotBeforeScan.inc':adapt(legacyAXScan).replaceAll('TLinkAXCopySnapshotUnlocked','PreScanAXCopySnapshotUnlocked'),
    'AXFindUnderTest.inc':source.slice(source.indexOf('static BOOL TLinkAXTextMatches('),source.indexOf('BOOL TLinkAXResultCompleteForAction(')),
    'AXAttributesUnderTest.inc':adapt(axAttributes(source)),
    'AXAttributesLegacy.inc':adapt(legacyAXAttributes),
    'AXSnapshotBeforeAttributes.inc':adapt(axSnapshot(preceding)).replaceAll('TLinkAXCopySnapshotUnlocked','PrecedingAXCopySnapshotUnlocked'),
    'AXCompletenessUnderTest.inc':complete,
    'AXErrorUnderTest.inc':source.slice(source.indexOf('static NSDictionary *TLinkAXError('),source.indexOf('NSDictionary *TLinkAXCapabilitySnapshot(void)')),
    'AXBoundedIntegerUnderTest.inc':source.slice(source.indexOf('static NSInteger TLinkAXBoundedInteger('),source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('))};
console.log('AX snapshot source passed: independent scanned-node cap/selector forwarding, monotonic attribute gates/CF cleanup, late completeness refusal and complete preceding AX geometry/foreground contract.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ax-snapshot-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/ax-snapshot-window-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-snapshot-runtime-test.mm'),'-o',native]);run(native,[]);
        const attributes=join(temp,'attributes');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-attribute-runtime-test.mm'),'-o',attributes]);run(attributes,[]);
    }else console.log('macOS actual/frozen AX snapshot Foundation/CF/ARC/sanitizer fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ax-snapshot-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
