import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { dirname, basename, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = async p => (await readFile(join(root, p), 'utf8')).replaceAll('\r\n', '\n');
const [a, b, adaptive, socket] = await Promise.all(['pccontrol/H264Stream.xm','stream-app/streamd/H264Stream.mm','shared/TLinkAdaptiveStreaming.mm','shared/TLinkH264Socket.h'].map(read));
function between(source, begin, end) { const x = source.indexOf(begin), y = source.indexOf(end, x + begin.length); assert.ok(x >= 0 && y > x, begin); return source.slice(x, y); }
const fixtures = {};
for (const [prefix, source] of [['Root', a], ['Troll', b]]) {
 fixtures[`${prefix}SendUnderTest.inc`] = between(source, 'static bool sendAll(', 'static uint64_t zx_htonll(');
 fixtures[`${prefix}EndianUnderTest.inc`] = between(source, 'static uint64_t zx_htonll(', 'static uint64_t zx_now_us(');
 fixtures[`${prefix}RawUnderTest.inc`] = between(source, 'static bool writeRawAnnexBFrame(', 'static uint32_t mpegCrc32(');
 fixtures[`${prefix}TSUnderTest.inc`] = between(source, 'static bool writeTSPackets(', '#pragma mark - Per-frame');
 fixtures[`${prefix}TablesUnderTest.inc`] = between(source, 'static bool sendTables(', '// BEGIN H264 client release.');
 fixtures[`${prefix}PATUnderTest.inc`] = between(source, 'static uint32_t mpegCrc32(', '#pragma mark - TS packet writer');
 fixtures[`${prefix}ReleaseUnderTest.inc`] = between(source, '// BEGIN H264 client release.', '// END H264 client release.');
 fixtures[`${prefix}ActiveUnderTest.inc`] = source.match(/static std::atomic<int> gActiveClientFd\{-1\};/)[0];
 const loop = between(source, '        while (running) {', '#pragma mark - Server');
 assert.doesNotMatch(loop, /TLinkAdaptiveStreamingDecision(?:ForSession)?\(|TLinkAdaptiveStreamingRecordRecovery\(|usleep\(|streamSeconds \+=/);
 assert.match(loop, /readTargetFPS:/);
 assert.match(loop, /writer.begin\(\)/);
 assert.ok(loop.indexOf('zx_releaseStreamClient(fd)') < loop.indexOf('TLinkAdaptiveStreamingSessionEndedForSession'));
 assert.match(fixtures[`${prefix}TSUnderTest.inc`], /uint8_t batch\[64 \* 188\]/);
 assert.match(source, /streamSeconds = \(frameStartNs - streamOrigin\) \/ 1e9/);
}
assert.match(adaptive, /gAdaptiveDecisionBusy.compare_exchange_strong/);
assert.match(adaptive, /session_changed/);
// Compile the actual socket adapter with only its POSIX syscall boundary doubled.
let socketAdapter = socket.slice(socket.indexOf('// Socket lifetime'), socket.lastIndexOf('#endif'));
for (const [call, replacement] of [['::send(', '::fixtureSend('], ['fcntl(', 'fixtureFcntl('], ['poll(', 'fixturePoll(']]) {
 assert.ok(socketAdapter.includes(call)); socketAdapter = socketAdapter.replaceAll(call, replacement);
}
fixtures['H264SocketUnderTest.inc'] = socketAdapter;
const oldRoot = 'static NSString *TLinkAdaptiveRoot(void) { return @"/var/mobile/Library/TLinkauto/adaptive-streaming"; }';
assert.ok(adaptive.includes(oldRoot));
fixtures['AdaptiveUnderTest.mm'] = '#import <Foundation/Foundation.h>\nextern NSString *TLinkAdaptiveFixtureRoot(void);\n' + adaptive.replace(oldRoot, 'static NSString *TLinkAdaptiveRoot(void) { return TLinkAdaptiveFixtureRoot(); }');
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot, 'tlink-h264-'));
function run(command, args) {
 const r = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 120000 });
 if (r.stdout) process.stdout.write(r.stdout); if (r.stderr) process.stderr.write(r.stderr);
 if (r.error) throw r.error; assert.equal(r.status, 0, `${command} failed (signal=${r.signal})`);
}
try {
 for (const [name, content] of Object.entries(fixtures)) await writeFile(join(temp, name), content);
 const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
 const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
 const binary = join(temp, windows ? 'h264-core.exe' : 'h264-core');
 const file = join(root, 'test/h264-safety-test.cpp');
 run(compiler, msvc ? ['/nologo','/std:c++14','/W4','/WX','/EHsc',`/I${temp}`, file, `/Fe${binary}`, `/Fo${join(temp,'core.obj')}`]
  : ['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-I',temp,file,'-o',binary]);
 run(binary, []);
 const adapterBinary = join(temp, windows ? 'h264-socket-adapter.exe' : 'h264-socket-adapter');
 const adapterFile = join(root, 'test/h264-socket-adapter-test.cpp');
 run(compiler, msvc ? ['/nologo','/std:c++14','/W4','/WX','/EHsc',`/I${temp}`,adapterFile,`/Fe${adapterBinary}`,`/Fo${join(temp,'adapter.obj')}`]
  : ['-std=c++11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-I',temp,adapterFile,'-o',adapterBinary]);
 run(adapterBinary, []);

 if (process.platform === 'darwin') {
  const runtime = join(temp,'h264-runtime');
  run(compiler,['-std=c++11','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-deprecated-declarations','-fobjc-arc',
   '-fsanitize=address,undefined','-fno-omit-frame-pointer','-framework','Foundation','-framework','CoreFoundation',
   '-I',temp,'-I',join(root,'shared'),join(root,'test/h264-runtime-test.mm'),join(temp,'AdaptiveUnderTest.mm'),'-o',runtime]);
  run(runtime,[temp]);
 } else console.log('macOS H264 socket/deadline/slot/table and actual adaptive Foundation integration added to both production workflows; not run on Windows.');
} finally { assert.equal(dirname(temp),tempRoot); assert.ok(basename(temp).startsWith('tlink-h264-')); await rm(temp,{recursive:true,force:true}); }
