import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [runtime,header,fingerprint,makefile]=await Promise.all(['pccontrol/TLinkautoJSRuntime.mm','shared/TLinkHelperRPCReplay.h','shared/TLinkHelperRPCFingerprint.mm','pccontrol/Makefile'].map(read));
assert.match(runtime,/#include "\.\.\/shared\/TLinkHelperRPCReplay.h"/);
assert.match(runtime,/TLinkHelperRPCReplay _helperNativeRPCReplay/);
assert.match(runtime,/TLinkHelperRPCDispatch\(_helperNativeRPCReplay, nativeRequestId, method, arguments/);
assert.match(runtime,/TLinkautoJSHelperRPCPolicy\(method, arguments, TLinkautoJSHelperConfigSnapshot\(\)\)/);
assert.equal((runtime.match(/_helperNativeRPCReplay\.clear\(\)/g)||[]).length,2);
assert.doesNotMatch(runtime,/helperNativeRPCCache|helperNativeRPCOrder|TLinkautoJSArgumentsFingerprint/);
assert.match(header,/cache.begin\(idKey,methodKey,digest\)[\s\S]*result=execute\(\)[\s\S]*cache.finish/);
assert.match(header,/case D::Unavailable:return TLinkHelperRPCError/);
assert.match(makefile,/pccontrol_FILES =[^\n]*\.\.\/shared\/TLinkHelperRPCFingerprint\.mm/);
assert.match(fingerprint,/writeJSONObject:arguments toStream:stream options:NSJSONWritingSortedKeys/);
assert.match(fingerprint,/_tlinkFeed.append\(buffer,length,TLinkHelperRPCSHAUpdate,&_tlinkHash\)/);
assert.doesNotMatch(fingerprint,/dataWithJSONObject|outputStreamToMemory|NSMutableData/);
assert.match(fingerprint,/@finally[\s\S]*\[stream close\]/);

for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-helper-replay-safety\.mjs/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-replay-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'helper-replay.exe':'helper-replay'),file=join(root,'test/helper-replay-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const executable=join(temp,'helper-replay-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/helper-replay-runtime-test.mm'),join(root,'shared/TLinkHelperRPCFingerprint.mm'),'-o',executable]);
        run(executable,[temp]);
    }else console.log('macOS actual helper replay SHA/JSON/exception integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-replay-'));await rm(temp,{recursive:true,force:true});}
