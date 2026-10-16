import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = async path => (await readFile(join(root, path), "utf8")).replaceAll("\r\n", "\n");
const [source, task, tweak] = await Promise.all(["pccontrol/Record.xm", "pccontrol/Task.xm", "pccontrol/Tweak.xm"].map(read));
assert.doesNotMatch(source, /NSFileHandle|writeData:|lastEventTimeStampForRecording|recordRunLoop|kIOHIDEventFieldDigitizerRange/);
assert.match(source, /IOHIDEventSystemClientUnscheduleWithRunLoop\(_client, _ownerLoop, kCFRunLoopDefaultMode\)/);
assert.match(source, /CFRelease\(_client\)/);
assert.match(source, /CFRunLoopPerformBlock\(_ownerLoop/);
assert.match(source, /if \(wait && \[NSThread currentThread\] == _ownerThread\)/);

assert.match(source, /_writerGeneration != generation \|\| _fd < 0/);
assert.match(source, /O_WRONLY \| O_CREAT \| O_EXCL \| O_CLOEXEC/);
assert.match(source, /dispatch_sync\(_writer,[\s\S]*fsync\(self->_fd\)[\s\S]*close\(self->_fd\)[\s\S]*_buffer.finish/);
assert.match(source, /const uintptr_t generation = recorder->_buffer.generation\(\);[\s\S]*zx_stopRecordingGeneration\(recorder, generation\)/);
assert.match(task, /NSString \*path = startRecordingWithError\(&err\)/);
assert.match(task, /stopRecordingWithError\(&err\)/);
assert.match(tweak, /stopRecordingAsync\(\^\(NSError \*error\)/);
const callback = source.slice(source.indexOf('- (void)acceptEvent:', source.indexOf('@implementation TLinkRecorder')), source.indexOf('\n@end', source.indexOf('@implementation TLinkRecorder')));
assert.ok(callback.length > 100);
assert.doesNotMatch(callback, /NSLog|NSString|NSData|write\(|writeData:|dispatch_async|CFAbsoluteTimeGetCurrent/);
assert.match(callback, /TLinkRecordEvent records\[20\]/);
const start = source.indexOf('// BEGIN recorder owner implementation');
const end = source.indexOf('// END recorder owner implementation.');
assert.ok(start >= 0 && end > start);
const tempRoot = resolve(tmpdir()), temp = await mkdtemp(join(tempRoot, 'tlink-recorder-'));
function run(command, args) {
  const r = spawnSync(command, args, { cwd: root, encoding: 'utf8', timeout: 120000 });
  if (r.stdout) process.stdout.write(r.stdout); if (r.stderr) process.stderr.write(r.stderr);
  if (r.error) throw r.error;
  assert.equal(r.status, 0, `${command} failed (signal=${r.signal})`);
}
try {
  await writeFile(join(temp, 'RecorderUnderTest.inc'), source.slice(start, end));
  const taskStart = task.indexOf('    else if (taskType == TASK_TOUCH_RECORDING_START)');
  const taskEnd = task.indexOf('    else if (taskType == TASK_TOUCH_RECORDING_STOP)', taskStart);
  assert.ok(taskStart >= 0 && taskEnd > taskStart);
  const taskBranch = task.slice(taskStart, taskEnd);
  const taskBody = taskBranch.slice(taskBranch.indexOf('@autoreleasepool'), taskBranch.lastIndexOf('\n    }'));
  await writeFile(join(temp, 'RecorderStartTaskUnderTest.inc'), taskBody);

  const windows = process.platform === 'win32', compiler = process.env.CXX || (windows ? 'cl' : 'clang++');
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? 'recorder-test.exe' : 'recorder-test');
  const file = join(root, 'test/recorder-safety-test.cpp');
  run(compiler, msvc ? ['/nologo', '/std:c++14', '/W4', '/WX', '/EHsc', file, `/Fe${binary}`, `/Fo${join(temp, 'core.obj')}`]
    : ['-std=c++14', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread', file, '-o', binary]);
  run(binary, []);
  if (process.platform === 'darwin') {
    const runtime = join(temp, 'recorder-runtime-test');
    run(compiler, ['-std=c++14', '-Wall', '-Wextra', '-Werror', '-Wno-deprecated-declarations', '-fobjc-arc',
      '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-framework', 'Foundation', '-framework', 'CoreFoundation',
      '-I', temp, join(root, 'test/recorder-runtime-test.mm'), '-o', runtime]);
    run(runtime, [temp]);
  } else console.log('macOS actual recorder owner/dispatch/HID/file integration is included in CI; not run on this host.');
} finally {
  assert.equal(dirname(temp), tempRoot); assert.ok(basename(temp).startsWith('tlink-recorder-'));
  await rm(temp, { recursive: true, force: true });
}
