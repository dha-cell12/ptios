import './style.css';
import { Adb, AdbServerClient } from '@yume-chan/adb';
import { AdbScrcpyClient, AdbScrcpyOptions3_1 } from '@yume-chan/adb-scrcpy';
import { AndroidMotionEventAction, ScrcpyVideoCodecId } from '@yume-chan/scrcpy';
import { WebCodecsVideoDecoder, BitmapVideoFrameRenderer } from '@yume-chan/scrcpy-decoder-webcodecs';
import { AdbWebSocketConnector } from './AdbWebSocketConnector';

const statusBadge = document.getElementById('status') as HTMLSpanElement;
const endpointInput = document.getElementById('endpoint') as HTMLInputElement;
const connectButton = document.getElementById('connect') as HTMLButtonElement;
const disconnectButton = document.getElementById('disconnect') as HTMLButtonElement;
const deviceInfo = document.getElementById('device-info') as HTMLPreElement;
const mirrorStatus = document.getElementById('mirror-status') as HTMLSpanElement;
const shellOutput = document.getElementById('shell-output') as HTMLTextAreaElement;
const shellCommand = document.getElementById('shell-command') as HTMLInputElement;
const shellRun = document.getElementById('run-shell') as HTMLButtonElement;
const canvas = document.getElementById('screen') as HTMLCanvasElement;
const deviceSelect = document.getElementById('device-select') as HTMLSelectElement;
const devicesContainer = document.getElementById('devices-container') as HTMLDivElement;
const deviceCardTemplate = document.getElementById('device-card-template') as HTMLTemplateElement;

// Device connection interface
interface DeviceConnection {
  serial: string;
  adb: Adb;
  scrcpyClient?: AdbScrcpyClient<AdbScrcpyOptions3_1<any>>;
  canvas: HTMLCanvasElement;
  statusElement: HTMLElement;
  cardElement: HTMLElement;
}

let serverClient: AdbServerClient | undefined;
const connectedDevices = new Map<string, DeviceConnection>();
let availableDevices: AdbServerClient.Device[] = [];

function setStatus(text: string, connected = false) {
  statusBadge.textContent = text;
  statusBadge.classList.toggle('connected', connected);
  connectButton.disabled = connected;
  disconnectButton.disabled = !connected;
  shellRun.disabled = !connected;
}

function appendShell(text: string) {
  shellOutput.value += `${text}\n`;
  shellOutput.scrollTop = shellOutput.scrollHeight;
}

function populateDeviceList(devices: AdbServerClient.Device[]) {
  deviceSelect.innerHTML = '';
  devices.forEach(device => {
    const option = document.createElement('option');
    option.value = device.serial;
    option.textContent = `${device.serial}${device.product ? ` (${device.product})` : ''}`;
    deviceSelect.appendChild(option);
  });
  deviceSelect.disabled = false;
}

async function connectToDevice(device: AdbServerClient.Device) {
  try {
    console.log('Connecting to device:', device.serial);

    // Create Adb instance for the device
    adb = await serverClient!.createAdb({ serial: device.serial });

    // Get device properties
    const model = await adb.getProp('ro.product.model');
    const version = await adb.getProp('ro.build.version.release');
    deviceInfo.textContent = `Device: ${device.serial}\nModel: ${model}\nAndroid: ${version}`;

    setStatus('Connected', true);
    mirrorStatus.textContent = 'Ready';
    await startMirror();
  } catch (error) {
    console.error('Device connection error:', error);
    setStatus('Failed', false);
    deviceInfo.textContent = (error as Error)?.message ?? String(error);
  }
}

async function connect() {
  try {
    const url = endpointInput.value.trim();
    setStatus('Connecting…', false);

    // Create WebSocket connector
    const connector = new AdbWebSocketConnector(url);

    // Create ADB Server Client
    serverClient = new AdbServerClient(connector);

    // Get list of devices
    console.log('Getting device list...');
    const devices = await serverClient.getDevices();
    console.log('Devices:', devices);

    if (devices.length === 0) {
      throw new Error('No devices connected');
    }

    availableDevices = devices;

    if (devices.length === 1) {
      // Auto-select single device
      console.log('Single device found, auto-connecting...');
      populateDeviceList(devices);
      deviceSelect.value = devices[0].serial;
      await connectToDevice(devices[0]);
    } else {
      // Multiple devices - show selector
      console.log(`${devices.length} devices found, please select one`);
      populateDeviceList(devices);
      setStatus('Select device', false);
      deviceInfo.textContent = 'Please select a device from the dropdown';
    }
  } catch (error) {
    console.error(error);
    setStatus('Failed', false);
    deviceInfo.textContent = (error as Error)?.message ?? String(error);
  }
}

