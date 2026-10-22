import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=(await readFile(join(root,'pccontrol/Image.xm'),'utf8')).replaceAll('\r\n','\n');
const provider=source.slice(source.indexOf('// BEGIN frame Vision provider.'),source.indexOf('// END frame Vision provider.'));
assert.ok(provider.length>100);assert.doesNotMatch(provider,/createScreenShot|\.clone\(|memcpy|\.assign\(|\.resize\(/);
assert.match(provider,/new\(std::nothrow\) ZXFrameRef\(frame\)/);
assert.match(provider,/holder.release\(\)/);assert.match(provider,/delete static_cast<ZXFrameRef \*>\(info\)/);
const task=await readFile(join(root,'pccontrol/TextRecognization/TextRecognizer.xm'),'utf8');
assert.match(task,/task==TASK_TEXT_FROM_FRAME[\s\S]*TLinkCreateVisionImageFromFrame[\s\S]*if\(!screenshot\)return nil;[\s\S]*}else{/);
assert.match(task,/if\(task==TASK_TEXT_FROM_AREA\)orientation=\[Screen getScreenOrientation\]/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-frame-vision-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'frame-vision.exe':'frame-vision'),file=join(root,'test/frame-vision-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
 run(process.env.PYTHON||(windows?'python':'python3'),['-B',join(root,'test/frame-vision-client-test.py')]);
 console.log('Actual frame provider/store lifetime and Vision task integration are compiled by the image-storage/vision macOS suites; not run on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-frame-vision-'));await rm(temp,{recursive:true,force:true});}
