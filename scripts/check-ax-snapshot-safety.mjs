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
import {legacyAXJSONBufferWriter} from './lib/ax-json-buffer-baseline.mjs';
import {wireBudgetLegacy} from './lib/ax-wire-budget-baseline.mjs';
import {wirePoolLegacy} from './lib/ax-wire-pool-baseline.mjs';
import {wirePublishLegacy} from './lib/ax-wire-publish-baseline.mjs';
import {capabilityPreflightLegacy} from './lib/ax-capability-preflight-baseline.mjs';
import {uiStagesLegacy,legacyUIStagesFind} from './lib/ax-ui-stages-baseline.mjs';
import {legacyAXJSONBudgetWriter} from './lib/ax-json-budget-baseline.mjs';
import {legacyAXJSONStopWriter,restoreAXJSONStopWriter,stopJSONLegacy} from './lib/ax-json-stop-baseline.mjs';
import {boundedJSONLegacy} from './lib/ax-bounded-json-baseline.mjs';
import {restoreAXWireRoute,wireRegion,wireLegacy,wireResponse,wireHandler,wireCapability} from './lib/ax-wire-baseline.mjs';
import {legacyAXHitOutput} from './lib/ax-hit-output-baseline.mjs';
import {legacyAXOutput} from './lib/ax-output-baseline.mjs';
import {legacyAXPreflight} from './lib/ax-preflight-baseline.mjs';
import {legacyAXFindPool} from './lib/ax-find-pool-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkAccessibilityTree.mm');restoreAXSnapshot(source);
const preceding=restoreAXAttributes(source);
const [rootTask,trollTask]=await Promise.all(['pccontrol/Task.xm','stream-app/streamd/POCSocketServer.mm'].map(read));
restoreAXWireRoute(rootTask,'root');restoreAXWireRoute(trollTask,'troll');
const wireAdapt=s=>s.replaceAll('TLinkAXBoundedJSONDataWithStop(','fixtureBoundedJSONWithStop(').replaceAll('TLinkAXBoundedJSONData(','fixtureBoundedJSON(').replaceAll(/\[NSJSONSerialization dataWithJSONObject:([^\n]+?) options:0 error:(?:nil|&error|&jsonError)\]/g,'fixtureJSON($1)')
    .replaceAll('[json base64EncodedStringWithOptions:0]','fixtureBase64(json)').replaceAll('CFAbsoluteTimeGetCurrent()','fixtureWireWall()')
    .replaceAll('    NSError *error = nil;\n','').replaceAll('        NSError *jsonError = nil;\n','')
    .replaceAll('[[NSString stringWithFormat:@"0;;%@\\r\\n", base64] UTF8String]','fixtureWireUTF8([NSString stringWithFormat:@"0;;%@\\r\\n", base64])')
    .replaceAll('response.UTF8String','fixtureWireUTF8(response)').replaceAll('TLinkSuccess(','fixtureWireSuccess(')
    .replaceAll('[NSString stringWithFormat:@"0;;%@\\r\\n", base64]','fixtureWireFormat(base64)')
    .replaceAll('[UIScreen mainScreen]','[WireUIFixtureScreen mainScreen]');
