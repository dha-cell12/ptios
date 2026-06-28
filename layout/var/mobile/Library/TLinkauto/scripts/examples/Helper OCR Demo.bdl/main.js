console.log("helper ocr demo started");
var runtime = device.runtimeInfo();
console.log("runtime", runtime);
var langs = device.ocrLanguages();
console.log("ocrLanguages", langs);
var frame = device.captureFrame({ gray: 1, bgra: 0, ttlMs: 1500 });
console.log("captureFrame", frame);
if (frame.ok && frame.id) {
  var result = device.ocrFrame(frame.id, { x: 0, y: 0, width: frame.width || 0, height: frame.height || 0, lang: "eng", psm: 6, maxAgeMs: 1500 });
  console.log("ocrFrame", result);
  console.log("releaseFrame", device.releaseFrame(frame.id));
}
device.toast("Helper OCR Demo completed", { type: 4, duration: 2 });
console.log("helper ocr demo completed");
