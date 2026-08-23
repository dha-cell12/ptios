import * as mpegts from 'mpegts.js';
import { TLinkautoWsClient } from '../../TLinkautoWsClient';

export type IosStreamProfile = 'fast' | 'rtc' | 'worker' | 'eco';

export type IosStreamUI = {
  canvas: HTMLCanvasElement;
  workerCanvas: HTMLCanvasElement;
  video: HTMLVideoElement;
  latencyOverlay: HTMLElement;
};

export class IosStreamService {
  private runId = 0;
  private ui?: IosStreamUI;
  private deviceId?: string;
  private profile?: IosStreamProfile;

  private h264Socket?: WebSocket;
  private h264Decoder?: VideoDecoder;

  private rtcPeer?: RTCPeerConnection;
  private rtcStatsTimer?: number;

  private mpegPlayer?: mpegts.Player;
  private feedbackClient?: TLinkautoWsClient;
  private reconnectTimer?: number;
  private reconnectAttempts = 0;
  private lastFrameAt = 0;
  private activeStart?: { deviceId: string; wsBase: string; httpBase: string; profile: IosStreamProfile };

  mount(ui: IosStreamUI) {
    this.ui = ui;
  }

  unmount() {
    this.stop();
    this.ui = undefined;
  }

  async start(deviceId: string, wsBase: string, httpBase: string, profile: IosStreamProfile) {
    if (!this.ui) return false;
    this.stop();
    this.runId++;
    const currentRunId = this.runId;
    this.deviceId = deviceId;
    this.profile = profile;
    this.activeStart = { deviceId, wsBase, httpBase, profile };

    let useFastPath = false;
    if (profile === 'fast') {
      useFastPath = await this.startH264(`${wsBase}/ios/${encodeURIComponent(deviceId)}/h264`, currentRunId);
    } else if (profile === 'worker') {
      useFastPath = await this.startH264(`${wsBase}/ios/${encodeURIComponent(deviceId)}/h264-worker`, currentRunId);
    } else if (profile === 'rtc') {
      useFastPath = await this.startRtc(httpBase, deviceId, currentRunId);
      if (!useFastPath) {
        console.warn('[ios-stream] RTC failed, falling back to Fast');
        useFastPath = await this.startH264(`${wsBase}/ios/${encodeURIComponent(deviceId)}/h264`, currentRunId);
      }
    }

    if (!useFastPath) {
      if (!mpegts.isSupported()) {
        console.error('mpegts.js not supported');
        return false;
      }
      this.startMpegts(wsBase, deviceId, profile, currentRunId);
    }
    return true;
  }

  stop() {
    this.runId++;
    if (this.reconnectTimer !== undefined) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = undefined;
    this.reconnectAttempts = 0;
    this.activeStart = undefined;
    this.feedbackClient?.close();
    this.feedbackClient = undefined;
    
    if (this.h264Socket) {
      this.h264Socket.close();
      this.h264Socket = undefined;
    }
    if (this.h264Decoder) {
      try { this.h264Decoder.close(); } catch {}
      this.h264Decoder = undefined;
    }
    
    if (this.rtcPeer) {
      this.rtcPeer.close();
      this.rtcPeer = undefined;
    }
    if (this.rtcStatsTimer !== undefined) {
      clearInterval(this.rtcStatsTimer);
      this.rtcStatsTimer = undefined;
    }

    if (this.mpegPlayer) {
      try { this.mpegPlayer.unload(); } catch {}
      try { this.mpegPlayer.detachMediaElement(); } catch {}
      try { this.mpegPlayer.destroy(); } catch {}
      this.mpegPlayer = undefined;
    }

    if (this.ui) {
      try {
        if (this.ui.video.srcObject instanceof MediaStream) {
          for (const track of this.ui.video.srcObject.getTracks()) track.stop();
          this.ui.video.srcObject = null;
        }
        this.ui.video.pause();
        this.ui.video.removeAttribute('src');
        this.ui.video.load();
      } catch {}

      const ctx = this.ui.canvas.getContext('2d');
      ctx?.clearRect(0, 0, this.ui.canvas.width || 1, this.ui.canvas.height || 1);
      
      this.ui.canvas.style.display = 'none';
      this.ui.workerCanvas.style.display = 'none';
      this.ui.video.style.display = 'block';
      this.ui.latencyOverlay.style.display = 'none';
      this.ui.latencyOverlay.textContent = 'Waiting for metrics...';
    }
  }

