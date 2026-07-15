console.log('compat/screenshot-image start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('Screenshot and image test');
var shot = report('screenshot', device.screenshot());
if (shot.ok) {
  var image = report('openImage', device.openImage(shot.path));
  var frame = report('captureFrame', device.captureFrame({ bgra: 1, ttlMs: 4000 }));
  if (image.ok && frame.ok) {
    report('findImageInFrame', device.findImageInFrame(frame.id, image.id, {
      x: 0, y: 0, width: frame.width, height: frame.height,
      acceptable: 0.95, pixelSkip: 0, maxAgeMs: 4000
    }));
  }
  if (frame && frame.ok) report('releaseFrame', device.releaseFrame(frame.id));
  if (image && image.ok) report('releaseImage', device.releaseImage(image.id));
}
console.log('compat/screenshot-image finished');
