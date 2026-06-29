console.log("helper storage demo started");

var runtime = device.runtimeInfo();
console.log("runtime", runtime.runtimeLocation, "nativeRPC", runtime.nativeRPC);

var textPath = "data/helper-storage-demo.txt";
var jsonPath = "data/helper-storage-demo.json";

var writeText = device.writeText(textPath, "hello from helper storage");
console.log("writeText", writeText);
if (!writeText.ok) throw new Error("writeText failed: " + JSON.stringify(writeText));

var readText = device.readText(textPath);
console.log("readText", readText);
if (!readText.ok || readText.text !== "hello from helper storage") throw new Error("readText mismatch");

var writeJSON = device.writeJSON(jsonPath, { ok: true, name: "helper-storage-demo", count: 2 });
console.log("writeJSON", writeJSON);
if (!writeJSON.ok) throw new Error("writeJSON failed: " + JSON.stringify(writeJSON));

var readJSON = device.readJSON(jsonPath);
console.log("readJSON", readJSON);
if (!readJSON.ok || !readJSON.value || readJSON.value.name !== "helper-storage-demo") throw new Error("readJSON mismatch");

var exists = device.fileExists(jsonPath);
console.log("fileExists", exists);
if (!exists.ok || !exists.exists) throw new Error("fileExists failed");

var deleteText = device.deleteFile(textPath);
var deleteJSON = device.deleteFile(jsonPath);
console.log("deleteText", deleteText);
console.log("deleteJSON", deleteJSON);

var toast = device.toast("Helper Storage Demo OK", { type: 4, duration: 2 });
console.log("toast", toast);
console.log("helper storage demo completed");

console.log('[HELPER_TEST_PASS] Helper Storage Demo');
