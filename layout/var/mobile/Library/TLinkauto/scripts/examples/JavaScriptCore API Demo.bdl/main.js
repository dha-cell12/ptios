device.toast("JSC demo started", { type: 3, duration: 2, position: 0 });
sleep(700);
console.log("runtime", device.runtimeInfo());

var size = device.getScreenSize();
console.log("screen", size);
device.toast("Screen " + size.width + "x" + size.height, { type: 3, duration: 2, position: 0 });
sleep(700);

var centerX = Math.floor(size.width / 2);
var centerY = Math.floor(size.height / 2);
var centerColor = device.pickColor(centerX, centerY);
console.log("center color", centerColor);
device.toast("Center RGB " + centerColor.red + "," + centerColor.green + "," + centerColor.blue, { type: 3, duration: 2, position: 0 });
sleep(700);

var frame = device.captureFrame({ gray: 1, bgra: 1, ttlMs: 1000 });
console.log("frame", frame);
device.toast(frame.ok ? "Frame captured #" + frame.id : "Frame failed", { type: frame.ok ? 4 : 1, duration: 2, position: 0 });
sleep(700);

if (frame.ok) {
  var frameColor = device.framePickColor(frame.id, centerX, centerY, { maxAgeMs: 1000 });
  console.log("frame center color", frameColor);
  device.toast("Frame RGB " + frameColor.red + "," + frameColor.green + "," + frameColor.blue, { type: 4, duration: 2, position: 0 });
  sleep(700);
  console.log("frame colors", device.framePickColors(frame.id, [
    { x: centerX, y: centerY },
    [Math.max(0, centerX - 20), centerY]
  ], { maxAgeMs: 1000 }));
  console.log("release frame", device.releaseFrame(frame.id));
}

var app = device.frontMostAppId();
var orientation = device.orientation();
var pid = device.frontMostPid();
var appInfo = device.appInfo(app.bundleId || "com.apple.springboard");
var ocrLangs = device.ocrLanguages();
var paths = device.botPath();
var info = device.info();
var battery = device.batteryInfo();
console.log("front app", app);
console.log("orientation", orientation);
console.log("front pid", pid);
console.log("app info", appInfo);
console.log("bot path", paths);
console.log("device info", info);
console.log("battery", battery);
device.toast("Front app: " + (app.bundleId || "unknown") + " pid " + (pid.pid || 0), { type: 3, duration: 2, position: 0 });
sleep(700);
device.toast("Bot path ready: " + !!paths.botPath, { type: paths.ok ? 3 : 1, duration: 2, position: 0 });
sleep(700);
device.toast("Device: " + (info.model || "unknown") + " battery " + Math.round(battery.level || 0) + "%", { type: info.ok ? 3 : 1, duration: 2, position: 0 });
sleep(700);
console.log("ocr languages", ocrLangs);
device.toast("OCR langs: " + ((ocrLangs.languages || []).join(",") || "none"), { type: ocrLangs.ok ? 3 : 1, duration: 3, position: 0 });
sleep(700);
device.toast("JSC demo done: " + (app.bundleId || "unknown"), { type: 4, duration: 3, position: 0 });
