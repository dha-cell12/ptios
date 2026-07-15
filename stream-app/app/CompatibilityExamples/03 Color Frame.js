console.log('compat/color-frame start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('Color and frame test');
var color = report('pickColor', device.pickColor(10, 10));
var frame = report('captureFrame', device.captureFrame({ bgra: 1, gray: 1, ttlMs: 3000 }));
if (frame.ok) {
  report('framePickColor', device.framePickColor(frame.id, 10, 10, { maxAgeMs: 3000 }));
  report('framePickColors', device.framePickColors(frame.id, [[10, 10], [20, 20], [30, 30]], { maxAgeMs: 3000 }));
  if (color.ok) {
    report('frameIsColors', device.frameIsColors(frame.id, [[10, 10, color.red, color.green, color.blue]], { tolerance: 0, maxAgeMs: 3000 }));
  }
  report('frameFindColor', device.frameFindColor(frame.id, {
    x: 0, y: 0, width: frame.width, height: frame.height,
    redMin: 0, redMax: 255, greenMin: 0, greenMax: 255, blueMin: 0, blueMax: 255,
    skip: 16, maxAgeMs: 3000
  }));
  report('releaseFrame', device.releaseFrame(frame.id));
}
console.log('compat/color-frame finished');
