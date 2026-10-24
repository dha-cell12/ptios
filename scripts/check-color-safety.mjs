import assert from 'node:assert/strict';
import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {dirname,basename,join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const read=async p=>(await readFile(join(root,p),'utf8')).replaceAll('\r\n','\n');
const [source,header,policy,bridge]=await Promise.all(['pccontrol/ColorPicker.xm','pccontrol/ColorPicker.h','shared/TLinkColorPolicy.h','pccontrol/jsruntime/TLinkInProcessNativeBridge.mm'].map(read));
assert.doesNotMatch(source,/NSValue|getValue:|using namespace cv/);
assert.match(source,/ZXColorImage screen\(zx_colorCapture\(request,error\)\)/);
assert.ok(source.indexOf('out.charge=')<source.indexOf('out.bytes.reset('));
const encoder=await read('test/fixtures/native-point-colors-encoder-legacy-v1.inc');
// The old encoder is a frozen compatibility oracle, separate from production numeric decoders.
assert.equal((encoder.match(/^static /gm)||[]).length,1,'legacy color fixture must contain one complete encoder');
assert.doesNotMatch(encoder,/TLinkautoJSDecode(?:Live)?PointColors|TLinkNative(?:FrameColors|ColorPoints)Request/);
assert.match(encoder,/%.0f,,%.0f,,%d,,%d,,%d/);assert.match(encoder,/componentsJoinedByString:@"\|"/);
assert.doesNotMatch(bridge,/TLinkautoJSEncodePointColorTable/);
assert.match(header,/#include "\.\.\/shared\/TLinkNativeColorRange\.h"/);
assert.match(source,/zx_colorRangeScreen\(search,request,result,error\)/);
assert.match(source,/bool searchRGBRange[\s\S]*zx_colorRun/);
const numericRuntime=await read('test/color-runtime-test.mm');
assert.ok(numericRuntime.indexOf('#include "ColorPolicyUnderTest.h"')<numericRuntime.indexOf('#include "../shared/TLinkNativeColorRange.h"'),'fixture clock policy must load before the numeric range header');
assert.match(source,/bool testRGBPoints[\s\S]*TLinkNativeColorPointsTableError[\s\S]*zx_colorPointsScreen/);
assert.match(header,/#include "\.\.\/shared\/TLinkNativeColorPoints\.h"/);
assert.ok(numericRuntime.indexOf('#include "ColorPolicyUnderTest.h"')<numericRuntime.indexOf('#include "../shared/TLinkNativeColorPoints.h"'),'fixture clock policy must load before the numeric points header');
assert.match(source,/bool searchRGBMulti[\s\S]*TLinkNativeColorPointsTableError[\s\S]*zx_colorMultiScreen/);
assert.match(header,/#include "\.\.\/shared\/TLinkNativeColorMulti\.h"/);
assert.ok(numericRuntime.indexOf('#include "ColorPolicyUnderTest.h"')<numericRuntime.indexOf('#include "../shared/TLinkNativeColorMulti.h"'),'fixture clock policy must load before the numeric multi header');
const tempRoot=resolve(tmpdir()),temp=await mkdtemp(join(tempRoot,'tlink-color-'));
function run(command,args){const r=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(r.stdout)process.stdout.write(r.stdout);if(r.stderr)process.stderr.write(r.stderr);if(r.error)throw r.error;assert.equal(r.status,0,`${command} failed (signal=${r.signal})`);}
try{
 await writeFile(join(temp,'ColorPolicyUnderTest.h'),policy.replaceAll('TLinkNativeNowNs()','FixtureNow()'));
 await writeFile(join(temp,'ColorHeaderUnderTest.h'),header.replace('#import <UIKit/UIKit.h>','#import <Foundation/Foundation.h>\n#import <CoreGraphics/CoreGraphics.h>').replace(/#ifdef __cplusplus[\s\S]*?#endif/,''));
 await writeFile(join(temp,'ColorEncoderUnderTest.inc'),encoder);
 await writeFile(join(temp,'ColorUnderTest.inc'),source.replace(/^#(?:include|import)[^\n]*\n/gm,'')
  .replaceAll('calloc(','FixtureCalloc(').replaceAll('free(p);','FixtureFree(p);').replaceAll('CGImageCreateWithImageInRect(','FixtureCrop(')
  .replaceAll('CGColorSpaceCreateDeviceRGB()','FixtureSpace()').replaceAll('CGBitmapContextCreate(','FixtureContext(').replaceAll('CGContextDrawImage(','FixtureDraw('));
 const windows=process.platform==='win32',compiler=process.env.CXX||(windows?'cl':'clang++'),msvc=/^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary=join(temp,windows?'color-core.exe':'color-core'),file=join(root,'test/color-safety-test.cpp');
 run(compiler,msvc?['/nologo','/std:c++14','/W4','/WX','/EHsc',file,`/Fe${binary}`,`/Fo${join(temp,'core.obj')}`]
 :['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-pthread',file,'-o',binary]);run(binary,[]);
 if(process.platform==='darwin'){
  const runtime=join(temp,'color-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',
   '-framework','Foundation','-framework','CoreGraphics','-I',temp,'-I',join(root,'shared'),join(root,'test/color-runtime-test.mm'),'-o',runtime]);run(runtime,[]);
 }else console.log('macOS actual ColorPicker/CoreGraphics/parser/encoder/fault lifetime fixture wired to CI; not run on Windows. Real capture/coordinates/device performance require qualification.');
}finally{assert.equal(dirname(temp),tempRoot);assert.ok(basename(temp).startsWith('tlink-color-'));await rm(temp,{recursive:true,force:true});}
