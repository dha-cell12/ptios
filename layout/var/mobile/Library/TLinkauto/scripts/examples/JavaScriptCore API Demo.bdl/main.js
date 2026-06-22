console.log("runtime", device.runtimeInfo());

var size = device.getScreenSize();
console.log("screen", size);

var centerX = Math.floor(size.width / 2);
var centerY = Math.floor(size.height / 2);
console.log("center color", device.pickColor(centerX, centerY));

var frame = device.captureFrame({ gray: 1, bgra: 1, ttlMs: 1000 });
console.log("frame", frame);

if (frame.ok) {
  console.log("frame center color", device.framePickColor(frame.id, centerX, centerY, { maxAgeMs: 1000 }));
  console.log("frame colors", device.framePickColors(frame.id, [
    { x: centerX, y: centerY },
    [Math.max(0, centerX - 20), centerY]
  ], { maxAgeMs: 1000 }));
  console.log("release frame", device.releaseFrame(frame.id));
}

console.log("front app", device.frontMostAppId());
console.log("orientation", device.orientation());
