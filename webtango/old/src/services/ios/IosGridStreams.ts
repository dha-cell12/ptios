import { buildIosStreamUrls } from './IosBridgeApi';
import type { UnifiedDevice } from '../deviceRegistry';

type GridStream = {
  worker: Worker;
  canvas: HTMLCanvasElement;
  deviceId: string;
};

// Manages per-device offscreen-canvas worker streams in the Screen View grid.
// One worker per visible iOS device; we tear them all down when the grid hides
// or when the user opens a focused modal so the single iOS stream slot stays free.
export class IosGridStreams {
  private streams = new Map<string, GridStream>();
  private suspended = new Set<string>();

  isSuspended(deviceId: string) {
    return this.suspended.has(deviceId);
  }

  suspend(deviceId: string) {
    this.suspended.add(deviceId);
    this.stop(deviceId);
  }

  resume(deviceId: string) {
    this.suspended.delete(deviceId);
  }

  start(device: UnifiedDevice, canvas: HTMLCanvasElement, bridgeWsUrl: string) {
    if (this.suspended.has(device.id)) return;
    if (!('transferControlToOffscreen' in canvas) || !('Worker' in window)) return;

    this.stop(device.id);

    const urls = buildIosStreamUrls(bridgeWsUrl, device.id);
    try {
      const offscreen = canvas.transferControlToOffscreen();
      const worker = new Worker(new URL('../../IosH264Worker.ts', import.meta.url), { type: 'module' });
      worker.onmessage = (event) => {
        const data = event.data;
        if (data?.type === 'start-failed') {
          console.error('[ios-grid] start failed', device.id, data.reason);
        }
        if (data?.type === 'decoder-error') {
          console.error('[ios-grid] decoder error', device.id, data.error);
        }
      };
      worker.postMessage(
        { type: 'start', url: urls.h264Worker, canvas: offscreen },
        [offscreen]
      );
      this.streams.set(device.id, { worker, canvas, deviceId: device.id });
    } catch (e) {
      console.error('[ios-grid] failed to spawn worker', device.id, e);
    }
  }

  stop(deviceId: string) {
    const stream = this.streams.get(deviceId);
    if (!stream) return;
    try { stream.worker.postMessage({ type: 'stop' }); } catch {}
    try { stream.worker.terminate(); } catch {}
    this.streams.delete(deviceId);
  }

  stopAll() {
    for (const id of Array.from(this.streams.keys())) this.stop(id);
  }

  has(deviceId: string) {
    return this.streams.has(deviceId);
  }
}
