import type { Adb } from '@yume-chan/adb';
import { AdbScrcpyClient, AdbScrcpyOptions3_1 } from '@yume-chan/adb-scrcpy';
import { ScrcpyVideoCodecId } from '@yume-chan/scrcpy';
import { WebCodecsVideoDecoder, BitmapVideoFrameRenderer } from '@yume-chan/scrcpy-decoder-webcodecs';
import { ReadableStream, type MaybeConsumable } from '@yume-chan/stream-extra';
import { CanvasDrawRegistry } from '../canvas/CanvasDrawRegistry';
import { getScrcpyServerBinary } from './ScrcpyServerBinary';
import { retryWithBackoff } from './AdbBridge';

export type ScrcpyMirrorSession = {
  serial: string;
  hiddenCanvas: HTMLCanvasElement;
  width: number;
  height: number;
  scrcpyClient: AdbScrcpyClient<AdbScrcpyOptions3_1<any>>;
  decoder: WebCodecsVideoDecoder;
  renderer: BitmapVideoFrameRenderer;
  controller: any;
  videoStream: any;
  stop: () => void;
};

export type ScrcpyMirrorOptions = {
  maxSize?: number;
  videoBitRate?: number;
  maxFps?: number;
};

const REMOTE_SERVER_PATH = '/data/local/tmp/scrcpy-server.jar';
const syncDisabledForDevice = new Set<string>();
let syncGloballyDisabled = false;

async function withTimeout<T>(promise: Promise<T>, label: string, timeoutMs = 5000): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timeout after ${timeoutMs}ms`)), timeoutMs)
    ),
  ]);
}

async function checkServerExists(adb: Adb): Promise<boolean> {
  try {
    const socket = await withTimeout(
      adb.createSocket(`shell:test -f ${REMOTE_SERVER_PATH} && echo 1 || echo 0`),
      'check-exists',
      2000
    );
    const decoder = new TextDecoder();
    let output = '';
    for await (const chunk of socket.readable) {
      output += decoder.decode(chunk);
    }
    return output.trim() === '1';
  } catch {
    return false;
  }
}

async function checkServerSize(adb: Adb): Promise<number | undefined> {
  try {
    const socket = await withTimeout(
      adb.createSocket(`shell:wc -c < ${REMOTE_SERVER_PATH} 2>/dev/null`),
      'size-check',
      2000
    );
    const decoder = new TextDecoder();
    let output = '';
    for await (const chunk of socket.readable) {
      output += decoder.decode(chunk);
    }
    const n = parseInt(output.trim(), 10);
    return Number.isFinite(n) ? n : undefined;
  } catch {
    return undefined;
  }
}

async function pushServerSync(adb: Adb, binary: Uint8Array): Promise<boolean> {
  const sync = await adb.sync();
  try {
    const stream = new ReadableStream<MaybeConsumable<Uint8Array>>({
      start(controller) {
        controller.enqueue(binary);
        controller.close();
      },
    });
    const syncTimeout = Math.max(3000, Math.ceil(binary.length / 30000) * 1000);
    await withTimeout(
      sync.write({ filename: REMOTE_SERVER_PATH, file: stream, permission: 0o644 }),
      'sync-write',
      syncTimeout
    );
    return await checkServerExists(adb);
  } finally {
    await sync.dispose();
  }
}

async function pushServerBase64(adb: Adb, binary: Uint8Array): Promise<void> {
  const base64Data = btoa(String.fromCharCode(...binary));
  const socket = await adb.createSocket(
    `shell:base64 -d > ${REMOTE_SERVER_PATH} && chmod 644 ${REMOTE_SERVER_PATH}`
  );
  const writer = socket.writable.getWriter();
  const encoder = new TextEncoder();
  const chunkSize = 65536;
  for (let i = 0; i < base64Data.length; i += chunkSize) {
    await writer.write(encoder.encode(base64Data.substring(i, i + chunkSize)));
  }
  await writer.close();
  const decoder = new TextDecoder();
  for await (const chunk of socket.readable) {
    const out = decoder.decode(chunk).trim();
    if (out) console.log(`[scrcpy-mirror] base64 push: ${out}`);
  }
}

export async function ensureScrcpyServerPushed(adb: Adb, serial: string): Promise<void> {
  const binary = await getScrcpyServerBinary();
  const exists = await checkServerExists(adb);
  let needsPush = !exists;
  if (exists) {
    const size = await checkServerSize(adb);
    needsPush = size !== binary.length;
  }
  if (!needsPush) return;

  let pushed = false;
  if (!syncDisabledForDevice.has(serial) && !syncGloballyDisabled) {
    try {
      pushed = await pushServerSync(adb, binary);
      if (pushed) console.log(`[scrcpy-mirror] sync push ok for ${serial}`);
    } catch (e) {
      console.warn(`[scrcpy-mirror] sync push failed for ${serial}, falling back to base64`, e);
      syncDisabledForDevice.add(serial);
      syncGloballyDisabled = true;
    }
  }
  if (!pushed) {
    await pushServerBase64(adb, binary);
    const verified = await checkServerExists(adb);
    if (!verified) throw new Error('Failed to push scrcpy-server via base64 fallback');
  }
}

export async function startScrcpyMirror(
  adb: Adb,
  serial: string,
  options: ScrcpyMirrorOptions = {}
): Promise<ScrcpyMirrorSession> {
  await ensureScrcpyServerPushed(adb, serial);

  const scrcpyOptions = new AdbScrcpyOptions3_1({
    maxSize: options.maxSize ?? 640,
    videoBitRate: options.videoBitRate ?? 1_000_000,
    videoCodec: 'h264',
    maxFps: options.maxFps ?? 24,
    audio: false,
    control: true,
    sendDeviceMeta: false,
    sendDummyByte: true,
    tunnelForward: true,
    clipboardAutosync: true,
  } as any);

  const scrcpyClient = await retryWithBackoff(
    () => AdbScrcpyClient.start(adb, REMOTE_SERVER_PATH, scrcpyOptions),
    2,
    1000,
    `${serial}-scrcpy-start`
  );

  const videoStream = await scrcpyClient.videoStream;
  if (!videoStream) throw new Error('scrcpy did not produce a video stream');
  const width = videoStream.metadata.width ?? 720;
  const height = videoStream.metadata.height ?? 1280;

  const hiddenCanvas = document.createElement('canvas');
  hiddenCanvas.width = width;
  hiddenCanvas.height = height;

  const renderer = new BitmapVideoFrameRenderer(hiddenCanvas);
  const decoder = new WebCodecsVideoDecoder({
    codec: ScrcpyVideoCodecId.H264,
    renderer,
  });

  videoStream.stream.pipeTo(decoder.writable).catch((e: any) => {
    if (e && e.name !== 'ExactReadableEndedError') {
      console.warn(`[scrcpy-mirror] stream error for ${serial}`, e);
    }
  });

  const getSize = () => ({
    width: videoStream.metadata.width ?? hiddenCanvas.width,
    height: videoStream.metadata.height ?? hiddenCanvas.height,
  });
  CanvasDrawRegistry.registerSource(serial, hiddenCanvas, getSize);

  const controller = scrcpyClient.controller;

  const stop = () => {
    try { CanvasDrawRegistry.unregisterSource(serial); } catch {}
    try { scrcpyClient.close(); } catch {}
  };

  return {
    serial,
    hiddenCanvas,
    width,
    height,
    scrcpyClient,
    decoder,
    renderer,
    controller,
    videoStream,
    stop,
  };
}

export function resetScrcpyPushState() {
  syncDisabledForDevice.clear();
  syncGloballyDisabled = false;
}
