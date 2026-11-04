import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {axSymbols,legacyAXSymbols,restoreAXSymbols} from './lib/ax-symbols-baseline.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const source=await read('shared/TLinkAccessibilityTree.mm');restoreAXSymbols(source);
for(const p of ['.github/workflows/build.yml','.github/workflows/stream-app.yml'])assert.match(await read(p),/node scripts\/check-ax-symbol-cache-safety\.mjs/);
const adapt=s=>s.replaceAll(/    static TLinkAXSymbols::Cache symbols\(\n        "([^"]+)",\n        "[^"]+", "[^"]+"\);/g,(_,path)=>`    auto &symbols = fixtureCache("${path}");`)
    .replaceAll('dlopen(','fixtureOpen(').replaceAll('dlsym(','fixtureLookup(').replaceAll('dlclose(','fixtureClose(');
const fixtures={'AXSymbolsUnderTest.inc':adapt(axSymbols(source)),'AXSymbolsLegacy.inc':adapt(legacyAXSymbols)};
console.log('AX symbols source passed: successful fixed symbol pairs/one pinned loader reference, missing lookup retry, unchanged live notify/lock/entitlement/CF and complete preceding AX source.');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ax-symbols-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const file=join(root,'test/ax-symbol-cache-safety-test.cpp'),binary=join(temp,windows?'core.exe':'core');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++11','-Wall','-Wextra','-Werror','-pthread','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',file,'-o',binary]);run(binary,[]);
    await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
    if(process.platform==='darwin'){
        const native=join(temp,'runtime');run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-I',temp,join(root,'test/ax-symbol-cache-runtime-test.mm'),'-o',native]);run(native,[]);
    }else console.log('macOS actual/frozen AX symbol Foundation/CF/ARC/sanitizer fixture included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ax-symbols-'));await rm(temp,{recursive:true,force:true,maxRetries:5,retryDelay:100});}
