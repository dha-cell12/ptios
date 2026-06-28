console.log("helper frame color demo started");

var runtime = device.runtimeInfo();
console.log("runtime", runtime.runtimeLocation, "nativeRPC", runtime.nativeRPC);

var size = device.getScreenSize();
console.log("screen", size);
if (!size.width || !size.height) throw new Error("invalid screen size");

var frame = device.captureFrame({ gray: 1, bgra: 1, ttlMs: 1500 });
console.log("captureFrame", frame);
if (!frame.ok || !frame.id) throw new Error("captureFrame failed: " + JSON.stringify(frame));

var x = Math.floor(size.width / 2);
var y = Math.floor(size.height / 2);
var color = device.framePickColor(frame.id, x, y, { coord: "pixel", maxAgeMs: 1500 });
console.log("center color", color);
if (!color.ok) throw new Error("framePickColor failed: " + JSON.stringify(color));

var released = device.releaseFrame(frame.id);
console.log("releaseFrame", released);
if (!released.ok) throw new Error("releaseFrame failed: " + JSON.stringify(released));

var cleanup = device.releaseAllFrames();
console.log("releaseAllFrames scoped", cleanup);

var msg = "Frame Color OK rgb=(" + color.red + "," + color.green + "," + color.blue + ")";
var toast = device.toast(msg, { type: 4, duration: 2 });
console.log("toast", toast);
console.log("helper frame color demo completed");
