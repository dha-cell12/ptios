import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFile(resolve(root, path), "utf8");
const fixture = JSON.parse(await read("test/fixtures/ocr-wire-contract-v1.json"));

assert.equal(fixture.contractVersion, 1);
assert.equal(fixture.lineEnding, "\r\n");
assert.equal(fixture.delimiter, ";;");

function decodeLegacyResponse(raw) {
  const normalized = raw.replace(/\r?\n$/, "");
  const parts = normalized.split(";;");
  return {
    ok: normalized.startsWith("0"),
    parts: parts.slice(1),
  };
}

const task27 = decodeLegacyResponse(fixture.task27.recognizeSuccess);
assert.equal(task27.ok, true);
assert.deepEqual(
  task27.parts.filter(Boolean).map((observation) => {
    const fields = observation.split(",,");
    assert.equal(fields.length, 5, "task 27 observations must remain five fields");
    return {
      text: fields[0],
      x: fields[1],
      y: fields[2],
      width: fields[3],
      height: fields[4],
    };
  }),
  fixture.task27.recognizeExpected,
);
assert.ok(
  !fixture.task27.recognizeSuccess.includes("engine="),
  "task 27 must not gain delimiter-separated metadata; it breaks legacy observation parsers",
);

const task27Languages = decodeLegacyResponse(fixture.task27.languagesSuccess);
assert.deepEqual(task27Languages.parts, ["en-US", "fr-FR", "de-DE"]);
assert.equal(decodeLegacyResponse(fixture.task27.error).ok, false);

const task91 = decodeLegacyResponse(fixture.task91.ocrSuccess);
assert.equal(task91.ok, true);
assert.ok(task91.parts.length >= 7, "task 91 success must retain its first seven fields");
assert.deepEqual(
  {
    text: Buffer.from(task91.parts[0], "base64").toString("utf8"),
    confidence: Number(task91.parts[1]),
    frameAgeMs: Number(task91.parts[2]),
    ocrMs: Number(task91.parts[3]),
    preprocessMs: Number(task91.parts[4]),
    totalMs: Number(task91.parts[5]),
    initSource: task91.parts[6],
  },
  fixture.task91.ocrExpected,
);
const task91Languages = decodeLegacyResponse(fixture.task91.languagesSuccess);
assert.equal(task91Languages.parts[0], "check_langs");
assert.equal(Buffer.from(task91Languages.parts[1], "base64").toString("utf8"), "eng,vie");
assert.equal(decodeLegacyResponse(fixture.task91.error).ok, false);

const [
  trollServer,
  trollScriptBridge,
  rootfullServer,
  rootfullVisionTask,
  rootfullTesseractTask,
  rootfullJSBridge,
  pythonClient,
  collector,
  baselineDoc,
] = await Promise.all([
  read("stream-app/streamd/POCSocketServer.mm"),
  read("stream-app/streamd/POCSocketServer.mm"),
  read("tlinkauto-binary/SocketServer.mm"),
  read("pccontrol/Task.xm"),
  read("pccontrol/TesseractOCRTask.mm"),
  read("pccontrol/jsruntime/TLinkInProcessNativeBridge.mm"),
  read("webtango/tlinkauto/client.py"),
  read("scripts/Collect-TLinkOCRBaseline.ps1"),
  read("docs/ocr-p0-baseline.md"),
]);

assert.match(trollServer, /if \(taskType == 27\)[\s\S]*?TLinkHandleVisionOCR\(body\)/);
assert.match(trollServer, /if \(taskType == 91\)[\s\S]*?TLinkHandleTesseractOCRCompat\(body\)/);
assert.match(trollServer, /ocr_worker_timeout timeout_ms=20000/);
assert.match(trollServer, /return TLinkSuccess\(\[NSString stringWithFormat:@"%@;;%.2f;;%llu;;%.3f;;%.3f;;%.3f;;tesseract_init_source=%@"/);

for (const [key, value] of Object.entries(fixture.task97.trollstoreRequiredAdditiveFields)) {
  assert.ok(
    baselineDoc.includes(`${key}=${value}`),
    `the historical P0 baseline document is missing ${key}=${value}`,
  );
}
for (const [key, value] of Object.entries(fixture.task97.rootfullRequiredAdditiveFields)) {
  assert.ok(
    rootfullServer.includes(`${key}=${value}`),
    `rootfull task 97 is missing the P0 OCR baseline field ${key}=${value}`,
  );
}

assert.match(trollScriptBridge, /TLinkScriptTaskResult\(weakSession, 91, body\)/);
assert.match(rootfullVisionTask, /taskType == TASK_TEXT_RECOGNIZER/);
assert.match(rootfullTesseractTask, /tesseract\.maximumRecognitionTime = 3\.0/);
assert.match(rootfullJSBridge, /TASK_OCR_TESSERACT_REGION/);
assert.match(pythonClient, /single_string_info = raw_info\.split\(",,"\)/);
assert.match(collector, /\[switch\]\$RunVision/);
assert.match(collector, /\$visionTask = "271;;\$rect/);
assert.match(collector, /\$tesseractTask = "91\$frameId/);
assert.match(collector, /\$probes\.task97_postflight = Invoke-TLinkTask -Task "97"/);
assert.match(baselineDoc, /task `27` and task `91` remain byte-compatible/i);
assert.match(baselineDoc, /-RunVision/);

console.log("OCR P0 baseline OK: legacy task 27/91 fixtures and historical capability baseline frozen");
