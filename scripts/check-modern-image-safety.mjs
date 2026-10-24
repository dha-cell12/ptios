import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=(await readFile(join(root,'pccontrol/Image.xm'),'utf8')).replaceAll('\r\n','\n');
function section(start,end){const a=source.indexOf(start),b=source.indexOf(end,a+start.length);assert.ok(a>=0&&b>a);return source.slice(a,b);}
const sad=section('static long long zx_sad_match_region','static BOOL zx_findTemplateSAD');
const scale=section('static BOOL zx_findTemplateSAD','NSString* handleFrameCaptureTaskFromRawData');
assert.ok(scale.indexOf('TLinkModernImageMakePlan(')<scale.indexOf('cv::resize('));
assert.ok(scale.indexOf('request->reserve(')<scale.indexOf('cv::resize('));
assert.match(sad,/request->consume\(size_t\(w\)\)/);
const color=section('// BEGIN numeric frame color pick.','NSString* handleFrameBatchTaskFromRawData');
assert.match(color,/TLinkColorRequest request/);assert.match(color,/zx_frameColorInputs/);
assert.match(color,/TLinkColorAnchors/);assert.match(color,/request.consume/);
assert.doesNotMatch(color,/-minDx|\[data\[12\] intValue\] \+ 1;[\s\S]*?if \(step <= 0\)/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-modern-image-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 await writeFile(join(temp,'ModernSadUnderTest.inc'),sad);
 await writeFile(join(temp,'ModernScaleUnderTest.inc'),scale);
 await writeFile(join(temp,'FrameColorUnderTest.inc'),color);
 await writeFile(join(temp,'ModernPayload.inc'),section('// BEGIN immutable image payload types','// END immutable image payload types.'));
 await writeFile(join(temp,'ModernFindFrame.inc'),section('NSString* handleFindImageInFrameTaskFromRawData','// BEGIN numeric frame color pick.'));
 await writeFile(join(temp,'ModernBatch.inc'),section('NSString* handleFrameBatchTaskFromRawData','bool zx_copyFrameGrayRegionForOCR'));
 await writeFile(join(temp,'ModernFindFresh.inc'),source.slice(source.indexOf('NSString* handleFindImageTaskFromRawData')));
 await writeFile(join(temp,'FrameColorHelpers.inc'),
  section('static NSError *zx_frameError(','static std::string zx_stringFromPart(')+
  section('static NSArray<NSString *> *zx_splitEventData(UInt8 *eventData)\n{','static bool zx_renderBGRAFromCGImage(CGImageRef img, std::vector<uint8_t> &out, int *outW, int *outH, int *outBpr)\n{')+
  section('static inline bool zx_bgraColorMatch(int r, int g, int b, int tr, int tg, int tb, int mode, double value)\n{','// Decode the same bounded byte sequence'));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'modern-image.exe':'modern-image'),file=join(root,'test/modern-image-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',`/I${temp}`,file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread','-I',temp,file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'frame-color-runtime');
  run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreGraphics','-I',temp,join(root,'test/frame-color-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
 }else console.log('macOS actual frame-color wire/handler/stride/offset fixture wired to CI; not run on Windows.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-modern-image-'));await rm(temp,{recursive:true,force:true});}
