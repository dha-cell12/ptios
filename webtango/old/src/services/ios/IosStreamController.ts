import * as mpegts from 'mpegts.js';
import { buildIosStreamUrls, fetchRtcIceConfig } from './IosBridgeApi';

export type IosStreamProfile = 'fast' | 'rtc' | 'worker' | 'eco';

export type IosStreamTargets = {
  video: HTMLVideoElement;
  canvas: HTMLCanvasElement;
  workerCanvas?: HTMLCanvasElement;
};

export type IosStreamStartOptions = {
  bridgeWsUrl: string;
  deviceId: string;
  profile: IosStreamProfile;
  forceRelay?: boolean;
  onStats?: (stats: unknown) => void;
  onProfileFallback?: (from: IosStreamProfile, to: IosStreamProfile, reason: string) => void;
};

export type IosStreamSession = {
  profile: IosStreamProfile;
  stop: () => void;
};

// High-level façade that picks the right transport (fast h264, RTC, worker, eco mpegts)
// and returns a stop() to tear everything down. Detailed h264/RTC pipelines stay in main.ts
// for now; this controller is the seam React components will subscribe to in Phase 3.
export class IosStreamController {
  private targets: IosStreamTargets;
  private current: IosStreamSession | undefined;
  private player: any | undefined;
  private pc: RTCPeerConnection | undefined;
  private socket: WebSocket | undefined;
  private decoder: VideoDecoder | undefined;
  private worker: Worker | undefined;
  private offscreen: OffscreenCanvas | undefined;
  private workerCanvasTransferred = false;

  constructor(targets: IosStreamTargets) {
    this.targets = targets;
  }

  getProfile(): IosStreamProfile | undefined {
    return this.current?.profile;
  }

  async start(options: IosStreamStartOptions): Promise<IosStreamSession> {
    this.stop();
    const urls = buildIosStreamUrls(options.bridgeWsUrl, options.deviceId);

    let profile = options.profile;
    if (profile === 'rtc' && typeof RTCPeerConnection === 'undefined') {
      options.onProfileFallback?.(profile, 'fast', 'RTCPeerConnection unavailable');
      profile = 'fast';
    }

    const session: IosStreamSession = {
      profile,
      stop: () => this.stop(),
    };

    if (profile === 'rtc') {
      const ok = await this.startRtc(urls.httpBase, urls.rtcOffer, urls.rtcClose, options);
      if (!ok) {
        options.onProfileFallback?.('rtc', 'fast', 'RTC negotiation failed');
        session.profile = 'fast';
        profile = 'fast';
      }
    }

    if (profile === 'fast') {
      await this.startMpegts(urls.h264.replace('/h264', '/stream'), false);
    } else if (profile === 'eco') {
      await this.startMpegts(urls.streamEco, true);
    } else if (profile === 'worker') {
      const ok = await this.startWorker(urls.h264Worker);
      if (!ok) {
        options.onProfileFallback?.('worker', 'fast', 'OffscreenCanvas worker unavailable');
        await this.startMpegts(urls.stream, false);
        session.profile = 'fast';
      }
    }

    this.current = session;
    return session;
  }

  stop() {
    this.current = undefined;
    try { this.player?.unload?.(); } catch {}
    try { this.player?.detachMediaElement?.(); } catch {}
    try { this.player?.destroy?.(); } catch {}
    this.player = undefined;

    try { this.socket?.close(); } catch {}
    this.socket = undefined;

    try { this.decoder?.close(); } catch {}
    this.decoder = undefined;

    try { this.worker?.postMessage({ type: 'stop' }); } catch {}
    this.worker = undefined;

    if (this.pc) {
      try {
        this.pc.ontrack = null;
        this.pc.onconnectionstatechange = null;
        this.pc.oniceconnectionstatechange = null;
        for (const recv of this.pc.getReceivers()) recv.track?.stop();
        for (const send of this.pc.getSenders()) send.track?.stop();
        this.pc.close();
      } catch {}
      this.pc = undefined;
    }

    const { video } = this.targets;
    try {
      if (video.srcObject instanceof MediaStream) {
        for (const t of video.srcObject.getTracks()) t.stop();
        video.srcObject = null;
      }
      video.pause();
      video.removeAttribute('src');
      video.load();
    } catch {}
  }

