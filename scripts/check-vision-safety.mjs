import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [source,header,policy,task,image]=await Promise.all(['pccontrol/TextRecognization/VKOcrManager.xm','pccontrol/TextRecognization/VKOcrManager.h','shared/TLinkVisionPolicy.h','pccontrol/TextRecognization/TextRecognizer.xm','pccontrol/Image.xm'].map(read));
assert.doesNotMatch(source,/initWithCompletionHandler:|topCandidates:1\]\[0\]/);
assert.match(source,/@finally \{UIGraphicsEndImageContext\(\);\}/);
assert.match(source,/dispatch_source_cancel\(monitor\);dispatch_sync\(monitorQueue/);
assert.match(task,/result && !TLinkVisionSlot\(\)->stopped\(\)/);
assert.ok(task.indexOf('vision_parameters_invalid')<task.indexOf('[Screen createScreenShotCGImageRef]'));
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-vision-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 await writeFile(join(temp,'VisionPolicyUnderTest.h'),policy.replaceAll('TLinkNativeNowNs()','FixtureNow()'));
 const section=(a,b)=>image.slice(image.indexOf(a),image.indexOf(b,image.indexOf(a)));
 await writeFile(join(temp,'VisionFramePayload.inc'),section('// BEGIN immutable image payload types','// END immutable image payload types.'));
 await writeFile(join(temp,'VisionFrameProvider.inc'),section('// BEGIN frame Vision provider.','// END frame Vision provider.'));
 await writeFile(join(temp,'VisionHeaderUnderTest.h'),header.replace('#import <UIKit/UIKit.h>','@class UIImage;'));
 await writeFile(join(temp,'VisionUnderTest.inc'),source.replace(/^#(?:include|import)[^\n]*\n/gm,''));
 await writeFile(join(temp,'TextRecognizerUnderTest.inc'),task.replace(/^#(?:include|import)[^\n]*\n/gm,'').replaceAll('[VKOcrManager alloc]','[FixtureTaskManager alloc]'));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'vision-core.exe':'vision-core'),file=join(root,'test/vision-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'vision-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-fobjc-arc','-DZX_DAEMON=1',
   '-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreGraphics','-framework','CoreImage','-framework','Vision','-framework','ImageIO',
   '-I',temp,'-I',join(root,'shared'),join(root,'test/vision-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
 }else console.log('macOS actual VKOcrManager lifecycle/cancel/output fixture wired to CI; not run on Windows. UIKit drawing and real OCR accuracy need device qualification.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-vision-'));await rm(temp,{recursive:true,force:true});}
