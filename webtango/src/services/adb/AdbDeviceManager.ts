import type { AdbServerClient } from '@yume-chan/adb';
import { AdbBridge, retryWithBackoff } from './AdbBridge';

export type AdbDeviceRecord = {
  serial: string;
  state: string;
  properties?: Record<string, string>;
  device?: any;
};

type Listener<T> = (payload: T) => void;

export type AdbDeviceEvents = {
  added: AdbDeviceRecord;
  removed: { serial: string };
  changed: AdbDeviceRecord;
  refreshed: AdbDeviceRecord[];
  error: { message: string; cause?: unknown };
};

// Polls the bridge for tracked devices and emits lifecycle events. UI layers
// (vanilla or React) subscribe via on() without touching ADB internals.
export class AdbDeviceManager {
  private bridge: AdbBridge;
  private devices = new Map<string, AdbDeviceRecord>();
  private listeners: { [K in keyof AdbDeviceEvents]: Set<Listener<AdbDeviceEvents[K]>> } = {
    added: new Set(),
    removed: new Set(),
    changed: new Set(),
    refreshed: new Set(),
    error: new Set(),
  };
  private pollTimer: number | undefined;
  private pollIntervalMs = 2000;

  constructor(bridge: AdbBridge) {
    this.bridge = bridge;
  }

  on<K extends keyof AdbDeviceEvents>(event: K, listener: Listener<AdbDeviceEvents[K]>): () => void {
    this.listeners[event].add(listener);
    return () => {
      this.listeners[event].delete(listener);
    };
  }

  private emit<K extends keyof AdbDeviceEvents>(event: K, payload: AdbDeviceEvents[K]) {
    for (const listener of this.listeners[event]) {
      try {
        listener(payload);
      } catch (e) {
        console.error(`[adb-device-manager] listener for ${event} threw`, e);
      }
    }
  }

  list(): AdbDeviceRecord[] {
    return Array.from(this.devices.values());
  }

  get(serial: string): AdbDeviceRecord | undefined {
    return this.devices.get(serial);
  }

  startPolling(intervalMs = 2000) {
    this.pollIntervalMs = intervalMs;
    if (this.pollTimer !== undefined) return;
    void this.refresh();
    this.pollTimer = window.setInterval(() => void this.refresh(), this.pollIntervalMs);
  }

  stopPolling() {
    if (this.pollTimer !== undefined) {
      window.clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  async refresh(): Promise<AdbDeviceRecord[]> {
    let client: AdbServerClient;
    try {
      client = await this.bridge.ensure();
    } catch (e) {
      this.emit('error', { message: 'failed to acquire ADB bridge', cause: e });
      return this.list();
    }

    let rawDevices: any[];
    try {
      rawDevices = await retryWithBackoff(() => client.getDevices(), 2, 300, 'getDevices');
    } catch (e) {
      this.emit('error', { message: 'getDevices failed', cause: e });
      return this.list();
    }

    const seen = new Set<string>();
    for (const raw of rawDevices) {
      const serial: string = raw.serial ?? raw.transportId ?? String(raw);
      seen.add(serial);
      const existing = this.devices.get(serial);
      const record: AdbDeviceRecord = {
        serial,
        state: raw.state ?? 'unknown',
        properties: existing?.properties,
        device: raw,
      };
      if (!existing) {
        this.devices.set(serial, record);
        this.emit('added', record);
      } else if (existing.state !== record.state) {
        this.devices.set(serial, { ...existing, ...record });
        this.emit('changed', this.devices.get(serial)!);
      } else {
        this.devices.set(serial, { ...existing, device: raw });
      }
    }

    for (const serial of Array.from(this.devices.keys())) {
      if (!seen.has(serial)) {
        this.devices.delete(serial);
        this.emit('removed', { serial });
      }
    }

    const snapshot = this.list();
    this.emit('refreshed', snapshot);
    return snapshot;
  }

  setProperties(serial: string, properties: Record<string, string>) {
    const existing = this.devices.get(serial);
    if (!existing) return;
    const updated = { ...existing, properties };
    this.devices.set(serial, updated);
    this.emit('changed', updated);
  }
}
