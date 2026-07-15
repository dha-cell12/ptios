function logResult(name, value) {
  console.log(name + "=" + JSON.stringify(value));
  return value;
}

function ensureOk(name, result) {
  if (!result || !result.ok) {
    console.log(name + " failed: " + JSON.stringify(result));
    return false;
  }
  return true;
}

console.log("Rootfull compatibility smoke started");
device.toast("Rootfull compatibility smoke");
device.sleep(0.2);

var runtime = logResult("runtimeInfo", device.runtimeInfo());
var status = logResult("runTask97", device.runTask(97, ""));
var screen = logResult("screen", device.getScreenSize());
var color = logResult("pickColor", device.pickColor(10, 10));

var frame = logResult("captureFrame", device.captureFrame({ bgra: 1, ttlMs: 2000 }));
if (frame.ok) {
  logResult("framePickColors", device.framePickColors(frame.id, [[10, 10], [20, 20]], { maxAgeMs: 2000 }));
  if (color.ok) {
    logResult("frameIsColors", device.frameIsColors(frame.id, [[10, 10, color.red, color.green, color.blue]], { tolerance: 0, maxAgeMs: 2000 }));
  }
  logResult("releaseFrame", device.releaseFrame(frame.id));
}

var shot = logResult("screenshotTo", device.screenshotTo("_data/rootfull-compat-shot.png"));
var languages = logResult("ocrLanguages", device.ocrLanguages());

var statePath = "_data/rootfull-compat-state.json";
var storageWrite = logResult("writeJSON", device.writeJSON(statePath, {
  at: Date.now(),
  runtime: runtime,
  status: status,
  screen: screen,
  color: color,
  screenshot: shot,
  languages: languages
}));
ensureOk("writeJSON", storageWrite);
logResult("fileExists", device.fileExists(statePath));
logResult("readJSON", device.readJSON(statePath));

logResult("setClipboardText", device.setClipboardText("TLinkauto rootfull compat"));
logResult("getClipboardText", device.getClipboardText());
logResult("insertText", device.insertText("TLinkauto rootfull compat"));

var shell = logResult("runShell", device.runShell("echo rootfull-compat", 3));
if (!shell.ok) {
  console.log("runShell is expected to fail when shell.enabled is off");
}

logResult("frontMostAppId", device.frontMostAppId());
logResult("frontMostPid", device.frontMostPid());
logResult("appState", device.appState("com.apple.Preferences"));

device.toast("Rootfull compatibility smoke finished");
console.log("Rootfull compatibility smoke finished");
