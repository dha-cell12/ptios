import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const hash = source => createHash("sha256").update(source).digest("hex");
const specs = JSON.parse(readFileSync(new URL("./rootless-makefile-specs.json", import.meta.url), "utf8"));
const defaultLine = "TLINK_ROOTLESS_RUNTIME ?= 0\n";
const flag = " -DTLINK_ROOTLESS_RUNTIME=$(TLINK_ROOTLESS_RUNTIME)";

// Historical makefile guards describe the source before rootless was added.
// Reverse only its independently checked default/compile-flag additions; never
// accept arbitrary makefile edits or replace historical expected hashes.
export function restoreRootlessMakefile(source, file) {
  if (!source.includes("TLINK_ROOTLESS_RUNTIME")) return source;
  const spec = specs[file];
  assert.ok(spec, `unsupported rootless makefile: ${file}`);
  assert.equal(hash(source), spec.currentHash, `complete rootless ${file}`);
  assert.equal(source.split(defaultLine).length - 1, 1, `${file}: rootless default count`);
  assert.equal(source.split(flag).length - 1, spec.flagCount, `${file}: rootless compile flag count`);
  const before = source.replace(defaultLine, "").replaceAll(flag, "");
  assert.equal(hash(before), spec.beforeHash, `complete preceding rootless ${file}`);
  return before;
}