const wireFixtures={};
for(const [name,task] of [['root',rootTask],['troll',trollTask]])for(const current of [false,true]){
    const label=(current?'CurrentUIStages':'BeforeUIStages')+(name==='root'?'Root':'Troll');
    let handler=wireAdapt(current?wireHandler(task,name):uiStagesLegacy(name));
    handler=handler.replaceAll('zx_uiTreeNotifyResult','CurrentRootResponse').replaceAll('TLinkUITreeJSONResponse','CurrentTrollResponse')
        .replaceAll('zx_uiTreeContextChanged','WireRootContextChanged').replaceAll('TLinkUITreeContextChanged','WireTrollContextChanged')
        .replaceAll(name==='root'?'zx_handleUITreeTask':'TLinkHandleUITreeTask',label);
    wireFixtures[label+'.inc']=handler;
}
wireFixtures['UIRootContext.inc']=wireAdapt(wireRegion(rootTask,'static BOOL zx_uiTreeContextChanged(','static void zx_handleUITreeTask(')).replaceAll('zx_uiTreeContextChanged','WireRootContextChanged');
wireFixtures['UITrollContext.inc']=wireAdapt(wireRegion(trollTask,'static BOOL TLinkUITreeContextChanged(','static NSData *TLinkHandleUITreeTask(')).replaceAll('TLinkUITreeContextChanged','WireTrollContextChanged');
for(const name of ['root','troll'])wireFixtures['BeforeCapabilityPreflight'+(name==='root'?'Root':'Troll')+'.inc']=wireAdapt(wireCapability(capabilityPreflightLegacy(name)));
wireFixtures['BeforeWirePublishRootResponse.inc']=wireAdapt(wirePublishLegacy('response')).replaceAll('zx_uiTreeNotifyResult','BeforeWirePublishRootResponse');
wireFixtures['BeforeWirePublishRootCapability.inc']=wireAdapt(wireCapability(wirePublishLegacy('handler')));
for(const name of ['root','troll']){
    const label='BeforeWirePool'+(name==='root'?'Root':'Troll');
    wireFixtures[label+'Response.inc']=wireAdapt(wirePoolLegacy(name,'response')).replaceAll(name==='root'?'zx_uiTreeNotifyResult':'TLinkUITreeJSONResponse',label+'Response');
    wireFixtures[label+'Capability.inc']=wireAdapt(wireCapability(wirePoolLegacy(name,'handler')));
}
for(const [name,task] of [['root',rootTask],['troll',trollTask]]){
    for(const current of [false,true]){
        const label=(current?'Current':'Legacy')+(name==='root'?'Root':'Troll');
        const response=current?wireResponse(task,name):wireLegacy(name,'response');
        const handler=current?wireHandler(task,name):wireLegacy(name,'handler');
        wireFixtures[label+'Response.inc']=wireAdapt(response).replaceAll(name==='root'?'zx_uiTreeNotifyResult':'TLinkUITreeJSONResponse',label+'Response');
        wireFixtures[label+'Capability.inc']=wireAdapt(wireCapability(handler));
    }
}
for(const name of ['root','troll']){
    const label='BeforeWireBudget'+(name==='root'?'Root':'Troll');
    wireFixtures[label+'Response.inc']=wireAdapt(wireBudgetLegacy(name,'response')).replaceAll(name==='root'?'zx_uiTreeNotifyResult':'TLinkUITreeJSONResponse',label+'Response');
    wireFixtures[label+'Capability.inc']=wireAdapt(wireCapability(wireBudgetLegacy(name,'handler')));
}
for(const name of ['root','troll']){
    const label='BeforeBounded'+(name==='root'?'Root':'Troll');
    wireFixtures[label+'Response.inc']=wireAdapt(boundedJSONLegacy(name,'response')).replaceAll(name==='root'?'zx_uiTreeNotifyResult':'TLinkUITreeJSONResponse',label+'Response');
    wireFixtures[label+'Capability.inc']=wireAdapt(wireCapability(boundedJSONLegacy(name,'handler')));
}
restoreAXJSONStopWriter(await read('shared/TLinkAXJSONOutput.mm'));
let oldWriter=legacyAXJSONStopWriter.replaceAll(/^#(?:import|include).*\n/gm,'');
for(const identifier of ['TLinkAXJSONStream','TLinkAXJSONWriter','TLinkAXJSONDataWithWriter','TLinkAXWriteJSON','TLinkAXBoundedJSONData'])oldWriter=oldWriter.replaceAll(identifier,'BeforeStop'+identifier);
wireFixtures['BeforeStopJSONWriter.inc']=oldWriter;
let beforeOutput=legacyAXJSONBudgetWriter.replaceAll(/^#(?:import|include).*\n/gm,'');
for(const identifier of ['TLinkAXJSONStream','TLinkAXJSONWriter','TLinkAXWriteJSON','TLinkAXJSONReportStop','TLinkAXJSONDataWithWriter','TLinkAXBoundedJSONDataWithStop','TLinkAXBoundedJSONData'])beforeOutput=beforeOutput.replaceAll(new RegExp('\\b'+identifier+'\\b','g'),'BeforeOutput'+identifier);
wireFixtures['BeforeOutputJSONWriter.inc']=beforeOutput;
let beforeStorage=legacyAXJSONBufferWriter.replaceAll(/^#(?:import|include).*\n/gm,'');
for(const identifier of ['TLinkAXJSONStream','TLinkAXJSONWriter','TLinkAXWriteJSON','TLinkAXJSONReportStop','TLinkAXJSONAdmitOutput','TLinkAXJSONDataWithWriter','TLinkAXBoundedJSONDataWithStop','TLinkAXBoundedJSONData'])beforeStorage=beforeStorage.replaceAll(new RegExp('\\b'+identifier+'\\b','g'),'BeforeStorage'+identifier);
wireFixtures['BeforeStorageJSONWriter.inc']=beforeStorage;
for(const name of ['root','troll']){
    const label='BeforeJSONStop'+(name==='root'?'Root':'Troll');
    const adaptStop=s=>wireAdapt(s).replaceAll('fixtureBoundedJSON(','fixtureBeforeStopJSON(');
    wireFixtures[label+'Response.inc']=adaptStop(stopJSONLegacy(name,'response')).replaceAll(name==='root'?'zx_uiTreeNotifyResult':'TLinkUITreeJSONResponse',label+'Response');
    wireFixtures[label+'Capability.inc']=adaptStop(wireCapability(stopJSONLegacy(name,'handler')));
}
for(const makefile of ['pccontrol/Makefile','stream-app/streamd/Makefile'])assert.match(await read(makefile),/TLinkAXJSONOutput\.mm/);
wireFixtures['WireTrollFormatter.inc']=wireRegion(trollTask,'static NSData *TLinkResponse(','static NSData *TLinkUnsupported(');
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
const fixtures={...wireFixtures,'AXSnapshotUnderTest.inc':adapt(actual),'AXSnapshotLegacy.inc':adapt(legacyAXSnapshot).replaceAll('TLinkAXCopySnapshotUnlocked','LegacyAXCopySnapshotUnlocked'),
    'AXAdmissionUnderTest.inc':axAdmissionState,
    'AXSnapshotWrapperUnderTest.inc':snapshotWrapper,
    'AXSnapshotWrapperBeforeStop.inc':oldSnapshotWrapper.replace('NSDictionary *TLinkAXCopySnapshot(','NSDictionary *BeforeStopAXCopySnapshot('),
    'AXFindBeforeStop.inc':oldFind.replaceAll('TLinkAXTextMatches','BeforeStopAXTextMatches').replaceAll('TLinkAXFindInSnapshot','BeforeStopAXFindInSnapshot').replaceAll('TLinkAXFindElement','BeforeStopAXFindElement'),
    'AXHitTestUnderTest.inc':adapt(axHitTest(source)),
    'AXHitTestBeforeOutput.inc':adapt(legacyAXHitOutput).replaceAll('TLinkAXElementAtPoint','BeforeOutputAXElementAtPoint'),
    'AXHitTestLegacy.inc':adapt(legacyAXHitTest).replaceAll('TLinkAXElementAtPoint','PrecedingAXElementAtPoint'),
    'AXSnapshotBeforeNodePool.inc':adapt(legacyAXNodePool).replaceAll('TLinkAXCopySnapshotUnlocked','PrePoolAXCopySnapshotUnlocked'),
    'AXSnapshotBeforeOutput.inc':adapt(legacyAXOutput).replaceAll('TLinkAXCopySnapshotUnlocked','BeforeOutputAXCopySnapshotUnlocked'),
    'AXSnapshotBeforePreflight.inc':adapt(legacyAXPreflight).replaceAll('TLinkAXCopySnapshotUnlocked','BeforePreflightAXCopySnapshotUnlocked'),
    'AXSnapshotBeforeOwner.inc':adapt(legacyAXSnapshotOwner).replaceAll('TLinkAXCopySnapshotUnlocked','BeforeOwnerAXCopySnapshotUnlocked'),
    'AXScanLimitsUnderTest.inc':axScanLimits,
    'AXSnapshotBeforeScan.inc':adapt(legacyAXScan).replaceAll('TLinkAXCopySnapshotUnlocked','PreScanAXCopySnapshotUnlocked'),
    'AXFindUnderTest.inc':source.slice(source.indexOf('static BOOL TLinkAXTextMatches('),source.indexOf('BOOL TLinkAXResultCompleteForAction(')),
    'AXFindLegacy.inc':legacyAXFind.replaceAll('TLinkAXFindInSnapshot','LegacyAXFindInSnapshot').replaceAll('[matches addObject:element]','fixtureAppendMatch(matches,element)'),
    'AXFindBeforePool.inc':legacyAXFindPool.replaceAll('TLinkAXFindInSnapshot','BeforePoolAXFindInSnapshot'),
    'AXFindBeforeStages.inc':legacyUIStagesFind.replaceAll('TLinkAXFindInSnapshot','BeforeStagesAXFindInSnapshot').replaceAll('TLinkAXFindElement','BeforeStagesAXFindElement'),
    'AXAttributesUnderTest.inc':adapt(axAttributes(source)),
    'AXAttributesLegacy.inc':adapt(legacyAXAttributes),
    'AXAttributesBeforeParent.inc':adapt(legacyAXParentAttributes),
    'AXSnapshotBeforeAttributes.inc':adapt(axSnapshot(preceding)).replaceAll('TLinkAXCopySnapshotUnlocked','PrecedingAXCopySnapshotUnlocked'),
    'AXCompletenessUnderTest.inc':complete,
    'AXErrorUnderTest.inc':source.slice(source.indexOf('static NSDictionary *TLinkAXError('),source.indexOf('NSDictionary *TLinkAXCapabilitySnapshot(void)')),
    'AXBoundedIntegerUnderTest.inc':source.slice(source.indexOf('static NSInteger TLinkAXBoundedInteger('),source.indexOf('static NSDictionary *TLinkAXCopySnapshotUnlocked('))};
console.log('AX snapshot source passed: complete Task78-81/retry/tap and matcher/enqueue cancellation package, full C05aa task/server/shared source restoration with guards/authority/codecs retained.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ax-snapshot-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})${r.stderr?'\nCaptured stderr (last 12000 characters):\n'+r.stderr.slice(-12000):''}`);}
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
        const wire=join(temp,'wire');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-wire-runtime-test.mm'),owner,'-o',wire]);run(wire,[]);
        const attributes=join(temp,'attributes');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/ax-attribute-runtime-test.mm'),'-o',attributes]);run(attributes,[]);
    }else console.log('macOS actual/frozen AX snapshot Foundation/CF/ARC/sanitizer fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ax-snapshot-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
