import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [source,policy,daemon]=await Promise.all(['pccontrol/TemplateMatch.xm','shared/TLinkTemplatePolicy.h','tlinkauto-binary/SocketServer.mm'].map(read));
function between(s,a,b){const start=s.indexOf(a),end=s.indexOf(b,start+a.length);assert.ok(start>=0&&end>start,a);return s.slice(start,end);}
assert.doesNotMatch(source,/\bimread\(|CFAbsoluteTimeGetCurrent\(\)/);
assert.match(source,/TLinkTemplateMakePlan/);assert.match(source,/std::call_once\(threads/);
assert.equal([...source.matchAll(/cv::setNumThreads\(/g)].length,1);
assert.match(source,/base->epoch==epoch/);
assert.match(source,/CGImageSourceCopyPropertiesAtIndex/);
assert.ok(source.indexOf('TLinkImagePixels([properties')<source.indexOf('cv::imdecode(input'));
assert.match(source,/request->consume/);
assert.match(source,/sZXTemplateMemory\(64\*1024\*1024,32\*1024\*1024,96\*1024\*1024\)/);
const screenAdapter=await read('pccontrol/ScreenMatch.xm');
assert.ok(screenAdapter.indexOf('TLinkTemplateParametersValid(')<screenAdapter.indexOf('[Screen createScreenShotCGImageRef]'));
const task21=between(daemon,'static char *handleTemplateMatchTaskInDaemon(const char *buffer)\n{','static uint64_t zx_socketNowMs()');
assert.ok(task21.indexOf('TLinkTemplateParametersValid(')<task21.indexOf('zx_ipcCaptureScreenshotToPath('));
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-template-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 await writeFile(join(temp,'TemplateSadUnderTest.inc'),between(source,'static long long zx_sad_match_region(','\n}\n')+'\n}\n');
 await writeFile(join(temp,'TemplateKeyUnderTest.inc'),between(source,'static std::string zx_tmScaledKey(','NSDictionary *TLinkTemplateMatchPerformance('));
 await writeFile(join(temp,'TemplatePolicyUnderTest.h'),policy.replaceAll('TLinkNativeNowNs()','FixtureNow()'));
 await writeFile(join(temp,'TemplateUnderTest.inc'),source.replace(/^#(?:include|import)[^\n]*\n/gm,'').replaceAll('CGBitmapContextCreate(', 'FixtureBitmapContext('));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'template-core.exe':'template-core'),file=join(root,'test/template-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',`/I${temp}`,file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread','-I',temp,file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'template-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-fobjc-arc',
   '-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO',
   '-framework','CoreMedia','-framework','CoreVideo','-I',temp,'-I',join(root,'shared'),join(root,'test/template-runtime-test.mm'),'-o',runtime]);run(runtime,[temp]);
 }else console.log('macOS actual TemplateMatch storage/decoder/orchestration/pressure tests wired to CI; not run on Windows. OpenCV operations are controlled doubles in that fixture.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-template-'));await rm(temp,{recursive:true,force:true});}
