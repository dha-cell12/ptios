console.log("clipboard image demo started");

var imagePath = "/var/mobile/Library/TLinkauto/clipboard-image-demo.png";

device.toast("Capturing screenshot for clipboard image demo", { type: 3, duration: 2 });
sleep(700);

var shot = device.screenshotTo(imagePath);
console.log("screenshotTo", shot);
TLinkauto.ensureOk(shot, "screenshot failed");

var copied = device.setClipboardImage(imagePath);
console.log("setClipboardImage", copied);
TLinkauto.ensureOk(copied, "setClipboardImage failed");

device.toast("Image copied. Open Notes/Messages and paste.", { type: 4, duration: 4 });
console.log("clipboard image demo completed", imagePath);
