import { TLinkautoWsClient } from '../../TLinkautoWsClient';
import { buildIosStreamUrls } from './IosBridgeApi';

export type IosControlMode = 'persistent' | 'ephemeral';

export type IosControlOptions = {
  mode?: IosControlMode;
  ephemeralCloseDelayMs?: number;
};

// Wraps the TLinkauto WS client with the persistent/ephemeral lifecycle
// previously baked into main.ts. ephemeral mode opens lazily per gesture and
// closes itself shortly after pointerup to free the single iOS control slot.
export class IosControlChannel {
  private bridgeWsUrl: string;
  private deviceId: string;
  private mode: IosControlMode;
  private ephemeralCloseDelayMs: number;
  private client: TLinkautoWsClient | undefined;
  private closeTimer: number | undefined;
  private screenSize: { width: number; height: number } | undefined;

  constructor(bridgeWsUrl: string, deviceId: string, options: IosControlOptions = {}) {
    this.bridgeWsUrl = bridgeWsUrl;
    this.deviceId = deviceId;
    this.mode = options.mode ?? 'persistent';
    this.ephemeralCloseDelayMs = options.ephemeralCloseDelayMs ?? 500;
  }

  getScreenSize() {
    return this.screenSize;
  }

  setScreenSize(size: { width: number; height: number }) {
    this.screenSize = size;
  }

  async ensureOpen(timeoutMs = 800): Promise<boolean> {
    if (this.closeTimer !== undefined) {
      window.clearTimeout(this.closeTimer);
      this.closeTimer = undefined;
    }
    if (this.client && this.client.isOpen() && !this.client.isStale()) return true;
    try {
      try { this.client?.close(); } catch {}
      const urls = buildIosStreamUrls(this.bridgeWsUrl, this.deviceId);
      this.client = new TLinkautoWsClient(urls.tlinkauto);
      await this.client.waitOpen(timeoutMs);
      if (!this.screenSize) {
        try {
          const size = await this.client.getScreenSize();
          if (size) this.screenSize = size;
        } catch {}
      }
      return true;
    } catch (e) {
      console.error('[ios-control] open failed', this.mode, e);
      return false;
    }
  }

  scheduleEphemeralClose(delayMs?: number) {
    if (this.mode !== 'ephemeral') return;
    const delay = delayMs ?? this.ephemeralCloseDelayMs;
    if (this.closeTimer !== undefined) window.clearTimeout(this.closeTimer);
    this.closeTimer = window.setTimeout(() => {
      this.closeTimer = undefined;
      try { this.client?.close(); } catch {}
      this.client = undefined;
    }, delay);
  }

  touch(action: 0 | 1 | 2, pointerId: number, x: number, y: number) {
    if (!this.client || !this.client.isOpen()) return false;
    this.client.touch(action, pointerId, x, y);
    return true;
  }

  tryTouchMove(pointerId: number, x: number, y: number) {
    if (!this.client || !this.client.isOpen()) return false;
    return this.client.tryTouchMove(pointerId, x, y);
  }

  async touchAck(action: 0 | 1 | 2, pointerId: number, x: number, y: number) {
    if (!this.client || !this.client.isOpen()) throw new Error('control channel not open');
    return this.client.touchAck(action, pointerId, x, y);
  }

  dispose() {
    if (this.closeTimer !== undefined) {
      window.clearTimeout(this.closeTimer);
      this.closeTimer = undefined;
    }
    try { this.client?.close(); } catch {}
    this.client = undefined;
  }
}
