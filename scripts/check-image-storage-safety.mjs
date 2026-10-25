import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = (await readFile(join(root, 'pccontrol/Image.xm'), 'utf8')).replaceAll('\r\n', '\n');
const section = (begin, end) => {
  const a = source.indexOf(begin), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a, `Missing fixture section: ${begin}`); return source.slice(a, b);
};
function bodyAfter(start, text = source) {
  const a = text.indexOf('{', start); assert.ok(a >= 0);
  // Strings/comments in these queue blocks have no unmatched braces.
  let depth = 1, b = a + 1;
  for (; b < text.length && depth; ++b) { if (text[b] === '{') ++depth; if (text[b] === '}') --depth; }
  assert.equal(depth, 0); return text.slice(a + 1, b - 1);
}
for (const match of source.matchAll(/TLinkNativeDispatchSync\(zx_imageQueue\(\), \^/g)) {
  const queueBody = bodyAfter(match.index);
  assert.doesNotMatch(queueBody, /zx_findTemplateSAD|cvtColor|\.clone\(|resize\(|zx_readBGRA|zx_parsePointTable|zx_renderBGRA|imdecode|imread/,
    'Store critical sections must only manage metadata/references');
}
assert.doesNotMatch(source, /dispatch_sync\(zx_imageQueue\(|\.released|gNext(?:Frame|Image)Id\+\+|\bimread\(/);
assert.equal([...source.matchAll(/CFAbsoluteTimeGetCurrent\(/g)].length, 1, 'Only legacy published wall timestamp remains');
assert.match(source, /frame\.capturedAtMs = \(uint64_t\)\(CFAbsoluteTimeGetCurrent/);
assert.match(source, /dispatch_source_set_timer[\s\S]*gFrameStore\.empty\(\) \? DISPATCH_TIME_FOREVER[\s\S]*DISPATCH_TIME_FOREVER, NSEC_PER_MSEC/);
assert.match(source, /TLinkImagePixels\(CGImageGetWidth\(screen\)[\s\S]*zx_reservePayload\(TLinkImageKind::Frame[\s\S]*zx_renderBGRAFromCGImage\(screen/);
const decoder = section('static cv::Mat zx_decodeBoundedImage(', '// BEGIN structured image open.');
assert.doesNotMatch(decoder,/openStoredImage|zx_openImage/);
assert.match(decoder, /readDataOfLength:maxEncodedBytes \+ 1/);
assert.match(decoder, /CGImageSourceCopyPropertiesAtIndex[\s\S]*TLinkImagePixels[\s\S]*zx_reservePayload[\s\S]*cv::imdecode/);
assert.match(decoder, /gray\.cols == \(int\)height && gray\.rows == \(int\)width/);
assert.match(await readFile(join(root, 'pccontrol/Makefile'), 'utf8'), /pccontrol_FRAMEWORKS = [^\n]*ImageIO/);
for (const name of ['handleFrameCaptureTaskFromRawData', 'handleFindImageTaskFromRawData', 'matchImageInFrame',
  'handleColorInFrameTaskFromRawData', 'handleFrameBatchTaskFromRawData', 'zx_copyFrameGrayRegionForOCR']) {
  assert.match(bodyAfter(source.indexOf(name + '(')), /TLinkImageWork work\(gImageCompute\)/, `${name} needs compute admission`);
}
// Inspect each function's own __block locals: C++ lambdas cannot capture them.
// The portable core alone cannot diagnose this Objective-C++ language restriction.
const admissionFixtures = {};
for (const [label, name] of [['Find', 'matchImageInFrame'], ['Batch', 'handleFrameBatchTaskFromRawData']]) {
  const body = bodyAfter(source.indexOf(name + '('));
  const blockLocals = [...body.matchAll(/__block\s+[^;]+?\b(\w+)\s*;/g)].map(match => match[1]);
  for (const lambda of body.matchAll(/\[&\]\s*\{/g)) {
    const computeBody = bodyAfter(lambda.index, body);
    for (const local of blockLocals) assert.doesNotMatch(computeBody, new RegExp(`\\b${local}\\b`),
      `${name}: C++ lambda must not capture __block local ${local}`);
  }
  const first = body.indexOf(label==='Find'?'    bool ok=false;':'    NSString *ret = nil;'), compute = body.indexOf('    [&] {', first);
  assert.ok(first >= 0 && compute > first);
  admissionFixtures[`Image${label}AdmissionUnderTest.inc`] = body.slice(first, compute);
  const lookup = body.slice(compute).match(/^\s*auto iit = \w+\.find\(imageId\);/m);
  assert.ok(lookup, `${name}: missing production compute lookup`);
  admissionFixtures[`Image${label}LookupUnderTest.inc`] = lookup[0];
}
// This fixture needs only the error constructor. Wire validators belong to the
// modern-image handler fixture and would be unused under macOS -Werror here.
const frameErrorHelper = section('static NSError *zx_frameError(', '// BEGIN typed frame/image wire admission.');
assert.doesNotMatch(frameErrorHelper, /\bstatic\s+bool\s+zx_/, 'Storage error fixture must not import wire validators');
const numericRelease=section('// BEGIN numeric frame release.','// END numeric frame release.');
assert.match(numericRelease,/__block size_t removed=0/);assert.match(numericRelease,/TLinkNativeDispatchSync\(zx_imageQueue\(\), \^\{/);
const portableRelease=numericRelease.replace('__block ','').replace('TLinkNativeDispatchSync(zx_imageQueue(), ^{','[&]{').replace('    });','    }();');
assert.doesNotMatch(portableRelease,/__block|TLinkNativeDispatchSync|\^\{/);
const numericImageRelease=section('// BEGIN numeric image release.','// END numeric image release.');
assert.match(numericImageRelease,/__block size_t removed=0/);assert.match(numericImageRelease,/TLinkNativeDispatchSync\(zx_imageQueue\(\), \^\{/);
const portableImageRelease=numericImageRelease.replace('__block ','').replace('TLinkNativeDispatchSync(zx_imageQueue(), ^{','[&]{').replace('    });','    }();');
assert.doesNotMatch(portableImageRelease,/__block|TLinkNativeDispatchSync|\^\{|gFrameStore|zx_rearmFrameExpiry|TLinkImageWork/);
const objectBody=bodyAfter(source.indexOf('NSString* handleImageObjectTaskFromRawData('));
const parserEnd=objectBody.indexOf('    if (action == 1) {');assert.ok(parserEnd>0);
const imageReleaseAction='NSString *imageReleaseActionUnderTest(UInt8 *eventData,NSError **error){'+objectBody.slice(0,parserEnd)+
  section('// BEGIN raw image release action.','// END raw image release action.').replace('    else if','    if')+'return nil;\n}\n';
const imageOpen=section('// BEGIN structured image open.','// END structured image open.');
const rawImageOpen=section('    else if (action == 2) {','    // BEGIN raw image release action.');
assert.match(imageOpen,/TLinkImageWork work\(gImageCompute\)/);
assert.match(imageOpen,/zx_decodeBoundedImage[\s\S]*zx_storeImageLocked[\s\S]*publishedId=imageId[\s\S]*stringWithFormat/);
const imageOpenAction='NSString *imageOpenActionUnderTest(UInt8 *eventData,NSError **error){'+objectBody.slice(0,parserEnd)+rawImageOpen.replace('    else if','    if')+'return nil;\n}\n';
const frameCapture=section('// BEGIN numeric frame capture.','// END numeric frame capture.');
const rawCapture=section('NSString* handleFrameCaptureTaskFromRawData(', '// BEGIN numeric frame release.');
assert.match(frameCapture,/TLinkImageWork work\(gImageCompute\)/);
assert.doesNotMatch(frameCapture,/stringWithFormat|componentsSeparatedByString/);
assert.match(frameCapture,/publishedId=frameId[\s\S]*value\.id=frameId/);
assert.match(rawCapture,/TLinkNativeFrameCaptureBody\(value\)/);
const captureParser=section('static NSArray<NSString *> *zx_splitEventData(UInt8 *eventData)\n{','static bool zx_stringIsPointCoord(');
const fixtures = {
  ...admissionFixtures,
  'ImageOpenUnderTest.inc':imageOpen,
  'ImageOpenActionUnderTest.inc':imageOpenAction,
  'ImageOpenResolverUnderTest.inc':section('static NSString *zx_resolveImagePath(', 'static cv::Mat zx_cvMatGrayFromCGImage('),
  'ImageOpenOwnerUnderTest.inc':section('static void zx_applyImageOwner(', 'static bool zx_ownerMatchFields('),
  'FrameCaptureUnderTest.inc': frameCapture+rawCapture,
  'FrameCaptureOwnerUnderTest.inc': section('static void zx_applyFrameOwner(', 'static void zx_applyImageOwner('),
  'FrameCaptureParserUnderTest.inc': captureParser,
  'NumericImageReleaseUnderTest.inc': numericImageRelease,
  'ImageReleasePortableUnderTest.inc': portableImageRelease,
  'ImageReleaseActionUnderTest.inc': imageReleaseAction,
  'ImageNumericReleaseUnderTest.inc': numericRelease,
  'ImageReleaseCoreUnderTest.inc': portableRelease,
  'ImagePayloadUnderTest.inc': section('// BEGIN immutable image payload types', '// END immutable image payload types.'),
  'FrameVisionUnderTest.inc': section('// BEGIN frame Vision provider.', '// END frame Vision provider.')
    .replaceAll('CGDataProviderCreateWithData(', 'FixtureFrameProvider(').replaceAll('CGImageCreate(', 'FixtureFrameImage('),
  'ImageGlobalsUnderTest.inc': section('// BEGIN image store globals', '// END image store globals.'),
  'ImageCoreUnderTest.inc': section('// BEGIN image store core', '// END image store core.'),
  'ImageDispatchUnderTest.inc': section('// BEGIN image store dispatch adapter.', '// END image store dispatch adapter.'),
  'ImageDecoderUnderTest.inc': decoder,
  'ImageErrorUnderTest.inc': frameErrorHelper,
  'ImageOwnerUnderTest.inc': section('static bool zx_ownerMatchFields(', 'static void zx_cleanupFramesLocked(uint64_t nowMs);\nstatic NSArray'),
  'ImageOwnerPartsUnderTest.inc': section('static std::string zx_stringFromPart(', 'static void zx_applyFrameOwner('),
  'ImageReleaseUnderTest.inc': section('NSString* handleFrameReleaseTaskFromRawData(', '// BEGIN numeric frame image match.'),
  'ImageQueueUnderTest.inc': 'static dispatch_queue_t zx_imageQueue() {' + bodyAfter(source.indexOf('static dispatch_queue_t zx_imageQueue(')) + '}\n',
};
assert.doesNotMatch(fixtures['ImageReleaseUnderTest.inc'],/matchImageInFrame|TLinkNativeFrameImageRequest/,'release fixture must not import the adjacent matcher');
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot, 'tlink-image-storage-'));
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 120000 });
  if (result.stdout) process.stdout.write(result.stdout); if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  assert.equal(result.status, 0, `${command} failed (signal=${result.signal})`);
}
try {
  for (const [name, content] of Object.entries(fixtures)) await writeFile(join(temp, name), content);
  const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? 'image-storage.exe' : 'image-storage');
  const file = join(root, 'test/image-storage-safety-test.cpp');
  run(compiler, msvc ? ['/nologo', '/std:c++14', '/W4', '/WX', '/EHsc', `/I${temp}`, file, `/Fe${binary}`, `/Fo${join(temp, 'core.obj')}`]
    : ['-std=c++14', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread', '-I', temp, file, '-o', binary]);
  run(binary, []);
  if (process.platform === 'darwin') {
    const runtime = join(temp, 'image-storage-runtime');
    run(compiler, ['-std=c++14', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations', '-fobjc-arc', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
      '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', 'ImageIO', '-I', temp, join(root, 'test/image-storage-runtime-test.mm'), '-o', runtime]);
    run(runtime, [temp]);
  } else console.log('macOS actual image store/dispatch/snapshot/expiry integration is included in root CI; not run on this host.');
} finally {
  assert.equal(dirname(temp), tempRoot); assert.ok(basename(temp).startsWith('tlink-image-storage-'));
  await rm(temp, { recursive: true, force: true });
}
