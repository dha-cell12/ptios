console.log('compat/runtime-storage start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('Runtime and storage test');
report('runtimeInfo', device.runtimeInfo());
report('screen', device.getScreenSize());
report('battery', device.batteryInfo());
report('rootDir', device.rootDir());
report('currentDir', device.currentDir());
report('botPath', device.botPath());

report('writeText', device.writeText('storage/compat.txt', 'tlinkauto-storage-ok'));
report('readText', device.readText('storage/compat.txt'));
report('fileExists', device.fileExists('storage/compat.txt'));
report('writeJSON', device.writeJSON('storage/compat.json', { ok: true, at: Date.now() }));
report('readJSON', device.readJSON('storage/compat.json'));
console.log('compat/runtime-storage finished');
