console.log('compat/file-handle start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('File handle compatibility test');
var file = device.openFile('storage/file-handle.txt', 'w+');
report('open', file);
if (file.ok) {
  report('write1', file.write('first line\n'));
  report('write2', file.write('second line\n'));
  report('tellAfterWrite', file.tell());
  report('seekStart', file.seek('set', 0));
  report('readLine', file.readLine());
  report('readRest', file.read('*a'));
  report('flush', file.flush());
  report('close', file.close());
  report('isClosed', file.isClosed());
}

var append = device.openFile('storage/file-handle.txt', 'a');
report('openAppend', append);
if (append.ok) {
  report('appendWrite', append.write('appended line\n'));
  report('appendClose', append.close());
}
report('finalText', device.readText('storage/file-handle.txt'));
console.log('compat/file-handle finished');
