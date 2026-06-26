console.log("helper native rpc demo started");

var info = device.runtimeInfo();
console.log("runtimeLocation", info.runtimeLocation);
console.log("nativeRPC", info.nativeRPC);

var result = device.toast("Helper native RPC toast", { type: 0, duration: 2 });
console.log("toast result", result);

if (!result || !result.ok) {
  throw new Error("native RPC toast failed: " + JSON.stringify(result));
}

console.log("helper native rpc demo completed");
