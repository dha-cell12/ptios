type ZxResponse = { ok: boolean; parts: string[]; raw: string };

function encodeAscii(text: string): Uint8Array {
  // Protocol is ASCII-friendly; force 0-127.
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    out[i] = text.charCodeAt(i) & 0x7f;
  }
  return out;
}

export class ZxTouchWsClient {
  private url: string;
  private ws: WebSocket;
  private buf = new Uint8Array(0);
  private lineWaiters: Array<(line: string) => void> = [];
  private closed = false;
  private keepaliveTimer: number | undefined;
  private lastTx = 0;
  private lastRx = 0;
  private suppressKeepaliveUntil = 0;
  private touchSeq = 1;

  constructor(url: string) {
    this.url = url;
    this.ws = new WebSocket(url);
    this.ws.binaryType = 'arraybuffer';

    this.ws.onmessage = (ev) => {
      this.lastRx = Date.now();
      const chunk = typeof ev.data === 'string' ? encodeAscii(ev.data) : new Uint8Array(ev.data);
      const merged = new Uint8Array(this.buf.length + chunk.length);
      merged.set(this.buf, 0);
      merged.set(chunk, this.buf.length);
      this.buf = merged;
      this.pumpLines();
    };

    this.ws.onclose = () => {
      this.closed = true;
      if (this.keepaliveTimer !== undefined) {
        clearInterval(this.keepaliveTimer);
        this.keepaliveTimer = undefined;
      }
      this.lineWaiters.splice(0).forEach((w) => w(''));
    };

    this.ws.onopen = () => {
      const now = Date.now();
      this.lastTx = now;
      this.lastRx = now;
      // Some tunnels/proxies kill idle WS ~20-30s.
      // Send a harmless command periodically to keep the control channel alive.
      this.keepaliveTimer = window.setInterval(() => {
        if (this.ws.readyState !== WebSocket.OPEN) return;
        const now = Date.now();
        if (now < this.suppressKeepaliveUntil) return;
        if (now - this.lastTx < 6000) return;
        try {
          // TASK_CURRENT_DIR (45) is safe and lightweight.
          this.ws.send('45\r\n');
          this.lastTx = now;
        } catch {
          // Ignore.
        }
      }, 5000);
    };
  }

  isOpen() {
    return this.ws.readyState === WebSocket.OPEN;
  }

  bufferedAmount() {
    return this.ws.bufferedAmount;
  }

  suppressKeepalive(ms = 1500) {
    this.suppressKeepaliveUntil = Math.max(this.suppressKeepaliveUntil, Date.now() + ms);
  }

  isStale(staleAfterMs = 20000) {
    if (this.ws.readyState !== WebSocket.OPEN) return true;
    const now = Date.now();
    return now - this.lastRx > staleAfterMs;
  }

  getUrl() {
    return this.url;
  }

  async waitOpen(timeoutMs = 1500): Promise<void> {
    if (this.ws.readyState === WebSocket.OPEN) return;
    await Promise.race([
      new Promise<void>((resolve, reject) => {
        this.ws.addEventListener('open', () => resolve(), { once: true });
        this.ws.addEventListener('error', () => reject(new Error('zxtouch ws error')), { once: true });
      }),
      new Promise<void>((_, reject) => setTimeout(() => reject(new Error('zxtouch ws open timeout')), timeoutMs)),
    ]);
  }

  close() {
    try {
      this.ws.close();
    } catch {}
  }

  private pumpLines() {
    while (true) {
      const idx = this.buf.indexOf(0x0a); // \n
      if (idx === -1) break;
      const lineBytes = this.buf.slice(0, idx + 1);
      this.buf = this.buf.slice(idx + 1);
      const line = new TextDecoder().decode(lineBytes).trim();
      const w = this.lineWaiters.shift();
      if (w) w(line);
    }
  }

