console.log('compat/app-process-shell start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('App process and shell test');
var bundleId = 'com.tlinkauto.streamcontrol';
report('appInfo', device.appInfo(bundleId));
report('appState', device.appState(bundleId));
report('appPid', device.appPid(bundleId));
report('appPaths', device.appPaths(bundleId));
report('frontMostAppId', device.frontMostAppId());
report('frontMostPid', device.frontMostPid());
report('shell', device.runShell('echo tlinkauto-shell-ok', 5));
console.log('A shell_disabled_by_settings result is expected when Enable Shell Task is off.');
console.log('compat/app-process-shell finished');
