type WorkerStartMessage = {
  type: 'start';
  url: string;
  canvas?: OffscreenCanvas;
};

type WorkerStopMessage = {
  type: 'stop';
};

type WorkerMessage = WorkerStartMessage | WorkerStopMessage;

type FrameMeta = {
  frameId: number;
  key: boolean;
  timestamp: number;
  captureStartUs?: number;
  captureDoneUs?: number;
  encodeDoneUs?: number;
  deviceSendUs?: number;
  browserRecvMs: number;
  decodeSubmitMs: number;
  payloadBytes: number;
};

type Metrics = {
  frame: number;
  fps: number;
  source_ms: number;
  capture_ms: number;
  encode_ms: number;
  net_approx_ms: number;
  browser_ms: number;
  decode_ms: number;
  draw_ms: number;
  total_approx_ms: number;
  decode_queue: number;
  in_flight: number;
  dropped: number;
  submitted: number;
  rendered: number;
  frames: number;
  kbps: number;
};

let socket: WebSocket | undefined;
let decoder: VideoDecoder | undefined;
let stopped = false;
let renderCanvas: OffscreenCanvas | undefined;

function appendBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length === 0) return b;
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function smooth(previous: number, next: number, alpha = 0.18) {
  if (!Number.isFinite(previous) || previous <= 0) return next;
  return previous * (1 - alpha) + next * alpha;
}

function msFromUsDelta(endUs?: number, startUs?: number) {
  if (endUs === undefined || startUs === undefined) return 0;
  return Math.max(0, (endUs - startUs) / 1000);
}

function stop() {
  stopped = true;
  try {
    socket?.close();
  } catch {}
  socket = undefined;
  try {
    decoder?.close();
  } catch {}
  decoder = undefined;
}

function postMetrics(metrics: Metrics) {
  self.postMessage({ type: 'metrics', metrics });
}

