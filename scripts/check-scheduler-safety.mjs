import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (await readFile(join(root, "pccontrol/Scheduler.xm"), "utf8")).replaceAll("\r\n", "\n");
const transaction = await readFile(join(root, "shared/TLinkAutoLaunchConfig.h"), "utf8");
assert.doesNotMatch(source, /NSTimer|scheduledTimerWithTimeInterval/);
assert.match(source, /dispatch_queue_create\("com.tlinkauto.scheduler", DISPATCH_QUEUE_SERIAL\)/);
assert.match(source, /dispatch_get_specific\(&schedulerQueueKey\)\) operation\(\);\s*else dispatch_sync\(queue, operation\)/);
assert.match(source, /dispatch_source_create\(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, schedulerQueue\(\)\)/);
assert.match(source, /schedulerPerformSync\(\^\{ timerRegistry.remove\(timerName\); \}\)/);
assert.match(source, /timerRegistry.fire\(name, generation, !canStartScriptPlaying\(\)/);
const callback = source.slice(source.indexOf("static void schedulerTimerFired"), source.indexOf("NSString* setTimerFromRawData"));
assert.ok(callback.indexOf("!canStartScriptPlaying()") < callback.indexOf("TLinkSchedulerScriptLaunchAllowed"));
assert.ok(callback.indexOf("TLinkSchedulerScriptLaunchAllowed") < callback.indexOf("playScript((UInt8*)"));
assert.match(source, /schedulerPerformSync\(\^\{[\s\S]*dispatch_resume\(source\);\s*\}\);\s*if \(error\) \*error = result;/);
assert.ok(transaction.indexOf("TLinkAutoLaunchFileLock lock(") < transaction.indexOf("dataWithContentsOfFile:path"));
assert.match(transaction, /flock\(fd_, LOCK_EX\)/);
assert.match(transaction, /stringByAppendingString:@"\.lock"/);
assert.match(transaction, /writeToFile:path options:NSDataWritingAtomic/);
assert.match(transaction, /NSFileReadNoSuchFileError/);
for (const file of ["pccontrol/Scheduler.xm", "stream-app/streamd/POCSocketServer.mm", "stream-app/app/BootScriptViewController.mm"]) {
  const text = await readFile(join(root, file), "utf8");
  assert.match(text, /TLinkAutoLaunchSetEntry\(/, `${file} must use the common transaction`);
  assert.doesNotMatch(text, /writeToFile:(?:kTLinkAutoLaunchConfigPath|autoLaunchFilePath\(\))/);
}
const player = await readFile(join(root, "pccontrol/ScriptPlayer.xm"), "utf8");
assert.match(player, /TLinkPlaybackState _playback/);
assert.match(player, /canStartScheduledScript[\s\S]*os_unfair_lock_lock\(&_playerLock\)[\s\S]*BOOL allowed = !_playback.busy\(\)/);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-scheduler-safety-"));
try {
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "scheduler-safety-test.exe" : "scheduler-safety-test");
  const testSource = join(root, "test/scheduler-safety-test.cpp");
  const args = msvc
    ? ["/nologo", "/std:c++14", "/W4", "/WX", "/EHsc", `/I${temp}`, testSource, `/Fe${binary}`, `/Fo${join(temp, "test.obj")}`]
    : ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-pthread", "-I", temp, testSource, "-o", binary];
  for (const [command, argv] of [[compiler, args], [binary, []]]) {
    const result = spawnSync(command, argv, { cwd: root, encoding: "utf8" });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `${command} failed (signal=${result.signal})`);
  }
  if (process.platform === "darwin") {
    const schedulerSource = source.slice(source.indexOf("struct TLinkSchedulerTimer {"), source.indexOf("// Scheduler license diagnostics.")) +
      source.slice(source.indexOf("// Registry mutation, timer callbacks"), source.indexOf("NSString* keepAwakeFromRawData"));
    await writeFile(join(temp, "SchedulerRuntimeUnderTest.inc"), schedulerSource);
    for (const name of ["scheduler-runtime", "autolaunch-transaction"]) {
      const executable = join(temp, name);
      const result = spawnSync(compiler, ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-fobjc-arc",
        "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-framework", "Foundation", "-I", temp,
        join(root, `test/${name}-test.mm`), "-o", executable], { cwd: root, encoding: "utf8" });
      if (result.stdout) process.stdout.write(result.stdout);
      if (result.stderr) process.stderr.write(result.stderr);
      if (result.error) throw result.error;
      assert.equal(result.status, 0, `${name} compilation failed`);
      const run = spawnSync(executable, [temp], { cwd: root, encoding: "utf8", timeout: 120000 });
      if (run.stdout) process.stdout.write(run.stdout);
      if (run.stderr) process.stderr.write(run.stderr);
      if (run.error) throw run.error;
      assert.equal(run.status, 0, `${name} runtime failed`);
    }
  } else {
    console.log("macOS dispatch/ARC and Foundation transaction tests require macOS; included in CI.");
  }
} finally {
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-scheduler-safety-"));
  await rm(temp, { recursive: true, force: true });
}
