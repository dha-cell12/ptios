import { buildIosStreamUrls } from './IosBridgeApi';
import { deriveBridgeBases } from '../bridgeBase';
import { IosStreamService } from './IosStreamService';
import type { UnifiedDevice } from '../deviceRegistry';

type GridStream = {
  canvas: HTMLCanvasElement;
  deviceId: string;
  stop: () => void;
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
    this.stop(device.id);

    if (device.capabilities?.includes('remote_wss')) {
      const parent = canvas.parentElement;
      if (!parent) return;
      const video = document.createElement('video');
      const workerCanvas = document.createElement('canvas');
      const latency = document.createElement('div');
      video.autoplay = true;
      video.muted = true;
      video.playsInline = true;
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = 'fill';
      workerCanvas.style.display = 'none';
      latency.style.display = 'none';
      canvas.style.display = 'none';
      parent.append(video, workerCanvas, latency);

      const service = new IosStreamService();
      service.mount({ canvas, workerCanvas, video, latencyOverlay: latency });
      const { wsBase, httpBase } = deriveBridgeBases(bridgeWsUrl);
      this.streams.set(device.id, {
        canvas,
        deviceId: device.id,
        stop: () => {
          service.unmount();
          video.remove();
          workerCanvas.remove();
          latency.remove();
        },
      });
      void service.start(device.id, wsBase, httpBase, 'rtc');
      return;
    }

    if (!('transferControlToOffscreen' in canvas) || !('Worker' in window)) return;

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
        { type: 'start', url: urls.h264Worker, feedbackUrl: urls.tlinkauto, port: 7004, canvas: offscreen },
        [offscreen]
      );
      this.streams.set(device.id, {
        canvas,
        deviceId: device.id,
        stop: () => {
          try { worker.postMessage({ type: 'stop' }); } catch {}
          try { worker.terminate(); } catch {}
        },
      });
    } catch (e) {
      console.error('[ios-grid] failed to spawn worker', device.id, e);
    }
  }

  stop(deviceId: string) {
    const stream = this.streams.get(deviceId);
    if (!stream) return;
    stream.stop();
    this.streams.delete(deviceId);
  }

  stopAll() {
    for (const id of Array.from(this.streams.keys())) this.stop(id);
  }

  has(deviceId: string) {
    return this.streams.has(deviceId);
  }
}
