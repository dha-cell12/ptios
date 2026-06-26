console.log("helper diagnostics demo started");

var helper = require("./helper-module");
var info = device.runtimeInfo();

console.log("runtimeLocation", info.runtimeLocation);
console.log("helperInstanceId", info.helperInstanceId);
console.log("square(7)", helper.square(7));

if (info.runtimeLocation === "in-process-prototype" && device.toast) {
  device.toast("Helper daemon reachable; execution is in-process", { type: 0, duration: 2 });
}

sleep(100);

console.log("helper diagnostics demo completed", info.runtimeLocation);
