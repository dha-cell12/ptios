console.log("helper ui rpc demo started");

var info = device.runtimeInfo();
console.log("runtime", info.runtimeLocation, "nativeRPC", info.nativeRPC);

var setClip = device.setClipboardText("TLinkauto helper RPC clipboard");
console.log("setClipboardText", setClip);

var clip = device.getClipboardText();
console.log("getClipboardText", clip);

var toast = device.toast("Helper UI RPC OK", { type: 4, duration: 2 });
console.log("toast", toast);

if (!setClip.ok || !clip.ok || !toast.ok) {
  throw new Error("helper UI RPC failed");
}

console.log("helper ui rpc demo completed");