function start(url: string, canvas?: OffscreenCanvas) {
  stop();
  stopped = false;
  if (canvas) renderCanvas = canvas;
  if (!renderCanvas) {
    self.postMessage({ type: 'start-failed', reason: 'OffscreenCanvas missing' });
    return;
  }

  const VideoDecoderCtor = (self as any).VideoDecoder as typeof VideoDecoder | undefined;
  const EncodedVideoChunkCtor = (self as any).EncodedVideoChunk as typeof EncodedVideoChunk | undefined;
  if (!VideoDecoderCtor || !EncodedVideoChunkCtor) {
    self.postMessage({ type: 'start-failed', reason: 'WebCodecs unavailable in worker' });
    return;
  }

  const ctx = renderCanvas.getContext('2d', { alpha: false });
  if (!ctx) {
    self.postMessage({ type: 'start-failed', reason: 'OffscreenCanvas 2D unavailable' });
    return;
  }

  let configured = false;
  let pending = new Uint8Array(0);
  let lastTimestamp = 0;
  let firstSourceTimestampUs: number | undefined;
  let fallbackFrameId = 0;
  let deviceToBrowserOffsetMs: number | undefined;
  let inFlight = 0;
  let sawFrame = false;
  const metaByTimestamp = new Map<number, FrameMeta>();

  let frames = 0;
  let submitted = 0;
  let rendered = 0;
  let dropped = 0;
  let sourceMs = 0;
  let captureMs = 0;
  let encodeMs = 0;
  let netMs = 0;
  let browserMs = 0;
  let decodeMs = 0;
  let drawMs = 0;
  let totalMs = 0;
  let lastFrameId = 0;

  let statStarted = performance.now();
  let statFrames = 0;
  let statBytes = 0;
  let fps = 0;
  let bytesPerSec = 0;
  let lastMetricsAt = 0;

  decoder = new VideoDecoderCtor({
    output(frame) {
      const outputStartMs = performance.now();
      const meta = metaByTimestamp.get(frame.timestamp);
      if (meta) metaByTimestamp.delete(frame.timestamp);
      try {
        const width = frame.displayWidth || frame.codedWidth;
        const height = frame.displayHeight || frame.codedHeight;
        if (renderCanvas!.width !== width || renderCanvas!.height !== height) {
          renderCanvas!.width = width;
          renderCanvas!.height = height;
        }
        ctx.drawImage(frame, 0, 0, renderCanvas!.width, renderCanvas!.height);
        const renderDoneMs = performance.now();
        if (meta) {
          rendered += 1;
          const dMs = Math.max(0, outputStartMs - meta.decodeSubmitMs);
          const rMs = Math.max(0, renderDoneMs - outputStartMs);
          const bMs = dMs + rMs;
          decodeMs = smooth(decodeMs, dMs);
          drawMs = smooth(drawMs, rMs);
          browserMs = smooth(browserMs, bMs);
          totalMs = smooth(totalMs, sourceMs + netMs + bMs);
        }
      } finally {
        inFlight = Math.max(0, inFlight - 1);
        frame.close();
      }
    },
    error(e) {
      self.postMessage({ type: 'decoder-error', error: String(e) });
    },
  });

  const configureDecoder = () => {
    if (configured || !decoder) return;
    const realtimeConfig = {
      codec: 'avc1.42E01E',
      optimizeForLatency: true,
      latencyMode: 'realtime',
      hardwareAcceleration: 'prefer-hardware',
      avc: { format: 'annexb' },
    } as any;
    try {
      decoder.configure(realtimeConfig);
    } catch {
      decoder.configure({
        codec: 'avc1.42E01E',
        optimizeForLatency: true,
        avc: { format: 'annexb' },
      } as any);
    }
    configured = true;
  };

  socket = new WebSocket(url);
  socket.binaryType = 'arraybuffer';
  socket.onerror = () => self.postMessage({ type: 'start-failed', reason: 'WebSocket error' });
  socket.onclose = () => {
    if (!stopped) self.postMessage({ type: 'closed' });
  };

  socket.onmessage = (ev) => {
    if (stopped || !decoder) return;
    const browserRecvMs = performance.now();
    pending = appendBytes(pending, new Uint8Array(ev.data as ArrayBuffer));

    while (pending.length >= 20) {
      if (pending[0] !== 0x5a || pending[1] !== 0x58 || pending[2] !== 0x48 || (pending[3] !== 0x31 && pending[3] !== 0x32)) {
        self.postMessage({ type: 'start-failed', reason: 'Bad ZXH magic' });
        stop();
        return;
      }

      const view = new DataView(pending.buffer, pending.byteOffset, pending.byteLength);
      const version = pending[3] === 0x32 ? 2 : 1;
      const flags = pending[4];
      const headerLength = version === 2 ? 52 : 20;
      if (pending.length < headerLength) break;

      let frameId = fallbackFrameId++;
      let timestamp = 0;
      let captureStartUs: number | undefined;
      let captureDoneUs: number | undefined;
      let encodeDoneUs: number | undefined;
      let deviceSendUs: number | undefined;
      let payloadLength: number;

      if (version === 2) {
        frameId = view.getUint32(8, false);
        captureStartUs = Number(view.getBigUint64(16, false));
        captureDoneUs = Number(view.getBigUint64(24, false));
        encodeDoneUs = Number(view.getBigUint64(32, false));
        deviceSendUs = Number(view.getBigUint64(40, false));
        payloadLength = view.getUint32(48, false);
        timestamp = captureStartUs;
      } else {
        timestamp = Number(view.getBigUint64(8, false));
        payloadLength = view.getUint32(16, false);
      }

      const frameLength = headerLength + payloadLength;
      if (pending.length < frameLength) break;

      const payload = pending.slice(headerLength, frameLength);
      pending = pending.slice(frameLength);
      const isKey = (flags & 1) !== 0;

      if (!configured) {
        if (!isKey) continue;
        configureDecoder();
      }

      if (firstSourceTimestampUs === undefined) firstSourceTimestampUs = timestamp;
      const relativeTimestamp = Math.max(0, timestamp - firstSourceTimestampUs);
      lastTimestamp = relativeTimestamp > lastTimestamp ? relativeTimestamp : lastTimestamp + 1;

      frames += 1;
      lastFrameId = frameId;
      captureMs = smooth(captureMs, msFromUsDelta(captureDoneUs, captureStartUs));
      encodeMs = smooth(encodeMs, msFromUsDelta(encodeDoneUs, captureDoneUs));
      sourceMs = smooth(sourceMs, msFromUsDelta(deviceSendUs, captureStartUs));
      if (deviceSendUs !== undefined && deviceToBrowserOffsetMs === undefined) {
        deviceToBrowserOffsetMs = browserRecvMs - deviceSendUs / 1000;
      }
      if (deviceSendUs !== undefined && deviceToBrowserOffsetMs !== undefined) {
        netMs = smooth(netMs, Math.max(0, browserRecvMs - (deviceSendUs / 1000 + deviceToBrowserOffsetMs)));
      }

      statFrames += 1;
      statBytes += payloadLength;
      const statElapsed = browserRecvMs - statStarted;
      if (statElapsed >= 1000) {
        fps = (statFrames * 1000) / statElapsed;
        bytesPerSec = (statBytes * 1000) / statElapsed;
        statFrames = 0;
        statBytes = 0;
        statStarted = browserRecvMs;
      }

      const decodeSubmitMs = performance.now();
      metaByTimestamp.set(lastTimestamp, {
        frameId,
        key: isKey,
        timestamp: lastTimestamp,
        captureStartUs,
        captureDoneUs,
        encodeDoneUs,
        deviceSendUs,
        browserRecvMs,
        decodeSubmitMs,
        payloadBytes: payloadLength,
      });

      try {
        inFlight += 1;
        submitted += 1;
        decoder.decode(new EncodedVideoChunkCtor({
          type: isKey ? 'key' : 'delta',
          timestamp: lastTimestamp,
          data: payload,
        }));
      } catch (e) {
        inFlight = Math.max(0, inFlight - 1);
        metaByTimestamp.delete(lastTimestamp);
        self.postMessage({ type: 'start-failed', reason: String(e) });
        stop();
        return;
      }

      if (!sawFrame) {
        sawFrame = true;
        self.postMessage({ type: 'started' });
      }

      if (browserRecvMs - lastMetricsAt > 500) {
        lastMetricsAt = browserRecvMs;
        postMetrics({
          frame: lastFrameId,
          fps,
          source_ms: sourceMs,
          capture_ms: captureMs,
          encode_ms: encodeMs,
          net_approx_ms: netMs,
          browser_ms: browserMs,
          decode_ms: decodeMs,
          draw_ms: drawMs,
          total_approx_ms: totalMs,
          decode_queue: decoder.decodeQueueSize,
          in_flight: inFlight,
          dropped,
          submitted,
          rendered,
          frames,
          kbps: (bytesPerSec * 8) / 1000,
        });
      }
    }
  };
}

self.onmessage = (event: MessageEvent<WorkerMessage>) => {
  if (event.data.type === 'start') start(event.data.url, event.data.canvas);
  if (event.data.type === 'stop') stop();
};

export {};
