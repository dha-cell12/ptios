console.log('compat/license-heartbeat start');

var file = device.openFile('storage/license-heartbeat.txt', 'a+');
console.log('open=' + JSON.stringify(file));
if (file.ok) {
  console.log('write-start=' + JSON.stringify(file.write('started\n')));
  console.log('flush-start=' + JSON.stringify(file.flush()));
}

device.toast('License heartbeat running for 60 seconds');
for (var second = 1; second <= 60; second++) {
  var sleepResult = device.sleep(1);
  console.log('heartbeat=' + second + ' sleep=' + JSON.stringify(sleepResult));
  if (device.shouldStop()) {
    console.log('license heartbeat observed stopRequested');
    break;
  }
  if (file.ok) {
    console.log('write=' + JSON.stringify(file.write('heartbeat ' + second + '\n')));
    console.log('flush=' + JSON.stringify(file.flush()));
  }
}

if (file.ok) {
  console.log('close=' + JSON.stringify(file.close()));
}
console.log('compat/license-heartbeat finished stop=' + device.shouldStop());
