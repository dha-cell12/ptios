const capability = device.uiTreeCapability();
console.log("UI Tree capability: " + JSON.stringify(capability));

if (!capability || capability.state !== "ready") {
  throw new Error("UI Tree is unavailable: " + JSON.stringify(capability));
}

const snapshot = device.uiTree({ visibleOnly: true, maxElements: 250 });
console.log("Foreground " + snapshot.bundle_id + " has " + snapshot.count + " visible AX elements");

// Change this selector to a stable label or accessibilityIdentifier in the
// foreground target application. This example is read-only by default.
const selector = { text: "Settings", match: "contains", visibleOnly: true };
const found = device.waitForElement(selector, {
  timeoutMs: 3000,
  intervalMs: 250,
  ignoreErrors: false
});
console.log("Selector result: " + JSON.stringify(found));

// Explicit action example:
// if (found.ok) device.tapElement({ text: "Settings", match: "exact", clickableOnly: true });