  private async startH264(url: string, runId: number): Promise<boolean> {
    const VideoDecoderCtor = (window as any).VideoDecoder as typeof VideoDecoder | undefined;
    const EncodedVideoChunkCtor = (window as any).EncodedVideoChunk as typeof EncodedVideoChunk | undefined;
    if (!VideoDecoderCtor || !EncodedVideoChunkCtor || !this.ui) return false;

    const ctx = this.ui.canvas.getContext('2d', { alpha: false });
    if (!ctx) return false;

    this.ui.video.style.display = 'none';
    this.ui.workerCanvas.style.display = 'none';
    this.ui.canvas.style.display = 'block';

    return new Promise((resolve) => {
      let settled = false;
      const settle = (ok: boolean) => {
        if (settled) return;
        settled = true;
        resolve(ok);
      };

      const socket = new WebSocket(url);
      socket.binaryType = 'arraybuffer';
      
      const decoder = new VideoDecoderCtor({
        output: (frame) => {
          if (this.runId !== runId) {
            frame.close();
            return;
          }
          const canvas = this.ui!.canvas;
          if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
            canvas.width = frame.displayWidth;
            canvas.height = frame.displayHeight;
          }
          ctx.drawImage(frame as any, 0, 0, canvas.width, canvas.height);
          frame.close();
        },
        error: (e) => {
          console.error('[ios-h264] decoder error', e);
          settle(false);
          try { socket.close(); } catch {}
        }
      });

      let configured = false;
      let sawFrame = false;
      let frameCount = 0;
      let statBytes = 0;
      let statStarted = performance.now();
      let lastFeedbackAt = 0;

      const sendFeedback = (decodeQueue: number, stalled = false) => {
        const now = performance.now();
        if (!this.activeStart || now - lastFeedbackAt < 1000) return;
        lastFeedbackAt = now;
        const elapsed = Math.max(1, now - statStarted);
        const feedback = {
          schema: 'stream_feedback_v1', port: this.activeStart.profile === 'worker' ? 7004 : 7003,
          fps: frameCount * 1000 / elapsed,
          kbps: statBytes * 8 / elapsed, decode_queue: decodeQueue, dropped: 0,
          total_approx_ms: 0, stalled,
        };
        frameCount = 0; statBytes = 0; statStarted = now;
        try {
          this.feedbackClient ??= new TLinkautoWsClient(`${this.activeStart.wsBase}/ios/${encodeURIComponent(this.activeStart.deviceId)}/tlinkauto`);
          void this.feedbackClient.waitOpen(1500).then(() =>
            this.feedbackClient?.requestWithTimeout(94, 3000, btoa(JSON.stringify(feedback))).catch(() => {}),
          ).catch(() => {});
        } catch {}
      };

      const watchdog = window.setInterval(() => {
        if (this.runId !== runId || !sawFrame || performance.now() - this.lastFrameAt < 3000) return;
        sendFeedback(decoder.decodeQueueSize, true);
        try { socket.close(); } catch {}
      }, 1000);

      const configureDecoder = () => {
        if (configured) return;
        try {
          decoder.configure({
            codec: 'avc1.42E01E',
            optimizeForLatency: true,
            avc: { format: 'annexb' }
          } as any);
          configured = true;
        } catch (e) {
          console.error('[ios-h264] decoder config failed', e);
          settle(false);
        }
      };

      socket.onopen = () => {
        if (this.runId !== runId) {
          socket.close();
          return;
        }
        this.h264Socket = socket;
        this.h264Decoder = decoder;
      };

      let pending = new Uint8Array(0);
      let firstSourceTimestampUs: number | undefined;
      let lastTimestamp = 0;

      const appendBytes = (a: Uint8Array, b: Uint8Array) => {
        if (a.length === 0) return b;
        const out = new Uint8Array(a.length + b.length);
        out.set(a, 0);
        out.set(b, a.length);
        return out;
      };

      socket.onmessage = (e) => {
        if (this.runId !== runId) return;
        if (typeof e.data === 'string') return;
        
        const chunk = new Uint8Array(e.data as ArrayBuffer);
        pending = appendBytes(pending, chunk);

        while (pending.length >= 20) {
          if (pending[0] !== 0x5a || pending[1] !== 0x58 || pending[2] !== 0x48 || (pending[3] !== 0x31 && pending[3] !== 0x32)) {
            console.error('[ios-h264] bad frame magic');
            socket.close();
            return;
          }

          const view = new DataView(pending.buffer, pending.byteOffset, pending.byteLength);
          const version = pending[3] === 0x32 ? 2 : 1;
          const flags = pending[4];
          const headerLength = version === 2 ? 52 : 20;
          if (pending.length < headerLength) break;

          let timestamp = 0;
          let payloadLength: number;

          if (version === 2) {
            const captureStartUs = Number(view.getBigUint64(16, false));
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
          frameCount += 1;
          statBytes += payloadLength;
          this.lastFrameAt = performance.now();
          sendFeedback(decoder.decodeQueueSize);
          if (!configured) {
            if (!isKey) continue;
            try {
              configureDecoder();
            } catch (err) {
              console.error('[ios-h264] configure failed', err);
              settle(false);
              socket.close();
              return;
            }
          }

          if (firstSourceTimestampUs === undefined) {
            firstSourceTimestampUs = timestamp;
          }
          const relativeTimestamp = Math.max(0, timestamp - firstSourceTimestampUs);
          lastTimestamp = relativeTimestamp > lastTimestamp ? relativeTimestamp : lastTimestamp + 1;

          try {
            decoder.decode(new EncodedVideoChunkCtor({
              type: isKey ? 'key' : 'delta',
              timestamp: lastTimestamp,
              data: payload,
            }));
            if (!sawFrame) {
              sawFrame = true;
              settle(true);
            }
          } catch (err) {
            console.error('[ios-h264] decode submit failed', err);
            settle(false);
            socket.close();
            return;
          }
        }
      };

      socket.onerror = () => settle(false);
      socket.onclose = () => {
        clearInterval(watchdog);
        if (!sawFrame) settle(false);
        if (this.runId === runId && sawFrame) this.scheduleReconnect('raw_socket_closed');
      };
      
      setTimeout(() => settle(false), 5000);
    });
  }