  private async startMpegts(url: string, eco: boolean): Promise<boolean> {
    if (!mpegts.isSupported()) return false;
    const { video } = this.targets;
    video.style.display = 'block';
    const config = eco
      ? {
          enableWorker: true,
          enableStashBuffer: true,
          stashInitialSize: 256,
          lazyLoad: true,
          liveBufferLatencyChasing: false,
          liveSync: false,
          autoCleanupSourceBuffer: true,
          autoCleanupMaxBackwardDuration: 10,
          autoCleanupMinBackwardDuration: 5,
        }
      : {
          enableWorker: true,
          lazyLoad: false,
          enableStashBuffer: false,
          stashInitialSize: 32,
          autoCleanupSourceBuffer: true,
          autoCleanupMaxBackwardDuration: 2,
          autoCleanupMinBackwardDuration: 1,
          liveBufferLatencyChasing: true,
          liveBufferLatencyMaxLatency: 0.8,
          liveBufferLatencyMinRemain: 0.15,
          liveSync: true,
          liveSyncTargetLatency: 0.3,
          liveSyncPlaybackRate: 1.5,
        };
    this.player = mpegts.createPlayer({ type: 'mpegts', isLive: true, url } as any, config as any);
    this.player.attachMediaElement(video);
    video.playsInline = true;
    video.muted = true;
    video.preload = 'auto';
    this.player.load();
    try { await video.play(); } catch {}
    return true;
  }

  private async startWorker(url: string): Promise<boolean> {
    const { workerCanvas, video } = this.targets;
    if (!workerCanvas || !('transferControlToOffscreen' in workerCanvas) || !('Worker' in window)) return false;
    video.style.display = 'none';
    workerCanvas.style.display = 'block';
    try {
      if (!this.workerCanvasTransferred) {
        this.offscreen = workerCanvas.transferControlToOffscreen();
        this.workerCanvasTransferred = true;
      }
      this.worker = new Worker(new URL('../../IosH264Worker.ts', import.meta.url), { type: 'module' });
      return await new Promise<boolean>((resolve) => {
        let settled = false;
        const timer = window.setTimeout(() => {
          if (!settled) { settled = true; resolve(false); }
        }, 1500);
        this.worker!.onmessage = (ev) => {
          const data = ev.data;
          if (data?.type === 'started') {
            if (!settled) { settled = true; clearTimeout(timer); resolve(true); }
          } else if (data?.type === 'start-failed') {
            if (!settled) { settled = true; clearTimeout(timer); resolve(false); }
          }
        };
        if (this.offscreen) {
          this.worker!.postMessage({ type: 'start', url, canvas: this.offscreen }, [this.offscreen]);
          this.offscreen = undefined;
        } else {
          this.worker!.postMessage({ type: 'start', url });
        }
      });
    } catch (e) {
      console.warn('[ios-stream] worker start failed', e);
      workerCanvas.style.display = 'none';
      video.style.display = 'block';
      return false;
    }
  }

  private async startRtc(httpBase: string, offerUrl: string, _closeUrl: string, options: IosStreamStartOptions): Promise<boolean> {
    try {
      const ice = await fetchRtcIceConfig(options.bridgeWsUrl, options.forceRelay);
      const pc = new RTCPeerConnection({
        iceServers: ice.iceServers,
        iceTransportPolicy: ice.iceTransportPolicy ?? 'all',
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require',
      });
      this.pc = pc;
      pc.addTransceiver('video', { direction: 'recvonly' });
      pc.ontrack = (ev) => {
        const [stream] = ev.streams;
        if (stream) {
          this.targets.video.srcObject = stream;
          this.targets.video.play().catch(() => {});
        }
      };
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await new Promise<void>((resolve) => {
        if (pc.iceGatheringState === 'complete') return resolve();
        const t = window.setTimeout(resolve, 3000);
        pc.addEventListener('icegatheringstatechange', () => {
          if (pc.iceGatheringState === 'complete') { clearTimeout(t); resolve(); }
        });
      });
      const local = pc.localDescription;
      if (!local) throw new Error('no local description');
      const resp = await fetch(offerUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sdp: local, profile: 'auto', iceTransportPolicy: ice.iceTransportPolicy ?? 'all' }),
      });
      if (!resp.ok) throw new Error(`offer HTTP ${resp.status}`);
      const answer = await resp.json();
      await pc.setRemoteDescription(answer.sdp);
      return true;
    } catch (e) {
      console.warn('[ios-stream] rtc start failed', e);
      try { this.pc?.close(); } catch {}
      this.pc = undefined;
      return false;
    }
  }
}
