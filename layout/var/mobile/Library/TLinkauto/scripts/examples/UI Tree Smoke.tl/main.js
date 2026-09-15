const capability = device.uiTreeCapability();
console.log("UI Tree capability: " + JSON.stringify(capability));
if (!capability || capability.state !== "ready") {
  throw new Error("UI Tree unavailable");
}

const snapshot = device.uiTree({ visibleOnly: true, maxElements: 250 });
console.log(JSON.stringify({
  bundle_id: snapshot.bundle_id,
  pid: snapshot.pid,
  count: snapshot.count,
  duration_ms: snapshot.duration_ms,
  partial: snapshot.partial
}));
