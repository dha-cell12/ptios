import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = (await readFile(join(root, "pccontrol/Screen.xm"), "utf8")).replaceAll("\r\n", "\n");
assert.doesNotMatch(source, /CGColorSpaceRelease|IOSurfaceUnLock/);
assert.match(source, /return CGImageRetain\(gKeepImage\)/);
assert.match(source, /zx_captureGeometry\(screenSize.width, screenSize.height, screen.scale, rotateIPad, &geometry\)/);
for (const [key, member] of [["AllocSize", "allocationSize"], ["BytesPerRow", "bytesPerRow"], ["Width", "width"], ["Height", "height"]]) {
  assert.ok(source.includes(`@"IOSurface${key}": @(geometry.${member})`));
}
assert.match(source, /return zx_captureSurfaceImage\(\(__bridge CFDictionaryRef\)properties, rotateIPad\)/);
const coreStart = source.indexOf("struct TLinkCaptureGeometry {");
const coreEnd = source.indexOf("// END capture ownership core.", coreStart);
assert.ok(coreStart >= 0 && coreEnd > coreStart);
const tempRoot = resolve(tmpdir());
const temp = await mkdtemp(join(tempRoot, "tlink-capture-safety-"));
try {
  await writeFile(join(temp, "CaptureCoreUnderTest.inc"), source.slice(coreStart, coreEnd));
  const windows = process.platform === "win32";
  const compiler = process.env.CXX || (windows ? "cl" : "clang++");
  const msvc = /^(cl|cl\.exe)$/i.test(basename(compiler));
  const binary = join(temp, windows ? "capture-safety-test.exe" : "capture-safety-test");
  const testSource = join(root, "test/capture-safety-test.cpp");
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
  assert.ok(basename(temp).startsWith("tlink-capture-safety-"));
  await rm(temp, { recursive: true, force: true });
}