async function startMirror() {
  if (!adb) return;
  mirrorStatus.textContent = 'Starting scrcpy…';

  const SCRCPY_VERSION = '3.1';
  const serverPath = `/data/local/tmp/scrcpy-server.jar`;

  try {
    // --- ROBUST AUTO-PUSH LOGIC ---
    let needPush = true;

    // 1. Verify existence and size
    try {
      mirrorStatus.textContent = 'Verifying server…';
      const socket = await adb.createSocket(`shell:stat -c %s ${serverPath}`);
      const decoder = new TextDecoder();
      let output = '';
      for await (const chunk of socket.readable) {
        output += decoder.decode(chunk);
      }

      const size = parseInt(output.trim());
      console.log(`Server file size on device: ${size} bytes`);

      // v3.1 is ~90KB. If < 20KB, it's invalid.
      if (!isNaN(size) && size > 20000) {
        needPush = false;
        console.log('Server exists and looks valid. Skipping push.');
      } else {
        console.log('Server missing or invalid size. Needs push.');
      }
    } catch (e) {
      console.warn('Verification failed, assuming push needed.', e);
    }

    // 2. Push if needed - using base64 + shell to bypass sync protocol issues
    console.log('[AUTO-PUSH] needPush =', needPush);
    if (needPush) {
      mirrorStatus.textContent = 'Downloading server…';
      const serverUrl = `/scrcpy-server-v${SCRCPY_VERSION}`;
      console.log('[AUTO-PUSH] Fetching from:', serverUrl);
      const response = await fetch(serverUrl);
      console.log('[AUTO-PUSH] Fetch response:', response.status, response.statusText);
      if (!response.ok) {
        throw new Error(`Failed to load scrcpy server from ${serverUrl}: ${response.status} ${response.statusText}`);
      }

      const blob = await response.blob();
      const buffer = await blob.arrayBuffer();
      const serverData = new Uint8Array(buffer);
      console.log(`Loaded server binary: ${serverData.byteLength} bytes`);

      mirrorStatus.textContent = 'Pushing server…';
      console.log('[AUTO-PUSH] Using Shell Push (sync protocol unstable over WebSocket)...');

      // Encode to base64
      let binaryString = '';
      for (let i = 0; i < serverData.length; i++) {
        binaryString += String.fromCharCode(serverData[i]);
      }
      const base64Full = btoa(binaryString);
      console.log(`[AUTO-PUSH] Encoded: ${base64Full.length} chars`);

      // Stream via shell
      const cmd = `base64 -d > ${serverPath} && chmod 644 ${serverPath}`;
      const socket = await adb.createSocket(`shell:${cmd}`);
      const writer = socket.writable.getWriter();

      try {
        const CHUNK_SIZE = 32 * 1024;
        const encoder = new TextEncoder();

        for (let i = 0; i < base64Full.length; i += CHUNK_SIZE) {
          await writer.write(encoder.encode(base64Full.substring(i, i + CHUNK_SIZE)));
          if (i % (CHUNK_SIZE * 10) === 0) {
            mirrorStatus.textContent = `Pushing… ${Math.round((i / base64Full.length) * 100)}%`;
          }
        }
        await writer.close();
      } catch (err) {
        console.error('[AUTO-PUSH] Error:', err);
        throw err;
      }

      // Wait for completion
      const decoder = new TextDecoder();
      for await (const chunk of socket.readable) {
        const output = decoder.decode(chunk);
        if (output.trim()) console.warn('[AUTO-PUSH]:', output);
      }

      console.log('✅ Server pushed');
    } else {
      console.log('Skipping push - server already exists and is valid');
    }
    // -----------------------------

    // Configure scrcpy options (v3.1)
    const options = new AdbScrcpyOptions3_1({
      maxSize: 960,
      videoBitRate: 4000000,
      videoCodec: "h264",
      maxFps: 60,
      audio: false,
      sendDeviceMeta: false,
      sendDummyByte: false,
      tunnelForward: true, // Must use forward tunnel
      control: true, // Enable control
    });

    // Start scrcpy server with retry logic
    console.log('Starting scrcpy server...');
    mirrorStatus.textContent = 'Starting server…';

    let lastError: Error | undefined;
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        console.log(`Attempt ${attempt}/5: Starting scrcpy...`);
        scrcpyClient = await AdbScrcpyClient.start(adb, serverPath, options);
        console.log('✅ Scrcpy started successfully');
        break; // Success!
      } catch (error) {
        lastError = error as Error;
        console.warn(`Attempt ${attempt} failed:`, error);

        if (attempt < 5) {
          const delay = attempt * 1000;
          console.log(`Waiting ${delay}ms before retry...`);
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }

    if (!scrcpyClient) {
      throw lastError || new Error('Failed to start scrcpy after 5 attempts');
    }

    // Get video stream
    const videoStream = await scrcpyClient.videoStream;
    if (!videoStream) {
      throw new Error('No video stream available');
    }

    console.log('Video stream metadata:', videoStream.metadata);
    mirrorStatus.textContent = 'Initializing decoder…';

    // Set canvas size
    canvas.width = videoStream.metadata.width || 1080;
    canvas.height = videoStream.metadata.height || 1920;

    // Create renderer and decoder
    const renderer = new BitmapVideoFrameRenderer(canvas);
    const decoder = new WebCodecsVideoDecoder({
      codec: ScrcpyVideoCodecId.H264,
      renderer: renderer,
    });

    // Pipe stream
    videoStream.stream.pipeTo(decoder.writable).catch((error) => {
      console.error('Video stream error:', error);
      mirrorStatus.textContent = 'Stream error: ' + (error as Error).message;
    });

    // --- DEVICE CONTROL ---
    if (scrcpyClient.controller) {
      console.log('Controller available, adding event listeners...');
      const controller = scrcpyClient.controller;

      // Mouse/Touch Handling
      let isMouseDown = false;
      const sendTouch = (type: number, e: MouseEvent) => {
        if (!videoStream.metadata.width || !videoStream.metadata.height) return;

        const rect = canvas.getBoundingClientRect();
        // Calculate coordinates in canvas space
        const x = (e.clientX - rect.left) * (canvas.width / rect.width);
        const y = (e.clientY - rect.top) * (canvas.height / rect.height);

        // Scrcpy expects coordinates in device space
        const deviceX = Math.max(0, Math.min(x, videoStream.metadata.width));
        const deviceY = Math.max(0, Math.min(y, videoStream.metadata.height));

        // ACTION_DOWN = 0, ACTION_UP = 1, ACTION_MOVE = 2
        controller.injectTouch({
          action: type as AndroidMotionEventAction,
          pointerId: BigInt(0), // Single pointer for mouse
          pointerX: deviceX,
          pointerY: deviceY,
          videoWidth: videoStream.metadata.width!,
          videoHeight: videoStream.metadata.height!,
          pressure: type === 0 || type === 2 ? 1 : 0,
          actionButton: 1, // Primary button
          buttons: e.buttons, // Current button state
        });
      };

      canvas.addEventListener('mousedown', (e) => {
        isMouseDown = true;
        sendTouch(0, e); // ACTION_DOWN
      });

      canvas.addEventListener('mousemove', (e) => {
        if (!isMouseDown) return;
        sendTouch(2, e); // ACTION_MOVE
      });

      canvas.addEventListener('mouseup', (e) => {
        if (!isMouseDown) return;
        sendTouch(1, e); // ACTION_UP
        isMouseDown = false;
      });

      canvas.addEventListener('mouseleave', (e) => {
        if (isMouseDown) {
          sendTouch(1, e); // ACTION_UP
          isMouseDown = false;
        }
      });
    }

    mirrorStatus.textContent = 'Streaming';
    console.log('✅ Video streaming started');
  } catch (error) {
    console.error('Mirror error:', error);
    mirrorStatus.textContent = (error as Error)?.message ?? String(error);
  }
}

