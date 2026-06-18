import { ZxTouchWsClient } from '../ZxTouchWsClient';

export class ZxTouchDeviceSdk {
  private client: ZxTouchWsClient;

  constructor(wsBase: string, deviceId: string) {
    this.client = new ZxTouchWsClient(`${wsBase}/ios/${encodeURIComponent(deviceId)}/zxtouch`);
  }

  async waitOpen(timeoutMs = 1500) {
    await this.client.waitOpen(timeoutMs);
  }

  close() {
    this.client.close();
  }

  async tap(x: number, y: number, holdMs = 60) {
    await this.waitOpen();
    this.client.touch(1, 1, x, y);
    await sleep(holdMs);
    this.client.touch(0, 1, x, y);
  }

  async swipe(x1: number, y1: number, x2: number, y2: number, durationMs = 300) {
    await this.waitOpen();
    const steps = Math.max(2, Math.ceil(durationMs / 16));
    this.client.touch(1, 1, x1, y1);
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      this.client.tryTouchMove(1, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t);
      await sleep(durationMs / steps);
    }
    this.client.touch(0, 1, x2, y2);
  }

  async getScreenSize() {
    await this.waitOpen();
    return this.client.getScreenSize();
  }

  async request(task: number, ...args: Array<string | number>) {
    return this.client.request(task, ...args);
  }
}

export function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) return Promise.reject(new DOMException('Aborted', 'AbortError'));
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(new DOMException('Aborted', 'AbortError'));
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}