  private nextLine(timeoutMs = 1000): Promise<string> {
    if (this.closed) return Promise.resolve('');
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const idx = this.lineWaiters.indexOf(resolve);
        if (idx >= 0) this.lineWaiters.splice(idx, 1);
        reject(new Error('zxtouch timeout'));
      }, timeoutMs);

      this.lineWaiters.push((line) => {
        clearTimeout(timer);
        resolve(line);
      });

      this.pumpLines();
    });
  }

  private decodeResponse(line: string): ZxResponse {
    const raw = line.replace(/\r\n?$/, '');
    if (!raw) return { ok: false, parts: [], raw };
    const parts = raw.split(';;');
    const ok = parts[0] === '0';
    return { ok, parts: ok ? parts.slice(1) : parts.slice(1), raw };
  }

  async request(task: number, ...args: Array<string | number>): Promise<ZxResponse> {
    await this.waitOpen();
    this.lastTx = Date.now();
    const payload = `${task}${args.map(String).join(';;')}\r\n`;
    this.ws.send(payload);
    const line = await this.nextLine();
    return this.decodeResponse(line);
  }

  sendRaw(text: string) {
    if (this.ws.readyState !== WebSocket.OPEN) return;
    this.lastTx = Date.now();
    this.ws.send(text);
  }

  trySendRaw(text: string, maxBufferedBytes = 512 * 1024) {
    if (this.ws.readyState !== WebSocket.OPEN) return false;
    if (this.ws.bufferedAmount > maxBufferedBytes) return false;
    this.lastTx = Date.now();
    this.ws.send(text);
    return true;
  }

  async getScreenSize(): Promise<{ width: number; height: number } | null> {
    // TASK_GET_DEVICE_INFO (25) subtask screen_size (1)
    try {
      const r = await this.request(25, 1);
      if (!r.ok || r.parts.length < 2) return null;
      const w = Number(r.parts[0]);
      const h = Number(r.parts[1]);
      if (!Number.isFinite(w) || !Number.isFinite(h)) return null;
      return { width: w, height: h };
    } catch {
      return null;
    }
  }

  touch(type: number, fingerIndex: number, x: number, y: number) {
    this.suppressKeepalive();
    // TASK_PERFORM_TOUCH (10)
    // legacy payload: "1{type}{finger:02}{x*10:05}{y*10:05}"
    const xi = Math.max(0, Math.round(x * 10));
    const yi = Math.max(0, Math.round(y * 10));
    const payload = `1${type}${String(fingerIndex).padStart(2, '0')}${String(xi).padStart(5, '0')}${String(yi).padStart(5, '0')}`;
    this.sendRaw(`10${payload}\r\n`);
  }

  async touchAck(type: number, fingerIndex: number, x: number, y: number): Promise<{ seq: number; latencyMs: number; dispatchUs?: number }> {
    this.suppressKeepalive();
    await this.waitOpen();
    const xi = Math.max(0, Math.round(x * 10));
    const yi = Math.max(0, Math.round(y * 10));
    const payload = `1${type}${String(fingerIndex).padStart(2, '0')}${String(xi).padStart(5, '0')}${String(yi).padStart(5, '0')}`;
    const seq = this.touchSeq++;
    const started = performance.now();
    this.lastTx = Date.now();
    this.ws.send(`61${seq};;${payload}\r\n`);

    while (true) {
      const line = await this.nextLine(1000);
      const response = this.decodeResponse(line);
      if (!response.ok || response.parts[0] !== String(seq)) continue;
      const dispatchUs = Number(response.parts[1]);
      return {
        seq,
        latencyMs: performance.now() - started,
        dispatchUs: Number.isFinite(dispatchUs) ? dispatchUs : undefined,
      };
    }
  }

  tryTouchMove(fingerIndex: number, x: number, y: number) {
    this.suppressKeepalive(1000);
    const xi = Math.max(0, Math.round(x * 10));
    const yi = Math.max(0, Math.round(y * 10));
    const payload = `12${String(fingerIndex).padStart(2, '0')}${String(xi).padStart(5, '0')}${String(yi).padStart(5, '0')}`;
    return this.trySendRaw(`10${payload}\r\n`);
  }
}
