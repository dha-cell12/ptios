console.log("helper full safe smoke started");
var runtime = device.runtimeInfo();
console.log("runtime", runtime);
var size = device.getScreenSize();
console.log("screen", size);
console.log("front app", device.frontMostAppId());
console.log("front pid", device.frontMostPid());
console.log("orientation", device.orientation());
console.log("device info", device.info());
console.log("battery", device.batteryInfo());
var jsonPath = "data/full-safe-smoke.json";
console.log("writeJSON", device.writeJSON(jsonPath, { ok: true, width: size.width || 0, height: size.height || 0 }));
console.log("readJSON", device.readJSON(jsonPath));
console.log("deleteFile", device.deleteFile(jsonPath));
var frame = device.captureFrame({ gray: 1, bgra: 1, ttlMs: 1500 });
console.log("frame", frame);
if (frame.ok && frame.id) {
  var x = Math.floor((size.width || frame.width || 1) / 2);
  var y = Math.floor((size.height || frame.height || 1) / 2);
  console.log("color", device.framePickColor(frame.id, x, y, { coord: "pixel", maxAgeMs: 1500 }));
  console.log("releaseFrame", device.releaseFrame(frame.id));
}
console.log("cleanup", device.releaseAllFrames());
console.log("ocrLanguages", device.ocrLanguages());
device.toast("Helper Full Safe Smoke completed", { type: 4, duration: 2 });
console.log("helper full safe smoke completed");

console.log('[HELPER_TEST_PASS] Helper Full Safe Smoke Demo');
