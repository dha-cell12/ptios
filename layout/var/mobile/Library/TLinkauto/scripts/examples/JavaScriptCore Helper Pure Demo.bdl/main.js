console.log("helper pure demo started");

var helper = require("./helper-module");
var info = device.runtimeInfo();

console.log("runtimeLocation", info.runtimeLocation);
console.log("helperInstanceId", info.helperInstanceId);
console.log("square(7)", helper.square(7));

sleep(100);

if (info.runtimeLocation !== "helper-process-prototype") {
  throw new Error("expected helper runtime");
}

console.log("helper pure demo completed");
