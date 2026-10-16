import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (await readFile(join(root, "pccontrol/TouchIndicator/TouchIndicatorWindow.xm"), "utf8")).replaceAll("\r\n", "\n");
const header = await readFile(join(root, "pccontrol/TouchIndicator/TouchIndicatorWindow.h"), "utf8");
assert.doesNotMatch(source, /index\s*-\s*1|NSError\s*\*\s*\*.*dispatch_async/);
assert.doesNotMatch(source, /dispatch_async|CFRunLoopRun\(|CFRunLoopStop\(|isShowing|showAlertBox\(/);
assert.match(source, /if \(\[NSThread isMainThread\]\) operation\(\);\s*else dispatch_sync\(dispatch_get_main_queue\(\), operation\)/);
assert.match(source, /__block NSError \*result = nil;\s*zx_indicatorPerformOnMain\(\^\{ result = zx_indicatorStartOnMain\(\); \}\);\s*if \(error\) \*error = result;/);
assert.match(source, /indicatorState != TLinkIndicatorStopped[\s\S]*indicatorState = TLinkIndicatorStarting/);
assert.match(source, /if \(failure\) \{\s*zx_indicatorStopOnMain\(\);\s*return failure;/);
assert.match(source, /zx_indicatorStopClientOnMain\(\);\s*\[touchIndicatorWindow hide\];\s*touchIndicatorWindow = nil/);
assert.match(source, /rawIndex < 0 \|\| rawIndex >= kTLinkTouchMaxFingerCount/);
assert.match(header, /Window methods are main-thread-only/);
for (const method of ["hideIndicator:", "showIndicator:", "moveIndicator:"]) {
  const start = source.indexOf(`- (void)${method}`);
  const end = source.indexOf("\n}\n", start);
  assert.ok(start >= 0 && end > start);
  const body = source.slice(start, end);
  assert.match(body, /if \(!zx_indicatorValidFingerIndex\(index\)/);
  assert.match(body, /touchIndicatorViewList\[index\]/);
  assert.ok(body.indexOf("zx_indicatorValidFingerIndex(index)") < body.indexOf("touchIndicatorViewList[index]"));
}

const globalsStart = source.indexOf("enum TLinkIndicatorState {");
const globalsEnd = source.indexOf("static TouchIndicatorWindow *", globalsStart);
const coreStart = source.indexOf("static bool zx_indicatorValidFingerIndex(");
const coreEnd = source.indexOf("// END indicator HID ownership core.", coreStart);
assert.ok(globalsStart >= 0 && globalsEnd > globalsStart && coreStart >= 0 && coreEnd > coreStart);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-indicator-safety-"));
try {
  await writeFile(join(temp, "IndicatorGlobalsUnderTest.inc"), source.slice(globalsStart, globalsEnd));
  await writeFile(join(temp, "IndicatorCoreUnderTest.inc"), source.slice(coreStart, coreEnd));
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "indicator-safety-test.exe" : "indicator-safety-test");
  const testSource = join(root, "test/touch-indicator-safety-test.cpp");
  const args = msvc
    ? ["/nologo", "/std:c++14", "/W4", "/WX", "/EHsc", `/I${temp}`, testSource, `/Fe${binary}`, `/Fo${join(temp, "test.obj")}`]
    : ["-std=c++14", "-Wall", "-Wextra", "-Werror", "-fsanitize=address,undefined", "-fno-omit-frame-pointer", "-I", temp, testSource, "-o", binary];
  for (const [command, argv] of [[compiler, args], [binary, []]]) {
    const result = spawnSync(command, argv, { cwd: root, encoding: "utf8" });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `${command} failed (signal=${result.signal})`);
  }
} finally {
  assert.equal(dirname(temp), tempRoot);
  assert.ok(basename(temp).startsWith("tlink-indicator-safety-"));
  await rm(temp, { recursive: true, force: true });
}