  private scheduleReconnect(reason: string) {
    if (!this.activeStart || this.reconnectTimer !== undefined || this.reconnectAttempts >= 6) return;
    this.reconnectAttempts += 1;
    const delay = Math.min(5000, 250 * 2 ** (this.reconnectAttempts - 1));
    console.warn(`[ios-stream] self-healing ${reason}, reconnect ${this.reconnectAttempts}/6 in ${delay}ms`);
    const start = { ...this.activeStart };
    const attempt = this.reconnectAttempts;
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = undefined;
      const reconnect = this.start(start.deviceId, start.wsBase, start.httpBase, start.profile);
      // start() performs a full transport cleanup; preserve the bounded retry
      // counter across that cleanup until a connection actually succeeds.
      this.reconnectAttempts = attempt;
      void reconnect.then((ok) => {
        if (ok) this.reconnectAttempts = 0;
      });
    }, delay);
  }

  private async fetchIceConfig(httpBase: string) {
    try {
      const resp = await fetch(`${httpBase}/rtc/config`);
      if (!resp.ok) return { iceServers: [], iceTransportPolicy: 'all' as RTCIceTransportPolicy };
      const config = await resp.json();
      return {
        iceServers: Array.isArray(config.iceServers) ? config.iceServers : [],
        iceTransportPolicy: config.iceTransportPolicy === 'relay' ? 'relay' : 'all' as RTCIceTransportPolicy,
      };
    } catch {
      return { iceServers: [], iceTransportPolicy: 'all' as RTCIceTransportPolicy };
    }
  }

  private async startRtc(httpBase: string, deviceId: string, runId: number): Promise<boolean> {
    if (!('RTCPeerConnection' in window) || !this.ui) return false;

    this.ui.video.style.display = 'block';
    this.ui.video.muted = true;
    this.ui.video.playsInline = true;
    this.ui.video.autoplay = true;
    this.ui.canvas.style.display = 'none';
    this.ui.workerCanvas.style.display = 'none';

    try {
      const iceConfig = await this.fetchIceConfig(httpBase);
      const pc = new RTCPeerConnection({
        iceServers: iceConfig.iceServers,
        iceTransportPolicy: iceConfig.iceTransportPolicy,
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require',
      });
      this.rtcPeer = pc;

      pc.addTransceiver('video', { direction: 'recvonly' });
      pc.ontrack = (event) => {
        if (this.runId !== runId) return;
        const [stream] = event.streams;
        if (stream && this.ui) {
          this.ui.video.srcObject = stream;
          this.ui.video.play().catch(() => {});
        }
      };

      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      // Wait for ICE gathering
      if (pc.iceGatheringState !== 'complete') {
        await Promise.race([
          new Promise<void>((resolve) => {
            const handler = () => {
              if (pc.iceGatheringState === 'complete') {
                pc.removeEventListener('icegatheringstatechange', handler);
                resolve();
              }
            };
            pc.addEventListener('icegatheringstatechange', handler);
          }),
          new Promise<void>((resolve) => window.setTimeout(resolve, 3000)),
        ]);
      }

      if (!pc.localDescription) throw new Error('missing local description');

      const resp = await fetch(`${httpBase}/ios/${encodeURIComponent(deviceId)}/rtc/offer`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sdp: pc.localDescription, profile: 'auto', iceTransportPolicy: iceConfig.iceTransportPolicy }),
      });

      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);

      const answer = await resp.json();
      if (this.runId !== runId || pc.signalingState === 'closed') {
        pc.close();
        return false;
      }

      await pc.setRemoteDescription(answer.sdp);
      if (this.runId !== runId || pc.connectionState === 'closed') return false;

      return true;
    } catch (e) {
      console.error('[ios-rtc] start failed', e);
      if (this.rtcPeer) {
        this.rtcPeer.close();
        this.rtcPeer = undefined;
      }
      return false;
    }
  }

  private startMpegts(wsBase: string, deviceId: string, profile: string, runId: number) {
    if (!this.ui) return;
    const streamPath = profile === 'eco' || profile === 'worker' ? 'stream-eco' : 'stream';
    const streamUrl = `${wsBase}/ios/${encodeURIComponent(deviceId)}/${streamPath}`;
    
    this.mpegPlayer = mpegts.createPlayer({
      type: 'mpegts',
      isLive: true,
      url: streamUrl,
    }, {
      enableWorker: true,
      lazyLoad: profile === 'eco',
      enableStashBuffer: profile === 'eco',
      stashInitialSize: profile === 'eco' ? 256 : 32,
      autoCleanupSourceBuffer: true,
      autoCleanupMaxBackwardDuration: 2,
      autoCleanupMinBackwardDuration: 1,
      liveBufferLatencyChasing: profile !== 'eco',
    });
    
    this.mpegPlayer.attachMediaElement(this.ui.video);
    this.mpegPlayer.load();
    this.mpegPlayer.play().catch(() => {});
  }
}
