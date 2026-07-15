console.log('compat/clipboard-keyboard start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('Clipboard background test');
report('setClipboardText', device.setClipboardText('hello from compatibility suite'));
report('getClipboardText', device.getClipboardText());
console.log('insertText and pasteFromClipboard are available for scripts that run while a target text field is focused.');
console.log('compat/clipboard-keyboard finished');
