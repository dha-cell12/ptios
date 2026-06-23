console.log("js-start");
sleep(100);
console.log("sleep-ok");
const size = device.getScreenSize();
console.log(JSON.stringify(size));
device.tap(100, 100);
