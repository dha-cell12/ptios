import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [task,image,vendor,policy,troll]=await Promise.all(['pccontrol/TesseractOCRTask.mm','pccontrol/Image.xm','third_party/TesseractOCR/TesseractOCR/G8Tesseract.mm','shared/TLinkOCRPolicy.h','stream-app/streamd/POCSocketServer.mm'].map(read));
function between(s,a,b){const start=s.indexOf(a),end=s.indexOf(b,start+a.length);assert.ok(start>=0&&end>start,a);return s.slice(start,end);}
assert.match(task,/TLinkOCRLRU<std::string, G8Tesseract \*>/);
assert.match(task,/DISPATCH_SOURCE_TYPE_MEMORYPRESSURE/);
assert.match(task,/TLinkOCRAdmission admission\(sZXTessActive\)/);
assert.match(task,/TLinkOCRRequestBudget>\(TLinkCurrentNativeBudget\(\), enteredAt\)/);
assert.match(task,/@finally \{ tesseract.delegate = nil; tesseract.image = nil; \}/);
assert.match(task,/plan.separateWork\) work = gray.clone\(\)/);
assert.match(task,/work.release\(\)/);
assert.match(task,/tesseract.maximumRecognitionTime = requestBudget->remainingSeconds\(\)/);
const roi=image.slice(image.indexOf('bool zx_copyFrameGrayRegionForOCR('));
assert.ok(roi.indexOf('TLinkOCRPlanImage(')<roi.indexOf('copied = frame.gray(roi).clone()'));
const clear=between(vendor,'    // A cached engine must not keep its last request', '    if (image.size.width <= 0');
assert.match(clear,/_tesseract->Clear\(\)/);assert.match(clear,/_image = nil/);
const scaler=between(troll,'static UIImage *TLinkScaledImageForTesseract(', 'static NSData *TLinkRunTrueTesseractOCR(');
assert.ok(scaler.indexOf('TLinkOCRPlanImageExtent(')<scaler.indexOf('UIGraphicsBeginImageContextWithOptions'));
const trueOCR=between(troll,'static NSData *TLinkRunTrueTesseractOCR(', 'static BOOL TLinkAppendVisionOCRTextForRegion(');
assert.ok(trueOCR.indexOf('TLinkOCRPlanImage(')<trueOCR.indexOf('TLinkScaledImageForTesseract(image'));
assert.match(task,/bool recognizeFrameWithTesseract[\s\S]*TLinkOCRAdmission admission[\s\S]*zx_tessRecognizeFrame/);
assert.match(task,/static bool zx_tessRecognizeFrame[\s\S]*TLinkNativeDispatchSync/);
assert.doesNotMatch(task.slice(task.indexOf('bool recognizeFrameWithTesseract')),/zx_tessSplitEventData|initWithUTF8String/);
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-ocr-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 await writeFile(join(temp,'OCRTaskUnderTest.inc'),task.replace(/^#(?:include|import)[^\n]*\n/gm,'').replaceAll('TLinkNativeNowNs()','FixtureNow()'));
 await writeFile(join(temp,'OCRPolicyUnderTest.h'),policy.replaceAll('TLinkNativeNowNs()','FixtureNow()'));
 await writeFile(join(temp,'OCRImageClearUnderTest.inc'),clear);
 await writeFile(join(temp,'OCRImageSetterUnderTest.inc'),between(vendor,'- (void)setImage:(UIImage *)image {','/**\n * Sets the region of interest'));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'ocr-policy.exe':'ocr-policy'),file=join(root,'test/ocr-policy-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++14','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'ocr-runtime');
  run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fobjc-arc','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreGraphics','-I',temp,'-I',join(root,'shared'),join(root,'test/ocr-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
 }else console.log('macOS actual root OCR adapter/provider ownership and vendor nil cleanup integration is wired to CI; not run on Windows. CV and OCR engine remain controlled doubles in that fixture.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-ocr-'));await rm(temp,{recursive:true,force:true});}
