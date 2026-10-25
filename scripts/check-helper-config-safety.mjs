import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async path=>(await readFile(join(root,path),'utf8')).replaceAll('\r\n','\n');
const [runtime,header]=await Promise.all(['pccontrol/TLinkautoJSRuntime.mm','shared/TLinkHelperConfigSnapshot.h'].map(read));
const between=(source,a,b)=>{const x=source.indexOf(a),y=source.indexOf(b,x+a.length);assert.ok(x>=0&&y>x,a);return source.slice(x,y);};
const wrapper=between(runtime,'// BEGIN cached helper config snapshot.','// END cached helper config snapshot.');
assert.match(wrapper,/static TLinkHelperConfigSnapshot config[\s\S]*return config.read\(\)/);
assert.doesNotMatch(wrapper,/dataWithContentsOfFile|JSONObjectWithData/);
assert.match(runtime,/TLinkautoJSHelperRPCPolicy\(method, arguments, TLinkautoJSHelperConfigSnapshot\(\)\)/);
assert.match(header,/memo_\.matches\(identity\)[\s\S]*openFile/);
assert.match(header,/statFile\(fd,&after\)[\s\S]*statPath\(path,&current\)[\s\S]*file.close\(\)[\s\S]*snapshot_=decode\(data\)[\s\S]*memo_\.publish/);
assert.match(header,/std::lock_guard<std::mutex> guard/);
for(const workflow of await Promise.all(['.github/workflows/build.yml','.github/workflows/stream-app.yml'].map(read)))assert.match(workflow,/node scripts\/check-helper-config-safety\.mjs/);
const policy=between(runtime,'static BOOL TLinkautoJSHelperRPCMethodIsAdmin','@class TLinkautoJSRuntime;');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-helper-config-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
    await writeFile(join(temp,'HelperConfigRuntimeUnderTest.inc'),wrapper+policy);
    const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary=join(temp,windows?'helper-config.exe':'helper-config'),file=join(root,'test/helper-config-safety-test.cpp');
    run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]:['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);
    run(binary,[]);
    if(process.platform==='darwin'){
        const executable=join(temp,'helper-config-runtime');
        run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-I',temp,join(root,'test/helper-config-runtime-test.mm'),join(root,'pccontrol/jsruntime/TLinkJSNativeRequest.mm'),'-o',executable]);
        run(executable,[temp]);
    }else console.log('macOS actual helper config file/cache/normalizer/policy integration is included in CI; not run on this host.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-helper-config-'));await rm(temp,{recursive:true,force:true});}
