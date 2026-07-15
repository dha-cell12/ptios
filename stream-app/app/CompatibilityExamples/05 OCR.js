console.log('compat/ocr start');
function report(name, value) {
  console.log(name + '=' + JSON.stringify(value));
  return value;
}

device.toast('Tesseract OCR test');
report('ocrLanguages', device.ocrLanguages());
var screen = device.getScreenSize();
var width = screen.ok ? Math.min(900, screen.width) : 600;
var height = screen.ok ? Math.min(500, screen.height) : 400;
report('ocr', device.ocr({ x: 0, y: 0, width: width, height: height, lang: 'eng', oem: 1, psm: 6, scaleUp: 2, ttlMs: 3000 }));
console.log('compat/ocr finished');
