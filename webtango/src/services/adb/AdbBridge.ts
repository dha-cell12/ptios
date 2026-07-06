import { AdbServerClient } from '@yume-chan/adb';
import { AdbWebSocketConnector } from '../../AdbWebSocketConnector';

export function normalizeBridgeWebSocketUrl(bridgeUrl: string): string {
  const u = new URL(bridgeUrl.trim());
  u.protocol = u.protocol === 'https:' || u.protocol === 'wss:' ? 'wss:' : 'ws:';
  if (u.pathname.endsWith('/bridge/')) {
    u.pathname = u.pathname.slice(0, -1);
  }
  return u.toString().replace(/\/$/, '');
}

// Wraps AdbServerClient lifecycle: create, health-check, recreate-on-stale.
// The same instance is reused as long as it responds to getDevices() within
// the timeout; otherwise we transparently rebuild it on top of a fresh WS.
export class AdbBridge {
  private client: AdbServerClient | undefined;
  private url: string | undefined;

  setEndpoint(rawUrl: string) {
    this.url = normalizeBridgeWebSocketUrl(rawUrl);
  }

  getEndpoint(): string | undefined {
    return this.url;
  }

  private build(): AdbServerClient {
    if (!this.url) throw new Error('AdbBridge endpoint not set');
    const connector = new AdbWebSocketConnector(this.url);
    return new AdbServerClient(connector);
  }

  async ensure(): Promise<AdbServerClient> {
    if (!this.client) {
      this.client = this.build();
    }
    return this.client;
  }

  forceRecreate(): AdbServerClient {
    this.client = this.build();
    return this.client;
  }

  get current(): AdbServerClient | undefined {
    return this.client;
  }

  close() {
    if (!this.client) return;
    try {
      (this.client as any).connector?.close?.();
    } catch (e) {
      console.warn('[adb-bridge] close error', e);
    }
    this.client = undefined;
  }
}

export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries = 3,
  initialDelayMs = 500,
  label = 'operation'
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt < maxRetries) {
        const delayMs =initialDelayMs * Math.pow(2, attempt);
        console.warn(`[adb-bridge] ${label} attempt ${attempt + 1} failed, retrying in ${delayMs}ms`, error);
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
    }
  }
  throw lastError;
}
