import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {axSymbols,legacyAXSymbols,restoreAXSymbols} from './lib/ax-symbols-baseline.mjs';
import {axFrontmost,legacyAXFrontmost,checkAXSymbolHeader} from './lib/ax-frontmost-symbols-baseline.mjs';
import {axEntitlement,axCapability,legacyAXEntitlement,legacyAXCapability} from './lib/ax-entitlement-task-baseline.mjs';
import {axScanLimits} from './lib/ax-scan-baseline.mjs';
import {legacyAXLazyFrontmost} from './lib/ax-lazy-frontmost-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkAccessibilityTree.mm');restoreAXSymbols(source);
checkAXSymbolHeader(await read('shared/TLinkAXSymbolCache.h'));
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-ax-symbol-cache-safety\.mjs/);
const adapt=s=>s.replaceAll(/    static TLinkAXSymbols::Cache symbols\(\n        "([^"]+)",\n        "[^"]+", "[^"]+"\);/g,(_,path)=>`    auto &symbols = fixtureCache("${path}");`)
    .replaceAll('dlopen(','fixtureOpen(').replaceAll('dlsym(','fixtureLookup(').replaceAll('dlclose(','fixtureClose(');
const frontmostAdapt=s=>s.replace(/    static TLinkAXSymbols::Cache copySymbols\([\s\S]*?\);/,'    auto &copySymbols = *copyCache;')
    .replace('    static TLinkAXSymbols::Symbol serverPortSymbol("SBSSpringBoardServerPort");','    auto &serverPortSymbol = *serverSymbol;')
    .replace('    static TLinkAXSymbols::Symbol legacyFrontmostSymbol("SBFrontmostApplicationDisplayIdentifier");','    auto &legacyFrontmostSymbol = *legacySymbol;')
    .replaceAll('dlopen(','fixtureOpen(').replaceAll('dlsym(','fixtureLookup(').replaceAll('dlclose(','fixtureClose(').replaceAll('CFRelease(','fixtureRelease(');
const fixtures={'AXSymbolsUnderTest.inc':adapt(axSymbols(source)),'AXSymbolsLegacy.inc':adapt(legacyAXSymbols),
    'AXFrontmostUnderTest.inc':frontmostAdapt(axFrontmost(source)),
    'AXFrontmostLegacy.inc':frontmostAdapt(legacyAXFrontmost),
    'AXFrontmostBeforeLazy.inc':frontmostAdapt(legacyAXLazyFrontmost),
    'AXEntitlementTaskUnderTest.inc':adapt(axEntitlement(source)).replaceAll('CFRelease(','fixtureRelease('),
    'AXEntitlementTaskLegacy.inc':adapt(legacyAXEntitlement).replaceAll('CFRelease(','fixtureRelease('),
    'AXCapabilityUnderTest.inc':axCapability(source).replaceAll('CFRelease(','fixtureRelease('),
    'AXCapabilityLegacy.inc':legacyAXCapability,'AXCapabilityConstants.inc':axScanLimits};
console.log('AX symbols source passed: deferred foreground second-symbol lookup, unchanged default cache/task/CF/guards and complete preceding AX/cache source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ax-symbols-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/ax-symbol-cache-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-pthread','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/ax-symbol-cache-runtime-test.mm'),'-o',native]);run(native,[]);
        const frontmost=join(temp,'frontmost');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/ax-frontmost-symbols-runtime-test.mm'),'-o',frontmost]);run(frontmost,[]);
        const capability=join(temp,'capability');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/ax-entitlement-task-runtime-test.mm'),'-o',capability]);run(capability,[]);
    }else console.log('macOS actual/frozen AX symbol Foundation/CF/ARC/sanitizer fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ax-symbols-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
