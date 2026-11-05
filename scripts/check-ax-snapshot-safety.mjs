import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {axSnapshot,legacyAXSnapshot,restoreAXSnapshot} from './lib/ax-snapshot-baseline.mjs';
import {axAttributes,legacyAXAttributes,restoreAXAttributes} from './lib/ax-attributes-baseline.mjs';
import {axScanLimits,legacyAXScan} from './lib/ax-scan-baseline.mjs';
import {axFind,legacyAXFind} from './lib/ax-find-baseline.mjs';
import {legacyAXNodePool} from './lib/ax-node-pool-baseline.mjs';
import {axHitTest,legacyAXHitTest} from './lib/ax-hit-test-baseline.mjs';
import {legacyAXParentAttributes} from './lib/ax-parent-attributes-baseline.mjs';
import {legacyAXSnapshotOwner} from './lib/ax-snapshot-owner-baseline.mjs';
import {axQueryRegion,legacyAXQueryStop} from './lib/ax-query-stop-baseline.mjs';
import {axAdmissionState} from './lib/ax-admission-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkAccessibilityTree.mm');restoreAXSnapshot(source);
const preceding=restoreAXAttributes(source);
const actual=axSnapshot(source);assert.doesNotMatch(actual,/CFAbsoluteTimeGetCurrent|NSDate \*deadline/);
assert.doesNotMatch(axFind(source),/NSMutableArray|matches\b/);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-ax-snapshot-safety\.mjs/);
const adapt=s=>s.replaceAll('TLinkNativeNowNs()','fixtureNow()').replaceAll('CFAbsoluteTimeGetCurrent()','fixtureWall()')
    .replaceAll('[[NSDate date] timeIntervalSince1970]','fixtureEpoch()').replaceAll('[UIScreen mainScreen]','[FixtureScreen mainScreen]')
    .replaceAll('CFRelease(','fixtureRelease(');
const complete=source.slice(source.indexOf('BOOL TLinkAXResultCompleteForAction('),source.indexOf('NSDictionary *TLinkAXElementAtPoint('));
const query=axQueryRegion(source),snapshotWrapper=query.slice(0,query.indexOf('static BOOL TLinkAXTextMatches('));
const oldSnapshotWrapper=legacyAXQueryStop.slice(0,legacyAXQueryStop.indexOf('static BOOL TLinkAXTextMatches('));
const oldFind=legacyAXQueryStop.slice(legacyAXQueryStop.indexOf('static BOOL TLinkAXTextMatches('));
const fixtures={'AXSnapshotUnderTest.inc':adapt(actual),'AXSnapshotLegacy.inc':adapt(legacyAXSnapshot).replaceAll('TLinkAXCopySnapshotUnlocked','LegacyAXCopySnapshotUnlocked'),
    'AXAdmissionUnderTest.inc':axAdmissionState,
    'AXSnapshotWrapperUnderTest.inc':snapshotWrapper,
    'AXSnapshotWrapperBeforeStop.inc':oldSnapshotWrapper.replace('NSDictionary *TLinkAXCopySnapshot(','NSDictionary *BeforeStopAXCopySnapshot('),
    'AXFindBeforeStop.inc':oldFind.replaceAll('TLinkAXTextMatches','BeforeStopAXTextMatches').replaceAll('TLinkAXFindInSnapshot','BeforeStopAXFindInSnapshot').replaceAll('TLinkAXFindElement','BeforeStopAXFindElement'),
    'AXHitTestUnderTest.inc':adapt(axHitTest(source)),
    'AXHitTestLegacy.inc':adapt(legacyAXHitTest).replaceAll('TLinkAXElementAtPoint','PrecedingAXElementAtPoint'),
    'AXSnapshotBeforeNodePool.inc':adapt(legacyAXNodePool).replaceAll('TLinkAXCopySnapshotUnlocked','PrePoolAXCopySnapshotUnlocked'),
    'AXSnapshotBeforeOwner.inc':adapt(legacyAXSnapshotOwner).replaceAll('TLinkAXCopySnapshotUnlocked','BeforeOwnerAXCopySnapshotUnlocked'),
    'AXScanLimitsUnderTest.inc':axScanLimits,
    'AXSnapshotBeforeScan.inc':adapt(legacyAXScan).replaceAll('TLinkAXCopySnapshotUnlocked','PreScanAXCopySnapshotUnlocked'),
    'AXFindUnderTest.inc':source.slice(source.indexOf('static BOOL TLinkAXTextMatches('),source.indexOf('BOOL TLinkAXResultCompleteForAction(')),
    'AXFindLegacy.inc':legacyAXFind.replaceAll('TLinkAXFindInSnapshot','LegacyAXFindInSnapshot').replaceAll('[matches addObject:element]','fixtureAppendMatch(matches,element)'),
    'AXAttributesUnderTest.inc':adapt(axAttributes(source)),
    'AXAttributesLegacy.inc':adapt(legacyAXAttributes),
    'AXAttributesBeforeParent.inc':adapt(legacyAXParentAttributes),
    'AXSnapshotBeforeAttributes.inc':adapt(axSnapshot(preceding)).replaceAll('TLinkAXCopySnapshotUnlocked','PrecedingAXCopySnapshotUnlocked'),
    'AXCompletenessUnderTest.inc':complete,
    'AXErrorUnderTest.inc':source.slice(source.indexOf('static NSDictionary *TLinkAXError('),source.indexOf('NSDictionary *TLinkAXCapabilitySnapshot(void)')),
    'AXBoundedIntegerUnderTest.inc':source.slice(source.indexOf('static NSInteger TLinkAXBoundedInteger('),source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('))};
console.log('AX snapshot source passed: shared eight-slot pre-enqueue query admission, unchanged validation/caller-stop/CF/window/foreground/authority contract.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ax-snapshot-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/ax-snapshot-window-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    const admissionFile=join(root,'test/ax-admission-safety-test.cpp'),admissionBinary=join(temp,windows?'admission.exe':'admission');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',admissionFile,`/Fe${admissionBinary}`,`/Fo${join(temp,'admission.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-pthread','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',admissionFile,'-o',admissionBinary]);run(admissionBinary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const owner=join(temp,'node-owner.o');run(compiler,['-x','objective-c','-Wall','-Wextra','-Werror','-fno-objc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-c',join(root,'test/ax-node-pool-owner.m'),'-o',owner]);
        const native=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-snapshot-runtime-test.mm'),owner,'-o',native]);run(native,[]);
        const attributes=join(temp,'attributes');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-attribute-runtime-test.mm'),'-o',attributes]);run(attributes,[]);
    }else console.log('macOS actual/frozen AX snapshot Foundation/CF/ARC/sanitizer fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ax-snapshot-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
