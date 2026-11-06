import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import {restoreCapturePreparation,capturePart,captureBefore,checkCaptureHeader} from './lib/capture-preparation-baseline.mjs';
import {bitmapPart,bitmapBefore,restoreBitmap,checkBitmapHeader} from './lib/bitmap-resources-baseline.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (await readFile(join(root, "pccontrol/Screen.xm"), "utf8")).replaceAll("\r\n", "\n");
const troll=(await readFile(join(root,'stream-app/streamd/StreamCaptureSource.mm'),'utf8')).replaceAll('\r\n','\n');
const common=(await readFile(join(root,'pccontrol/Common.xm'),'utf8')).replaceAll('\r\n','\n');
const preceding=restoreCapturePreparation(source,'root');restoreCapturePreparation(troll,'troll');restoreCapturePreparation(common,'common');
const bitmapImage=(await readFile(join(root,'pccontrol/Image.xm'),'utf8')).replaceAll('\r\n','\n');
const bitmapCapture=(await readFile(join(root,'stream-app/streamd/CaptureCore.mm'),'utf8')).replaceAll('\r\n','\n');
restoreBitmap(bitmapImage,'image');restoreBitmap(bitmapCapture,'capture');
await Promise.all(['TLinkBitmapResourceCore.h','TLinkBitmapResources.h'].map(async name=>checkBitmapHeader(name,(await readFile(join(root,'shared',name),'utf8')).replaceAll('\r\n','\n'))));
await Promise.all(['TLinkCapturePlan.h','TLinkCapturePreparation.h','TLinkCaptureOwnership.h'].map(async name=>checkCaptureHeader(name,(await readFile(join(root,'shared',name),'utf8')).replaceAll('\r\n','\n'))));
assert.doesNotMatch(source, /CGColorSpaceRelease|IOSurfaceUnLock/);
assert.match(source, /return CGImageRetain\(gKeepImage\)/);
assert.match(source, /zx_captureGeometry\(screenSize.width, screenSize.height, screen.scale, rotateIPad, &geometry\)/);
for (const [key, member] of [["AllocSize", "allocationSize"], ["BytesPerRow", "bytesPerRow"], ["Width", "width"], ["Height", "height"]]) {
  assert.ok(preceding.includes(`@"IOSurface${key}": @(geometry.${member})`));
}
assert.match(source, /return zx_captureSurfaceImage\(\(__bridge CFDictionaryRef\)properties, rotateIPad\)/);
const coreStart = source.indexOf("struct TLinkCaptureGeometry {");
const coreEnd = source.indexOf("// END capture ownership core.", coreStart);
assert.ok(coreStart >= 0 && coreEnd > coreStart);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-capture-safety-"));
function run(command,args){const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout:120000});if(result.stdout)process.stdout.write(result.stdout);if(result.stderr)process.stderr.write(result.stderr);if(result.error)throw result.error;assert.equal(result.status,0,`${command} failed (signal=${result.signal})${result.stderr?'\n'+result.stderr.slice(-12000):''}`);}
try {
  await writeFile(join(temp, "CaptureCoreUnderTest.inc"), source.slice(coreStart, coreEnd));
  const trollFresh=capturePart(troll,'troll','fresh');
  await writeFile(join(temp,'TrollFreshAPIUnderTest.inc'),trollFresh.slice(0,trollFresh.indexOf('CGImageRef SCCreateScreenShotCGImage(void)')));
  const preparation=(await readFile(join(root,'shared/TLinkCapturePreparation.h'),'utf8')).replaceAll('\r\n','\n');
  const regex=s=>s.replaceAll('[device rangeOfString:@"^iPad[8-9]|iPad[1-9][0-9]+" options:NSRegularExpressionSearch]','fixtureRegex(device)');
  const fixtures={
    'CapturePreparationUnderTest.inc':regex(preparation).replace('namespace TLinkCapturePreparation {','namespace MeasuredCapturePreparation {').replace('#include "TLinkCapturePlan.h"','').replace('candidate=MakeProperties(key);','candidate=fixtureProperties(key);'),
    'RootGeometryUnderTest.inc':source.slice(coreStart,source.indexOf('static CGImageRef zx_captureRotatedImage(',coreStart)),
  };
  for(const current of [false,true]){
    const label=current?'Current':'Before';
    fixtures[label+'DeviceUnderTest.inc']=(current?capturePart(common,'common','device'):captureBefore('common','device')).replace('getDeviceName()',label+'GetDeviceName()').replaceAll('uname(','fixtureUname(');
    fixtures[label+'RootEntry.inc']=regex(current?capturePart(source,'root','entry'):captureBefore('root','entry'))
      .replace('zx_captureScreenCGImageRef(void)',label+'RootCapture(void)').replaceAll('[UIScreen mainScreen]','[CaptureFixtureScreen mainScreen]').replaceAll('UIScreen *','CaptureFixtureScreen *')
      .replaceAll('getDeviceName()',label+'GetDeviceName()').replaceAll('zx_captureSurfaceImage(','fixtureCapture(')
      .replace('static TLinkCapturePlan::BoolMemo deviceMemo;','auto &deviceMemo=*rootDeviceMemo;')
      .replace('static TLinkCapturePreparation::Properties propertyMemo;','auto &propertyMemo=*rootProperties;')
      .replaceAll('TLinkCapturePreparation::','MeasuredCapturePreparation::')
      .replace('    NSDictionary *properties = @{','    ++legacyBuilds;\n    NSDictionary *properties = @{');
    fixtures[label+'TrollSurface.inc']=((current?'':captureBefore('troll','round'))+(current?capturePart(troll,'troll','surface'):captureBefore('troll','surface')))
      .replaceAll('SCDisplayPixelSize(',label+'DisplaySize(').replaceAll('SCCreateBGRAIOSurface(',label+'CreateSurface(').replaceAll('SCRoundUp(','BeforeRoundUp(')
      .replaceAll('[UIScreen mainScreen]','[CaptureFixtureScreen mainScreen]').replaceAll('UIScreen *','CaptureFixtureScreen *').replaceAll('IOSurfaceCreate(','fixtureSurface(').replaceAll('IOSurfaceRef','FixtureSurface *')
      .replace('static TLinkCapturePreparation::Properties propertyMemo;','auto &propertyMemo=*trollProperties;').replaceAll('TLinkCapturePreparation::','MeasuredCapturePreparation::');
  }
  await Promise.all(Object.entries(fixtures).map(([name,value])=>writeFile(join(temp,name),value)));
  const bitmapHeader=(await readFile(join(root,'shared/TLinkBitmapResources.h'),'utf8')).replaceAll('\r\n','\n');
  const bitmapFixtures={'BitmapResourcesUnderTest.inc':bitmapHeader.replace('namespace TLinkBitmapResources {','namespace MeasuredBitmapResources {')
    .replace('#include "TLinkBitmapResourceCore.h"','').replace('#include "TLinkCaptureOwnership.h"','')
    .replace('static TLinkBitmapCore::Memo<CGColorSpaceRef> memo(&CGColorSpaceRelease);','auto &memo=*rgbMemo;')
    .replace('return CGColorSpaceCreateDeviceRGB();','return fixtureRGB();').replace('return CreateData(owner);','return fixtureData(owner);')};
  const bitmapAdapt=s=>s.replaceAll('TLinkBitmapResources::','MeasuredBitmapResources::').replaceAll('CGColorSpaceCreateDeviceRGB()','fixtureRGB()')
    .replaceAll('CGColorSpaceRelease(','fixtureDropSpace(').replaceAll('CGBitmapContextCreate(','fixtureContext(')
    .replaceAll('CGContextRelease','fixtureDropContext').replaceAll('CGContextDrawImage(','fixtureDraw(');
  for(const current of [false,true]){
    const label=current?'Current':'Before',part=(kind,name)=>current?bitmapPart(kind==='image'?bitmapImage:kind==='capture'?bitmapCapture:troll,kind,name):bitmapBefore(kind,name);
    bitmapFixtures[label+'BitmapCapture.inc']=bitmapAdapt(part('capture','production')).replace('+ (CaptureOutcome *)runProductionCapture {','static BitmapOutcome *'+label+'ProductionCapture(){')
      .replaceAll('CaptureOutcome','BitmapOutcome').replaceAll('[UIImage imageWithCGImage:','[BitmapFixtureImage imageWithCGImage:').replaceAll('SCCreateScreenShotCGImage()','fixtureScreen()')
      .replaceAll('CGDataProviderCreateWithCFData(','fixtureProvider(').replaceAll('CGImageCreate(','fixtureImage(').replace('TLinkBitmapCore::Bytes::Allocate(byteCount)','fixtureStorage(byteCount)');
    bitmapFixtures[label+'BitmapStream.inc']=bitmapAdapt(part('stream','copy')).replace('SCCopyCGImageWithCoreGraphics(',label+'StreamCopy(')
      .replaceAll('CVPixelBufferLockBaseAddress(','fixtureLock(').replaceAll('CVPixelBufferUnlockBaseAddress(','fixtureUnlock(');
    bitmapFixtures[label+'BitmapGray.inc']=bitmapAdapt(part('image','gray')).replace('zx_cvMatGrayFromCGImage(',label+'Gray(');
    bitmapFixtures[label+'BitmapRender.inc']=bitmapAdapt(part('image','render')).replace('zx_renderBGRAFromCGImage(',label+'Render(');
  }
  const pipeline=bitmapPart(troll,'stream','pipeline');
  bitmapFixtures['BitmapPipelineGuard.inc']=pipeline.slice(pipeline.indexOf('    auto unlockCapture='),pipeline.indexOf('    BOOL forceLegacy'))
    .replaceAll('os_unfair_lock_unlock(','fixturePipelineUnlock(');
  assert.ok(bitmapFixtures['BitmapPipelineGuard.inc'].includes('captureOwner'));
  await Promise.all(Object.entries(bitmapFixtures).map(([name,value])=>writeFile(join(temp,name),value)));
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "capture-safety-test.exe" : "capture-safety-test");
  const testSource = join(root, "test/capture-safety-test.cpp");
  const args = msvc
    ? ["/nologo", "/std:c++14", "/W4", "/WX", "/EHsc", `/I${temp}`, testSource, `/Fe${binary}`, `/Fo${join(temp, "test.obj")}`]
    : ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-pthread", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I", temp, testSource, "-o", binary];
  run(compiler,args);run(binary,[]);
  if(process.platform==='darwin'){
    const owner=join(temp,'owner.o');run(compiler,['-x','objective-c','-Wall','-Wextra','-Werror','-fno-objc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-c',join(root,'test/ax-node-pool-owner.m'),'-o',owner]);
    const native=join(temp,'preparation');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-I',temp,join(root,'test/capture-preparation-runtime-test.mm'),owner,'-o',native]);run(native,[]);
    const bitmap=join(temp,'bitmap');run(compiler,['-std=c++14','-Wall','-Wextra','-Werror','-fobjc-arc','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation','-framework','CoreGraphics','-framework','CoreVideo','-I',temp,join(root,'test/bitmap-resources-runtime-test.mm'),'-o',bitmap]);run(bitmap,[]);
  }else console.log('Capture preparation/bitmap Foundation/ARC/sanitizer integration included for macOS CI; not executed on this host.');
} finally {
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-capture-safety-"));
  await rm(temp, { recursive: true, force: true });
}
