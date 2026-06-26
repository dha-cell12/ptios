console.log("helper rpc smoke demo started");

var runtime = device.runtimeInfo();
console.log("runtime", runtime.runtimeLocation, "nativeRPC", runtime.nativeRPC);

var size = device.getScreenSize();
console.log("screen", size);

var app = device.frontMostAppId();
console.log("front app", app);

var pid = device.frontMostPid();
console.log("front pid", pid);

var orientation = device.orientation();
console.log("orientation", orientation);

var dev = device.info();
console.log("device info", dev);

var battery = device.batteryInfo();
console.log("battery", battery);

var wifi = device.wifi();
console.log("wifi", wifi);

var paths = device.botPath();
console.log("botPath", paths);

var toast = device.toast("Helper RPC smoke OK", { type: 4, duration: 2 });
console.log("toast", toast);

if (!size.ok || !app.ok || !pid.ok || !orientation.ok || !dev.ok || !battery.ok || !toast.ok) {
  throw new Error("helper RPC smoke failed");
}

console.log("helper rpc smoke demo completed");
