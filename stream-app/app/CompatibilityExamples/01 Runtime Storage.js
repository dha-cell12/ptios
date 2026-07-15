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

var file = device.openFile('storage/compat-handle.txt', 'w+');
report('openFile', file);
if (file.ok) {
  report('fileWrite1', file.write('line one\n'));
  report('fileWrite2', file.write('line two\n'));
  report('fileTellAfterWrite', file.tell());
  report('fileSeekStart', file.seek('set', 0));
  report('fileReadLine', file.readLine());
  report('fileReadRest', file.read('*a'));
  report('fileFlush', file.flush());
  report('fileClose', file.close());
  report('fileIsClosed', file.isClosed());
}
console.log('compat/runtime-storage finished');