async function disconnect() {
  if (animationFrame !== undefined) {
    cancelAnimationFrame(animationFrame);
  }
  animationFrame = undefined;
  scrcpyClient?.close();
  scrcpyClient = undefined;
  await adb?.close?.();
  serverClient = undefined;
  adb = undefined;
  setStatus('Disconnected', false);
  deviceInfo.textContent = 'No device connected.';
  mirrorStatus.textContent = 'Idle';
}

async function runShell() {
  if (!adb) return;
  const command = shellCommand.value.trim();
  if (!command) return;

  const socket = await adb.createSocket(`shell:${command}`);
  const decoder = new TextDecoder();
  for await (const chunk of socket.readable) {
    appendShell(decoder.decode(chunk));
  }
}

connectButton.addEventListener('click', connect);
disconnectButton.addEventListener('click', disconnect);
shellRun.addEventListener('click', runShell);

// Handle device selection change
deviceSelect.addEventListener('change', async () => {
  const selectedSerial = deviceSelect.value;
  if (!selectedSerial || !serverClient) return;

  const device = availableDevices.find(d => d.serial === selectedSerial);
  if (device) {
    await connectToDevice(device);
  }
});

const defaultHost = window.location.origin.replace(/\/?$/, '');
endpointInput.value = `${defaultHost.replace('8000', '15037')}/bridge/`;
setStatus('Disconnected', false);
