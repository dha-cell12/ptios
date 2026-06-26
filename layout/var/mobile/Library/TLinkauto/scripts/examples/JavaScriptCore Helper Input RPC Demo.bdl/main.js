console.log("helper input rpc demo started");

var info = device.runtimeInfo();
console.log("runtimeLocation", info.runtimeLocation, "nativeRPC", info.nativeRPC);

var toast = device.toast("Helper input RPC demo", { type: 4, duration: 2 });
console.log("toast", toast);

var tap = device.tap(20, 20);
console.log("tap", tap);

sleep(200);

var swipe = device.swipe(20, 120, 120, 120, 150);
console.log("swipe", swipe);

if (!toast.ok || !tap.ok || !swipe.ok) {
  throw new Error("input RPC failed");
}

console.log("helper input rpc demo completed");
