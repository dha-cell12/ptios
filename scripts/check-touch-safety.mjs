import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = async (path) => (await readFile(join(root, path), "utf8")).replaceAll("\r\n", "\n");
const [touch, task, ipc, bridge, trollTouch, trollServer] = await Promise.all([
  read("pccontrol/Touch.xm"), read("pccontrol/Task.xm"),
  read("pccontrol/IPCMessagePort.xm"), read("pccontrol/jsruntime/TLinkInProcessNativeBridge.mm"),
  read("stream-app/streamd/TouchInjector.mm"), read("stream-app/streamd/POCSocketServer.mm"),
]);
// Compile the production injection functions themselves, not a second implementation.
const start = touch.indexOf("static IOHIDEventRef generateChildEventTouchDown(");
const end = touch.indexOf("\n/**\nPost the parent event", start);
assert.ok(start >= 0 && end > start, "Cannot find production touch injection functions");
const injection = touch.slice(start, end);
const trollChildrenStart = trollTouch.indexOf("static IOHIDEventRef POCChildDown(");
const trollChildrenEnd = trollTouch.indexOf("\n// ---------------------------------------------------------------------------\n// Dispatch", trollChildrenStart);
const trollPerformStart = trollTouch.indexOf("bool POCPerformTouchFromRawData(");
const trollPerformEnd = trollTouch.indexOf("\n// ---------------------------------------------------------------------------\n// Public API", trollPerformStart);
assert.ok(trollChildrenStart >= 0 && trollChildrenEnd > trollChildrenStart && trollPerformStart >= 0 && trollPerformEnd > trollPerformStart);
const trollInjection = trollTouch.slice(trollChildrenStart, trollChildrenEnd) + trollTouch.slice(trollPerformStart, trollPerformEnd);
assert.match(trollServer, /touch_ack_bad_payload/);
assert.match(trollServer, /POCPerformTouchFromRawData[\s\S]*lengthOfBytesUsingEncoding:NSUTF8StringEncoding/);
assert.match(injection, /bool performTouchFrame\(const TLinkTouchPoint \*points, int touchCount\)/);
assert.match(injection, /TLinkValidateTouchFrame\(points, touchCount\)/);
assert.match(injection, /bool performTouchFromRawData\(const UInt8 \*eventData, size_t eventDataLength\)/);
assert.match(task, /actualLength < 2/);
assert.doesNotMatch(task, /processTaskWithContext\(buff, SIZE_MAX/);
assert.match(task, /performTouchFromRawData\(eventData, eventDataLength\)/);
assert.match(task, /performTouchFromRawData\(eventData \+ touchOffset, eventDataLength - touchOffset\)/);
assert.doesNotMatch(task, /strstr\(\(char \*\)eventData, ";;"\)/);
assert.match(ipc, /processTaskWithContext[\s\S]*lengthOfBytesUsingEncoding:NSUTF8StringEncoding/);
assert.match(bridge, /processTaskWithContext[\s\S]*\[payloadData length\] - 1/);

const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-touch-safety-"));
try {
  const helpersStart = task.indexOf("static int zx_clampTouchCoord(");
  const helpersEnd = task.indexOf("static NSArray<NSString *> *zx_splitTaskParts", helpersStart);
  assert.ok(helpersStart >= 0 && helpersEnd > helpersStart);
  await writeFile(join(temp, "TaskTouchHelpersUnderTest.inc"), task.slice(helpersStart, helpersEnd));
  for (const [runtime, code, troll] of [["rootfull", injection, false], ["TrollStore", trollInjection, true]]) {
    await writeFile(join(temp, "TouchInjectionUnderTest.inc"), code);
    console.log(`Testing ${runtime} production touch injection`);
    const windows = process.platform === "win32";
    const compiler = process.env.CXX || (windows ? "cl" : "clang++");
    const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
    const binary = join(temp, windows ? "touch-safety-test.exe" : "touch-safety-test");
    const source = join(root, "test/touch-safety-test.cpp");
    const defines = troll ? [msvc ? "/DTLINK_TEST_TROLLSTORE=1" : "-DTLINK_TEST_TROLLSTORE=1"] : [];
    const args = msvc
      ? [...defines, "/nologo", "/std:c++14", "/W4", "/WX", "/EHsc", `/I${temp}`, source, `/Fe${binary}`, `/Fo${join(temp, "test.obj")}`]
      : [...defines, "-std=c++14", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I", temp, source, "-o", binary];
    for (const [command, argv] of [[compiler, args], [binary, []]]) {
      const result = spawnSync(command, argv, { cwd: root, encoding: "utf8" });
      if (result.stdout) process.stdout.write(result.stdout);
      if (result.stderr) process.stderr.write(result.stderr);
      if (result.error) throw result.error;
      assert.equal(result.status, 0, `${command} failed (signal=${result.signal})`);
    }
  }
} finally {
  // Only delete the exact directory created above, contained in the OS temporary root.
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-touch-safety-"));
  await rm(temp, { recursive: true, force: true });
}
