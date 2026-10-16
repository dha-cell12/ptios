import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (await readFile(join(root, "pccontrol/ScriptPlayer.xm"), "utf8")).replaceAll("\r\n", "\n");
const play = await readFile(join(root, "pccontrol/Play.xm"), "utf8");
const task = await readFile(join(root, "pccontrol/Task.xm"), "utf8");
assert.doesNotMatch(source, /CFRunLoopRun|CFRunLoopStop|NSTimer|scriptPlayForceStop|clearLegacyState|static .*isPlaying/);
assert.match(source, /dispatch_queue_create\("com.tlinkauto.playback", DISPATCH_QUEUE_SERIAL\)/);
assert.match(source, /_playback.reserve\(\)/);
assert.match(source, /_playback.beginFinish\(session.generation\)/);
assert.match(source, /finishRunHistoryForSession:session state:state error:error[\s\S]*_playback.finish\(session.generation\)/);
assert.match(source, /if \(file\) fclose\(file\)/);
assert.match(source, /processTaskWithContext\(bytes, length, NULL, session.taskContext\)/);
assert.match(source, /TLinkRootfullLicenseTaskAllowed\(TASK_USLEEP/);
assert.match(source, /dispatch_semaphore_signal\(session.wake\)/);
assert.match(source, /_indicatorGeneration != session.generation/);
assert.match(play, /playPath:[\s\S]*repeatTime:repeatTime interval:sleepBetweenRun speed:playSpeed/);
assert.doesNotMatch(play, /\[scriptPlayer setPath:|\[scriptPlayer setSpeed:/);
assert.match(task, /else if \(context.didInjectTouchPayload\) \{\s*context.didInjectTouchPayload\(eventData, eventDataLength\)/);
assert.match(task, /context.didInjectTouchPayload\(eventData \+ touchOffset, eventDataLength - touchOffset\)/);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-raw-playback-safety-"));
try {
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "raw-playback-safety-test.exe" : "raw-playback-safety-test");
  const testSource = join(root, "test/raw-playback-safety-test.cpp");
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
    const start = source.indexOf("// BEGIN playback session implementation");
    const end = source.indexOf("// END playback session implementation.", start);
    assert.ok(start >= 0 && end > start);
    await writeFile(join(temp, "PlaybackRuntimeUnderTest.inc"), source.slice(start, end));
    const runtime = join(temp, "playback-runtime-test");
    const compiled = spawnSync(compiler, ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-Wno-deprecated-declarations",
      "-fobjc-arc", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-framework", "Foundation", "-I", temp,
      join(root, "test/playback-runtime-test.mm"), join(root, "pccontrol/TLinkTaskContext.mm"), "-o", runtime],
      { cwd: root, encoding: "utf8" });
    if (compiled.stdout) process.stdout.write(compiled.stdout);
    if (compiled.stderr) process.stderr.write(compiled.stderr);
    if (compiled.error) throw compiled.error;
    assert.equal(compiled.status, 0, "playback runtime compilation failed");
    const run = spawnSync(runtime, [temp], { cwd: root, encoding: "utf8", timeout: 120000 });
    if (run.stdout) process.stdout.write(run.stdout);
    if (run.stderr) process.stderr.write(run.stderr);
    if (run.error) throw run.error;
    assert.equal(run.status, 0, "playback runtime failed");
  } else console.log("macOS playback dispatch/ARC integration tests require macOS; included in rootfull/roothide CI.");
} finally {
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-raw-playback-safety-"));
  await rm(temp, { recursive: true, force: true });
}
