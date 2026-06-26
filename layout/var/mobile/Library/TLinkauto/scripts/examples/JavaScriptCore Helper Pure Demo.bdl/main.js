console.log("helper pure demo started");

var helper = require("./helper-module");
var info = device.runtimeInfo();

console.log("runtimeLocation", info.runtimeLocation);
console.log("helperInstanceId", info.helperInstanceId);
console.log("square(7)", helper.square(7));

sleep(100);

console.log("helper pure demo completed", info.runtimeLocation);
