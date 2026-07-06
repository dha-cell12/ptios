import './style.css';
import './screen-view.css';
import { Adb, AdbServerClient } from '@yume-chan/adb';
import { AdbScrcpyClient, AdbScrcpyOptions3_1 } from '@yume-chan/adb-scrcpy';
import { AndroidMotionEventAction, AndroidKeyCode, AndroidKeyEventAction, ScrcpyVideoCodecId } from '@yume-chan/scrcpy';
import { WebCodecsVideoDecoder, BitmapVideoFrameRenderer } from '@yume-chan/scrcpy-decoder-webcodecs';
import { PackageManager } from '@yume-chan/android-bin';
import { ReadableStream, WrapReadableStream, type MaybeConsumable } from '@yume-chan/stream-extra';
import * as mpegts from 'mpegts.js';
import { AdbWebSocketConnector } from './AdbWebSocketConnector';
import { ScrcpyBatchController } from './ScrcpyBatchController';
import { TLinkautoWsClient } from './TLinkautoWsClient';
import { bridgeStore, setBridgeUrl, markConnecting, markConnected, markDisconnected, markError } from './stores/BridgeStore';
import { iosDeviceStore, refreshIosDevices as refreshIosDevicesStore, startIosPolling, stopIosPolling } from './stores/IosDeviceStore';
import { adbDeviceStore, upsertLegacyDevice, removeLegacyDevice } from './stores/AdbDeviceStore';
import { registerMirrorSession, unregisterMirrorSession } from './stores/ScrcpyMirrorStore';
import { registerAdbConnection, unregisterAdbConnection } from './stores/AdbConnectionRegistry';
import { CanvasDrawRegistry } from './services/canvas/CanvasDrawRegistry';
import type { ScrcpyMirrorSession } from './services/adb/ScrcpyMirror';

let automationIdeMounted = false;

async function ensureAutomationIdeMounted() {
  if (automationIdeMounted) return;
  const root = document.getElementById('automation-ide-root');
  if (!root) return;
  const { mountAutomationIde } = await import('./ide/mountAutomationIde');
  mountAutomationIde(root);
  automationIdeMounted = true;
}

// UI Elements
const statusBadge = document.getElementById('status') as HTMLSpanElement;
const endpointInput = document.getElementById('endpoint') as HTMLInputElement;
const connectButton = document.getElementById('connect') as HTMLButtonElement;
const disconnectButton = document.getElementById('disconnect') as HTMLButtonElement;
const devicesContainer = document.getElementById('devices-container') as HTMLDivElement;
const deviceCardTemplate = document.getElementById('device-card-template') as HTMLTemplateElement;
const deviceCountLabel = document.getElementById('device-count') as HTMLSpanElement;
const searchInput = document.getElementById('search-query') as HTMLInputElement;
const refreshBtn = document.getElementById('refresh-devices') as HTMLButtonElement;
const iosDevicesContainer = document.getElementById('ios-devices-container') as HTMLDivElement;
const iosDeviceCardTemplate = document.getElementById('ios-device-card-template') as HTMLTemplateElement;
const iosDeviceCountLabel = document.getElementById('ios-device-count') as HTMLSpanElement;
const detailPane = document.getElementById('device-detail') as HTMLElement;
const detailEmpty = document.getElementById('detail-empty') as HTMLDivElement;
const detailContent = document.getElementById('detail-content') as HTMLDivElement;
const detailThumb = document.getElementById('detail-thumb') as HTMLImageElement;
const detailName = document.getElementById('detail-name') as HTMLHeadingElement;
const detailMeta = document.getElementById('detail-meta') as HTMLParagraphElement;
const detailCanvas = document.getElementById('device-canvas') as HTMLCanvasElement;
const shellPane = document.getElementById('shell-pane') as HTMLDivElement;
const toggleShellBtn = document.getElementById('toggle-shell') as HTMLButtonElement;
const shellOutput = document.getElementById('shell-output') as HTMLDivElement;
const shellCommand = document.getElementById('shell-command') as HTMLInputElement;
const shellRun = document.getElementById('run-shell') as HTMLButtonElement;
const statBattery = document.getElementById('stat-battery') as HTMLDivElement;
const statMemory = document.getElementById('stat-memory') as HTMLDivElement;
const statSerial = document.getElementById('stat-serial') as HTMLDivElement;
const statModel = document.getElementById('stat-model') as HTMLDivElement;
const deviceModal = document.getElementById('device-modal') as HTMLDivElement;
const modalCanvas = document.getElementById('modal-canvas') as HTMLCanvasElement;
const modalDeviceTitle = document.getElementById('modal-device-title') as HTMLHeadingElement;
const closeModalButton = document.getElementById('close-modal') as HTMLButtonElement;
const pullFilePane = document.getElementById('pull-file-pane') as HTMLDivElement;
const pullFilePathInput = document.getElementById('pull-file-path') as HTMLInputElement;
const pullFileBtn = document.getElementById('run-pull-file') as HTMLButtonElement;
const pullFileStatus = document.getElementById('pull-file-status') as HTMLDivElement;

const iosStreamModal = document.getElementById('ios-stream-modal') as HTMLDivElement;
const iosModalDeviceTitle = document.getElementById('ios-modal-device-title') as HTMLHeadingElement;
const closeIosModalButton = document.getElementById('close-ios-modal') as HTMLButtonElement;
const iosVideo = document.getElementById('ios-video') as HTMLVideoElement;
const iosCanvas = document.getElementById('ios-canvas') as HTMLCanvasElement;
const iosWorkerCanvas = document.getElementById('ios-worker-canvas') as HTMLCanvasElement;
const iosLatencyOverlay = document.getElementById('ios-latency-overlay') as HTMLDivElement;
const iosStreamFrame = document.querySelector('.ios-stream-frame') as HTMLDivElement;
const iosModeFastButton = document.getElementById('ios-mode-fast') as HTMLButtonElement;
const iosModeRtcButton = document.getElementById('ios-mode-rtc') as HTMLButtonElement;
const iosModeWorkerButton = document.getElementById('ios-mode-worker') as HTMLButtonElement;
const iosModeEcoButton = document.getElementById('ios-mode-eco') as HTMLButtonElement;
const initialUrlParams = new URLSearchParams(window.location.search);
const iosDisableControlForTest = initialUrlParams.get('iosNoControl') === '1';
const iosControlMode = initialUrlParams.get('iosControlMode') === 'ephemeral' ? 'ephemeral' : 'persistent';
const iosAckTouch = initialUrlParams.get('iosAckTouch') === '1';
const iosRtcForceRelay = initialUrlParams.get('rtcForceRelay') === '1';
const iosAutoTouchMode = initialUrlParams.get('iosAutoTouch') || '';
const iosAutoTouchCount = Number(initialUrlParams.get('iosAutoTouchCount') || 200);
const iosAutoTouchSteps = Number(initialUrlParams.get('iosAutoTouchSteps') || 20);
const iosAutoTouchMoveIntervalMs = Number(initialUrlParams.get('iosAutoTouchMoveIntervalMs') || 16);
const iosAutoTouchPauseMs = Number(initialUrlParams.get('iosAutoTouchPauseMs') || 200);

interface UnifiedDevice {
  id: string;
  platform: string;
  status: string;
  display_name: string;
  meta: any;
  capabilities: string[];
}

type RtcIceConfig = {
  iceServers: RTCIceServer[];
  iceTransportPolicy?: RTCIceTransportPolicy;
};

interface DeviceConnection {
  serial: string;
  state: string; // 'device', 'recovery', 'sideload', 'bootloader', 'unauthorized'
  adb: Adb;
  scrcpyClient?: AdbScrcpyClient<AdbScrcpyOptions3_1<any>>;
  cardElement: HTMLElement;
  screenViewCanvas?: HTMLCanvasElement; // Cached canvas reference
  renderer?: BitmapVideoFrameRenderer;
  decoder?: WebCodecsVideoDecoder;
  properties?: {
    model?: string;
    version?: string;
    brand?: string;
    arch?: string;
  };
}

// Global state
let serverClient: AdbServerClient | undefined;
const connectedDevices = new Map<string, DeviceConnection>();
let availableDevices: AdbServerClient.Device[] = [];
let currentModalDevice: string | null = null;
let currentSelectedSerial: string | null = null;
let modalAbortController: AbortController | null = null;
let scrcpyServerBinary: Uint8Array | null = null;
const syncDisabledForDevice = new Set<string>();

let iosDevices: UnifiedDevice[] = [];
let iosDevicesSignature = '';
let iosPollTimer: number | undefined;
let iosPlayer: any | undefined;
let iosZx: TLinkautoWsClient | undefined;
let iosScreenSize: { width: number; height: number } = { width: 375, height: 667 };
let iosPointerActive = false;
let iosActivePointerId: number | undefined;
let iosGestureSeq = 0;
let iosGestureMoveCount = 0;
let iosLastMoveAt = 0;
let iosCurrentDeviceId: string | undefined;
let iosCurrentWsBase: string | undefined;
let iosLiveChaseTimer: number | undefined;
let iosPendingMove: { x: number; y: number } | undefined;
let iosMovePumpTimer: number | undefined;
let iosEphemeralCloseTimer: number | undefined;
let iosAutoTouchRunId = 0;
let iosAutoTouchRunning = false;
let iosCurrentDevice: UnifiedDevice | undefined;
let iosLastSentMove: { x: number; y: number } | undefined;
let iosLastMoveSentAt = 0;
let iosTouchMoveIntervalMs = 16;
let iosRtcTouchThrottleUntil = 0;
type IosStreamProfile = 'fast' | 'rtc' | 'worker' | 'eco';
let iosStreamProfile: IosStreamProfile = 'rtc';
let iosH264Socket: WebSocket | undefined;
let iosH264Decoder: VideoDecoder | undefined;
let iosH264RunId = 0;
let iosH264Worker: Worker | undefined;
let iosOffscreenCanvas: OffscreenCanvas | undefined;
let iosWorkerCanvasTransferred = false;
let iosRtcPeer: RTCPeerConnection | undefined;
let iosRtcRunId = 0;
let iosRtcHttpBase: string | undefined;
let iosRtcDeviceId: string | undefined;
let iosRtcSelectedProfile = 'auto';
let iosRtcSelectedPort = 0;
let iosRtcStatsTimer: number | undefined;
let iosRtcStatsLogAt = 0;
let iosRtcLastStats: {
  at: number;
  framesDecoded: number;
  bytesReceived: number;
  freezes: number;
} | undefined;
let iosRtcRecoveryTimer: number | undefined;
let iosRtcLastRecoveryAt = 0;

type IosH264FrameMeta = {
  version: 1 | 2;
  frameId: number;
  key: boolean;
  timestamp: number;
  captureStartUs?: number;
  captureDoneUs?: number;
  encodeDoneUs?: number;
  deviceSendUs?: number;
  browserRecvMs: number;
  decodeSubmitMs?: number;
  payloadBytes: number;
};

type IosLatencyStats = {
  frames: number;
  submitted: number;
  rendered: number;
  dropped: number;
  sourceMs: number;
  captureMs: number;
  encodeMs: number;
  sendToBrowserMs: number;
  browserMs: number;
  decodeMs: number;
  drawMs: number;
  totalApproxMs: number;
  queue: number;
  inFlight: number;
  fps: number;
  bytesPerSec: number;
  lastFrameId: number;
};

let iosLatencyStats: IosLatencyStats | undefined;
let iosLatencyLogAt = 0;

function setIosMode(profile: IosStreamProfile) {
  iosStreamProfile = profile;
  iosModeFastButton?.classList.toggle('active', profile === 'fast');
  iosModeRtcButton?.classList.toggle('active', profile === 'rtc');
  iosModeWorkerButton?.classList.toggle('active', profile === 'worker');
  iosModeEcoButton?.classList.toggle('active', profile === 'eco');
}

function iosBrowserSupportsRtc() {
  return typeof RTCPeerConnection !== 'undefined';
}

function iosDeviceSupportsRtc(device?: UnifiedDevice) {
  if (!device) return true;
  return device.capabilities?.includes('stream_rtc_auto') === true;
}

function getDefaultIosControlProfile(device?: UnifiedDevice): IosStreamProfile {
  return iosBrowserSupportsRtc() && iosDeviceSupportsRtc(device) ? 'rtc' : 'fast';
}

async function ensureIosZxOpen(timeoutMs = 800): Promise<boolean> {
  if (iosEphemeralCloseTimer !== undefined) {
    clearTimeout(iosEphemeralCloseTimer);
    iosEphemeralCloseTimer = undefined;
  }
  if (iosZx && iosZx.isOpen() && !iosZx.isStale()) return true;
  if (!iosCurrentWsBase || !iosCurrentDeviceId) return false;

  try {
    try {
    iosZx?.close();
    } catch {}
    iosZx = new TLinkautoWsClient(`${iosCurrentWsBase}/ios/${encodeURIComponent(iosCurrentDeviceId)}/tlinkauto`);
    await iosZx.waitOpen(timeoutMs);
    console.log('[ios-tlinkauto] connected', iosControlMode);
    return true;
  } catch {
    console.error('[ios-tlinkauto] connect failed', iosControlMode);
    return false;
  }
}

function scheduleIosEphemeralControlClose(delayMs = 500) {
  if (iosControlMode !== 'ephemeral') return;
  if (iosEphemeralCloseTimer !== undefined) clearTimeout(iosEphemeralCloseTimer);
  iosEphemeralCloseTimer = window.setTimeout(() => {
    iosEphemeralCloseTimer = undefined;
    try {
      iosZx?.close();
      console.log('[ios-tlinkauto] closed ephemeral');
    } catch {}
    iosZx = undefined;
  }, delayMs);
}

function startIosLiveChase() {
  // Prefer mpegts.js built-in live sync.
  if (iosLiveChaseTimer !== undefined) {
    clearInterval(iosLiveChaseTimer);
    iosLiveChaseTimer = undefined;
  }
}

// Global Visibility Flags (for performance)
let isScreenViewVisible = false;
let isDetailViewVisible = false;
let isModalVisible = false;

// ============================================================================
// CRITICAL FIX: Global sync disable flag
// ============================================================================
const syncGloballyDisabled = { value: false };

// ============================================================================
// Clipboard sync state - prevent feedback loops
// ============================================================================
const clipboardSyncState = new Map<string, { lastDeviceValue: string; lastSyncTime: number }>();
const CLIPBOARD_SYNC_COOLDOWN = 1000; // 1 second cooldown after device->browser sync

let connectSessionStart: number | null = null;
let isConnecting = false;

// ============================================================================
// Screen View State
// ============================================================================
let screenViewMode: 'grid' | 'focus' = 'grid';
let screenPlatform: 'android' | 'ios' = 'android';
let screenScale = 0.8;
const screenViewPane = document.getElementById('screen-view-pane') as HTMLElement;
const screenGrid = document.getElementById('screen-grid') as HTMLDivElement;
const screenZoomInput = document.getElementById('screen-zoom') as HTMLInputElement;
const screenZoomValue = document.getElementById('screen-zoom-value') as HTMLElement;

type IosGridStream = {
  worker: Worker;
  canvas: HTMLCanvasElement;
  deviceId: string;
};

const iosGridStreams = new Map<string, IosGridStream>();
const iosGridSuspendedForControl = new Set<string>();
let iosModalOpenedFromGridDeviceId: string | undefined;

function updateVisibilityState() {
  const activeTab = document.querySelector('.nav-item[data-tab="screen_view"]');
  isScreenViewVisible = !!activeTab && activeTab.classList.contains('active');
  isDetailViewVisible = detailContent.style.display !== 'none' && !!currentSelectedSerial;
  isModalVisible = deviceModal.style.display !== 'none' && !!currentModalDevice;
}

function setStatus(text: string, connected = false) {
  // Slice B: React ConnectionPanel owns the status dot and buttons now.
  // Legacy still calls setStatus through many code paths; we keep it as a
  // store-sync shim until later slices delete each caller.
  syncBridgeStatusFromLegacy(text, connected);
}

// Slice A: mirror legacy connection lifecycle into bridgeStore. The DOM remains
// the source of truth for now; the store is a read-only mirror that future
// React components and services subscribe to. Replaced by direct store writes
// in later slices.
function syncBridgeStatusFromLegacy(text: string, connected: boolean) {
  if (connected) {
    markConnected();
  } else if (isConnecting) {
    markConnecting();
  } else if (/fail/i.test(text)) {
    markError(text);
  } else {
    markDisconnected();
  }
}

function appendShell(text: string) {
  const line = document.createElement('div');
  line.textContent = `> ${text}`;
  shellOutput.appendChild(line);
  shellOutput.scrollTop = shellOutput.scrollHeight;
}

function updateDeviceCount() {
  if (deviceCountLabel) {
    deviceCountLabel.textContent = `Devices Found (${connectedDevices.size})`;
  }
}

function updateIosDeviceCount() {
  if (iosDeviceCountLabel) {
    iosDeviceCountLabel.textContent = `iOS Found (${iosDevices.length})`;
  }
}

function deriveBridgeBases(bridgeWsUrl: string): { httpBase: string; wsBase: string } {
  const u = new URL(bridgeWsUrl);
  const httpProto = u.protocol === 'wss:' || u.protocol === 'https:' ? 'https:' : 'http:';
  const wsProto = u.protocol === 'wss:' || u.protocol === 'https:' ? 'wss:' : 'ws:';

  // If deployed behind a reverse proxy with a prefix, keep it.
  // Example: wss://example.com/prefix/bridge/ -> basePath = /prefix
  let basePath = u.pathname;
  basePath = basePath.replace(/\/bridge\/?$/, '');
  if (basePath.endsWith('/')) basePath = basePath.slice(0, -1);

  return {
    httpBase: `${httpProto}//${u.host}${basePath}`,
    wsBase: `${wsProto}//${u.host}${basePath}`,
  };
}

function normalizeBridgeWebSocketUrl(bridgeUrl: string): string {
  const u = new URL(bridgeUrl.trim());
  u.protocol = u.protocol === 'https:' || u.protocol === 'wss:' ? 'wss:' : 'ws:';
  if (u.pathname.endsWith('/bridge/')) {
    u.pathname = u.pathname.slice(0, -1);
  }
  return u.toString().replace(/\/$/, '');
}

async function refreshIosDevices() {
  if (!iosDevicesContainer) return;
  const bridgeWsUrl = endpointInput?.value?.trim();
  if (!bridgeWsUrl) return;

  let httpBase: string;
  try {
    ({ httpBase } = deriveBridgeBases(bridgeWsUrl));
  } catch {
    return;
  }

  try {
    const resp = await fetch(`${httpBase}/devices`, { cache: 'no-store' });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const devices = (await resp.json()) as UnifiedDevice[];
    const nextIosDevices = devices.filter(d => d.platform === 'ios');
    const nextSignature = iosDeviceSignature(nextIosDevices);
    if (nextSignature !== iosDevicesSignature) {
      iosDevices = nextIosDevices;
      iosDevicesSignature = nextSignature;
      // Slice A: mirror into iosDeviceStore so React components in later slices
      // can subscribe instead of re-implementing the fetch loop.
      iosDeviceStore.setState({
        devices: nextIosDevices,
        signature: nextSignature,
        lastRefreshAt: performance.now(),
        lastError: undefined,
      });
      renderIosDevices();
      if (screenPlatform === 'ios' && isScreenViewVisible) renderScreenView();
    }
  } catch (e) {
    if (iosDevicesSignature !== '') {
      iosDevices = [];
      iosDevicesSignature = '';
      iosDeviceStore.setState({
        devices: [],
        signature: '',
        lastError: String(e),
        lastRefreshAt: performance.now(),
      });
      renderIosDevices();
      if (screenPlatform === 'ios' && isScreenViewVisible) renderScreenView();
    }
  }
}

function iosDeviceSignature(devices: UnifiedDevice[]) {
  return devices
    .map(d => `${d.id}|${d.status}|${d.display_name}|${d.meta?.ip || ''}|${d.meta?.device?.system_version || ''}`)
    .sort()
    .join('\n');
}

function renderIosDevices() {
  if (!iosDevicesContainer) return;
  iosDevicesContainer.innerHTML = '';

  if (iosDevices.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty-state';
    empty.innerHTML = '<div class="empty-icon">🍎</div><h3>No iOS Devices</h3><p>Make sure the iPhone service is reachable on TCP 6000.</p>';
    iosDevicesContainer.appendChild(empty);
    updateIosDeviceCount();
    return;
  }

  for (const d of iosDevices) {
    const clone = iosDeviceCardTemplate.content.cloneNode(true) as DocumentFragment;
    const card = clone.querySelector('.device-card') as HTMLElement;
    const name = clone.querySelector('.card-name') as HTMLElement;
    const meta = clone.querySelector('.device-meta') as HTMLElement;
    const badge = clone.querySelector('.status-badge') as HTMLElement;
    const thumb = clone.querySelector('.card-thumb-img') as HTMLImageElement;
    const viewBtn = clone.querySelector('.btn-view-stream') as HTMLButtonElement;

    card.dataset.iosId = d.id;
    name.textContent = d.display_name || d.id;

    const info = d.meta?.device;
    const ip = d.meta?.ip;
    if (info) {
      meta.textContent = `${info.model || 'iPhone'} • iOS ${info.system_version || '--'} • ${ip || '--'}`;
    } else {
      meta.textContent = `iOS • ${ip || '--'}`;
    }

    const online = d.status === 'online';
    badge.textContent = online ? 'ONLINE' : 'OFFLINE';
    badge.className = `status-badge ${online ? 'badge-online' : 'badge-offline'}`;
    thumb.src = "https://images.unsplash.com/photo-1616348436168-de43ad0db179?auto=format&fit=crop&q=80&w=400";

    card.addEventListener('dblclick', () => openIosStream(d, getDefaultIosControlProfile(d)));
    viewBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      openIosStream(d, getDefaultIosControlProfile(d));
    });

    iosDevicesContainer.appendChild(clone);
  }

  updateIosDeviceCount();
}

function destroyIosPlayer() {
  iosAutoTouchRunId += 1;
  iosH264RunId += 1;
  iosRtcRunId += 1;
  iosAutoTouchRunning = false;
  stopIosRtcPlayer();

  try {
    iosH264Worker?.postMessage({ type: 'stop' });
  } catch {}

  try {
    iosH264Socket?.close();
  } catch {}
  iosH264Socket = undefined;

  try {
    iosH264Decoder?.close();
  } catch {}
  iosH264Decoder = undefined;

  // mpegts.js needs a full teardown to ensure the underlying WebSocket
  // closes promptly (the iOS stream server allows only one client).
  try {
    iosPlayer?.unload?.();
  } catch {}
  try {
    iosPlayer?.detachMediaElement?.();
  } catch {}
  try {
    iosPlayer?.destroy?.();
  } catch {}
  iosPlayer = undefined;

  if (iosLiveChaseTimer !== undefined) {
    clearInterval(iosLiveChaseTimer);
    iosLiveChaseTimer = undefined;
  }

  try {
    iosZx?.close();
  } catch {}
  iosZx = undefined;
  if (iosEphemeralCloseTimer !== undefined) {
    clearTimeout(iosEphemeralCloseTimer);
    iosEphemeralCloseTimer = undefined;
  }
  iosCurrentDeviceId = undefined;
  iosCurrentWsBase = undefined;
  iosCurrentDevice = undefined;
  iosPointerActive = false;
  iosActivePointerId = undefined;
  iosPendingMove = undefined;
  iosLastSentMove = undefined;
  iosLastMoveSentAt = 0;
  iosGestureMoveCount = 0;
  iosTouchMoveIntervalMs = 16;
  iosRtcTouchThrottleUntil = 0;
  if (iosMovePumpTimer !== undefined) {
    clearInterval(iosMovePumpTimer);
    iosMovePumpTimer = undefined;
  }

  try {
    if (iosVideo.srcObject instanceof MediaStream) {
      for (const track of iosVideo.srcObject.getTracks()) track.stop();
      iosVideo.srcObject = null;
    }
    iosVideo.pause();
    iosVideo.removeAttribute('src');
    iosVideo.load();
  } catch {}

  if (iosCanvas) {
    const ctx = iosCanvas.getContext('2d');
    ctx?.clearRect(0, 0, iosCanvas.width || 1, iosCanvas.height || 1);
    iosCanvas.style.display = 'none';
  }
  if (iosWorkerCanvas) {
    iosWorkerCanvas.style.display = 'none';
  }
  if (iosLatencyOverlay) {
    iosLatencyOverlay.style.display = 'none';
    iosLatencyOverlay.textContent = 'Waiting for metrics...';
  }
  iosLatencyStats = undefined;
  iosLatencyLogAt = 0;
  if (iosVideo) iosVideo.style.display = 'block';
}

function appendBytes(a: Uint8Array, b: Uint8Array) {
  if (a.length === 0) return b;
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function msFromUsDelta(endUs?: number, startUs?: number) {
  if (endUs === undefined || startUs === undefined) return 0;
  return Math.max(0, (endUs - startUs) / 1000);
}

function smooth(previous: number, next: number, alpha = 0.18) {
  if (!Number.isFinite(previous) || previous <= 0) return next;
  return previous * (1 - alpha) + next * alpha;
}

function updateIosLatencyOverlay() {
  if (!iosLatencyOverlay || !iosLatencyStats) return;
  const s = iosLatencyStats;
  iosLatencyOverlay.style.display = 'block';
  iosLatencyOverlay.textContent =
    `ZXH2 frame ${s.lastFrameId} | ${s.fps.toFixed(1)} fps | ${(s.bytesPerSec / 1024).toFixed(0)} KB/s\n` +
    `source ${s.sourceMs.toFixed(1)} ms = capture ${s.captureMs.toFixed(1)} + encode ${s.encodeMs.toFixed(1)}\n` +
    `net~ ${s.sendToBrowserMs.toFixed(1)} ms | browser ${s.browserMs.toFixed(1)} = decode ${s.decodeMs.toFixed(1)} + draw ${s.drawMs.toFixed(1)}\n` +
    `total~ ${s.totalApproxMs.toFixed(1)} ms | queue ${s.queue} | in-flight ${s.inFlight}\n` +
    `dropped ${s.dropped} | submitted ${s.submitted} | rendered ${s.rendered}/${s.frames}`;
}

function logIosLatencyStats() {
  if (!iosLatencyStats) return;
  console.table({
    frame: iosLatencyStats.lastFrameId,
    fps: Number(iosLatencyStats.fps.toFixed(1)),
    source_ms: Number(iosLatencyStats.sourceMs.toFixed(1)),
    capture_ms: Number(iosLatencyStats.captureMs.toFixed(1)),
    encode_ms: Number(iosLatencyStats.encodeMs.toFixed(1)),
    net_approx_ms: Number(iosLatencyStats.sendToBrowserMs.toFixed(1)),
    browser_ms: Number(iosLatencyStats.browserMs.toFixed(1)),
    decode_ms: Number(iosLatencyStats.decodeMs.toFixed(1)),
    draw_ms: Number(iosLatencyStats.drawMs.toFixed(1)),
    total_approx_ms: Number(iosLatencyStats.totalApproxMs.toFixed(1)),
    decode_queue: iosLatencyStats.queue,
    in_flight: iosLatencyStats.inFlight,
    dropped: iosLatencyStats.dropped,
    submitted: iosLatencyStats.submitted,
    rendered: iosLatencyStats.rendered,
    kbps: Number(((iosLatencyStats.bytesPerSec * 8) / 1000).toFixed(0)),
  });
}

function applyIosWorkerMetrics(m: any) {
  iosLatencyStats = {
    frames: m.frames ?? 0,
    submitted: m.submitted ?? 0,
    rendered: m.rendered ?? 0,
    dropped: m.dropped ?? 0,
    sourceMs: m.source_ms ?? 0,
    captureMs: m.capture_ms ?? 0,
    encodeMs: m.encode_ms ?? 0,
    sendToBrowserMs: m.net_approx_ms ?? 0,
    browserMs: m.browser_ms ?? 0,
    decodeMs: m.decode_ms ?? 0,
    drawMs: m.draw_ms ?? 0,
    totalApproxMs: m.total_approx_ms ?? 0,
    queue: m.decode_queue ?? 0,
    inFlight: m.in_flight ?? 0,
    fps: m.fps ?? 0,
    bytesPerSec: ((m.kbps ?? 0) * 1000) / 8,
    lastFrameId: m.frame ?? 0,
  };
  updateIosLatencyOverlay();

  const now = performance.now();
  if (now - iosLatencyLogAt > 3000) {
    iosLatencyLogAt = now;
    logIosLatencyStats();
  }
}

async function startIosH264WorkerPlayer(streamUrl: string): Promise<boolean> {
  if (!iosWorkerCanvas || !('transferControlToOffscreen' in iosWorkerCanvas) || !('Worker' in window)) return false;

  iosVideo.style.display = 'none';
  iosCanvas.style.display = 'none';
  iosWorkerCanvas.style.display = 'block';

  try {
    if (!iosOffscreenCanvas) {
      iosOffscreenCanvas = iosWorkerCanvas.transferControlToOffscreen();
      iosWorkerCanvasTransferred = true;
    }

    if (!iosH264Worker) {
      iosH264Worker = new Worker(new URL('./IosH264Worker.ts', import.meta.url), { type: 'module' });
    }

    const started = await new Promise<boolean>((resolve) => {
      let settled = false;
      const timer = window.setTimeout(() => {
        if (settled) return;
        settled = true;
        resolve(false);
      }, 1500);

      iosH264Worker!.onmessage = (event) => {
        const data = event.data;
        if (data?.type === 'metrics') {
          applyIosWorkerMetrics(data.metrics);
          return;
        }
        if (data?.type === 'decoder-error') {
          console.error('[ios-h264-worker] decoder error', data.error);
          return;
        }
        if (data?.type === 'start-failed') {
          console.error('[ios-h264-worker] start failed', data.reason);
          if (!settled) {
            settled = true;
            clearTimeout(timer);
            resolve(false);
          }
          return;
        }
        if (data?.type === 'started') {
          if (!settled) {
            settled = true;
            clearTimeout(timer);
            resolve(true);
          }
        }
      };

      if (iosWorkerCanvasTransferred && iosOffscreenCanvas) {
        iosH264Worker!.postMessage({ type: 'start', url: streamUrl, canvas: iosOffscreenCanvas }, [iosOffscreenCanvas]);
        iosOffscreenCanvas = undefined;
      } else {
        iosH264Worker!.postMessage({ type: 'start', url: streamUrl });
      }
    });

    if (!started) {
      iosH264Worker?.postMessage({ type: 'stop' });
      iosWorkerCanvas.style.display = 'none';
      iosVideo.style.display = 'block';
      return false;
    }

    return true;
  } catch (e) {
    console.error('[ios-h264-worker] unavailable', e);
    try {
      iosH264Worker?.postMessage({ type: 'stop' });
    } catch {}
    iosWorkerCanvas.style.display = 'none';
    iosVideo.style.display = 'block';
    return false;
  }
}

async function startIosH264Player(streamUrl: string, useWorker = false): Promise<boolean> {
  if (useWorker) {
    return startIosH264WorkerPlayer(streamUrl);
  }

  const runId = ++iosH264RunId;

  const VideoDecoderCtor = (window as any).VideoDecoder as typeof VideoDecoder | undefined;
  const EncodedVideoChunkCtor = (window as any).EncodedVideoChunk as typeof EncodedVideoChunk | undefined;
  if (!VideoDecoderCtor || !EncodedVideoChunkCtor || !iosCanvas) return false;

  const ctx = iosCanvas.getContext('2d', { alpha: false });
  if (!ctx) return false;

  iosVideo.style.display = 'none';
  if (iosWorkerCanvas) iosWorkerCanvas.style.display = 'none';
  iosCanvas.style.display = 'block';

  let configured = false;
  let pending = new Uint8Array(0);
  let lastTimestamp = 0;
  let firstSourceTimestampUs: number | undefined;
  let fallbackFrameId = 0;
  let deviceToBrowserOffsetMs: number | undefined;
  let statWindowStarted = performance.now();
  let statWindowFrames = 0;
  let statWindowBytes = 0;
  const metaByTimestamp = new Map<number, IosH264FrameMeta>();
  let inFlightFrames = 0;
  let settled = false;
  let sawFrame = false;
  let settleStart: (ok: boolean) => void = () => {};
  const startPromise = new Promise<boolean>((resolve) => {
    settleStart = (ok) => {
      if (settled) return;
      settled = true;
      resolve(ok);
    };
  });
  const startTimer = window.setTimeout(() => {
    if (runId !== iosH264RunId) return;
    settleStart(false);
    try {
      socket.close();
    } catch {}
  }, 1500);

  const decoder = new VideoDecoderCtor({
    output(frame) {
      if (runId !== iosH264RunId) {
        frame.close();
        return;
      }
      const outputStartMs = performance.now();
      const meta = metaByTimestamp.get(frame.timestamp);
      if (meta) metaByTimestamp.delete(frame.timestamp);
      try {
        const width = frame.displayWidth || frame.codedWidth;
        const height = frame.displayHeight || frame.codedHeight;
        if (iosCanvas.width !== width || iosCanvas.height !== height) {
          iosCanvas.width = width;
          iosCanvas.height = height;
        }
        ctx.drawImage(frame, 0, 0, iosCanvas.width, iosCanvas.height);
        const renderDoneMs = performance.now();
        if (meta && iosLatencyStats) {
          iosLatencyStats.rendered += 1;
          const decodeMs = Math.max(0, outputStartMs - (meta.decodeSubmitMs ?? meta.browserRecvMs));
          const drawMs = Math.max(0, renderDoneMs - outputStartMs);
          const browserMs = decodeMs + drawMs;
          iosLatencyStats.decodeMs = smooth(iosLatencyStats.decodeMs, decodeMs);
          iosLatencyStats.drawMs = smooth(iosLatencyStats.drawMs, drawMs);
          iosLatencyStats.browserMs = smooth(iosLatencyStats.browserMs, browserMs);
          iosLatencyStats.totalApproxMs = smooth(
            iosLatencyStats.totalApproxMs,
            iosLatencyStats.sourceMs + iosLatencyStats.sendToBrowserMs + browserMs
          );
          updateIosLatencyOverlay();
        }
      } finally {
        inFlightFrames = Math.max(0, inFlightFrames - 1);
        if (iosLatencyStats) iosLatencyStats.inFlight = inFlightFrames;
        frame.close();
      }
    },
    error(e) {
      console.error('[ios-h264] decoder error', e);
    },
  });
  iosH264Decoder = decoder;

  const configureDecoder = () => {
    if (configured || runId !== iosH264RunId) return;
    const realtimeConfig = {
      codec: 'avc1.42E01E',
      optimizeForLatency: true,
      latencyMode: 'realtime',
      hardwareAcceleration: 'prefer-hardware',
      avc: { format: 'annexb' },
    } as any;

    try {
      decoder.configure(realtimeConfig);
    } catch (e) {
      console.warn('[ios-h264] realtime decoder config failed, using fallback', e);
      decoder.configure({
        codec: 'avc1.42E01E',
        optimizeForLatency: true,
        avc: { format: 'annexb' },
      } as any);
    }
    configured = true;
  };

  const socket = new WebSocket(streamUrl);
  iosH264Socket = socket;
  socket.binaryType = 'arraybuffer';

  socket.onmessage = (ev) => {
    if (runId !== iosH264RunId || socket !== iosH264Socket || decoder !== iosH264Decoder) return;
    const browserRecvMs = performance.now();
    const chunk = new Uint8Array(ev.data as ArrayBuffer);
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
        try {
          configureDecoder();
        } catch (e) {
          console.error('[ios-h264] configure failed', e);
          settleStart(false);
          socket.close();
          return;
        }
      }

      if (firstSourceTimestampUs === undefined) {
        firstSourceTimestampUs = timestamp;
      }
      const relativeTimestamp = Math.max(0, timestamp - firstSourceTimestampUs);
      lastTimestamp = relativeTimestamp > lastTimestamp ? relativeTimestamp : lastTimestamp + 1;
      const decodeSubmitMs = performance.now();
      const meta: IosH264FrameMeta = {
        version,
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
      };

      if (deviceSendUs !== undefined && deviceToBrowserOffsetMs === undefined) {
        deviceToBrowserOffsetMs = browserRecvMs - deviceSendUs / 1000;
      }

      if (!iosLatencyStats) {
        iosLatencyStats = {
          frames: 0,
          submitted: 0,
          rendered: 0,
          dropped: 0,
          sourceMs: 0,
          captureMs: 0,
          encodeMs: 0,
          sendToBrowserMs: 0,
          browserMs: 0,
          decodeMs: 0,
          drawMs: 0,
          totalApproxMs: 0,
          queue: 0,
          inFlight: 0,
          fps: 0,
          bytesPerSec: 0,
          lastFrameId: frameId,
        };
      }

      iosLatencyStats.frames += 1;
      iosLatencyStats.lastFrameId = frameId;
      iosLatencyStats.captureMs = smooth(iosLatencyStats.captureMs, msFromUsDelta(captureDoneUs, captureStartUs));
      iosLatencyStats.encodeMs = smooth(iosLatencyStats.encodeMs, msFromUsDelta(encodeDoneUs, captureDoneUs));
      iosLatencyStats.sourceMs = smooth(iosLatencyStats.sourceMs, msFromUsDelta(deviceSendUs, captureStartUs));
      if (deviceSendUs !== undefined && deviceToBrowserOffsetMs !== undefined) {
        const networkApprox = Math.max(0, browserRecvMs - (deviceSendUs / 1000 + deviceToBrowserOffsetMs));
        iosLatencyStats.sendToBrowserMs = smooth(iosLatencyStats.sendToBrowserMs, networkApprox);
      }

      if (decoder.state !== 'configured') return;
      iosLatencyStats.queue = decoder.decodeQueueSize;
      iosLatencyStats.inFlight = inFlightFrames;

      statWindowFrames += 1;
      statWindowBytes += payloadLength;
      const statElapsed = browserRecvMs - statWindowStarted;
      if (statElapsed >= 1000) {
        iosLatencyStats.fps = (statWindowFrames * 1000) / statElapsed;
        iosLatencyStats.bytesPerSec = (statWindowBytes * 1000) / statElapsed;
        statWindowFrames = 0;
        statWindowBytes = 0;
        statWindowStarted = browserRecvMs;
      }

      metaByTimestamp.set(lastTimestamp, meta);
      try {
        inFlightFrames += 1;
        iosLatencyStats.inFlight = inFlightFrames;
        iosLatencyStats.submitted += 1;
        decoder.decode(new EncodedVideoChunkCtor({
          type: isKey ? 'key' : 'delta',
          timestamp: lastTimestamp,
          data: payload,
        }));
        if (!sawFrame) {
          sawFrame = true;
          clearTimeout(startTimer);
          settleStart(true);
        }
        updateIosLatencyOverlay();
        if (browserRecvMs - iosLatencyLogAt > 3000) {
          iosLatencyLogAt = browserRecvMs;
          logIosLatencyStats();
        }
      } catch (e) {
        inFlightFrames = Math.max(0, inFlightFrames - 1);
        iosLatencyStats.inFlight = inFlightFrames;
        metaByTimestamp.delete(lastTimestamp);
        console.error('[ios-h264] decode submit failed', e);
        settleStart(false);
        socket.close();
        return;
      }
    }
  };

  socket.onerror = (e) => {
    if (runId !== iosH264RunId || socket !== iosH264Socket) return;
    console.error('[ios-h264] ws error', e);
    clearTimeout(startTimer);
    settleStart(false);
  };

  socket.onclose = () => {
    if (runId !== iosH264RunId || socket !== iosH264Socket) return;
    if (!sawFrame) {
      clearTimeout(startTimer);
      settleStart(false);
    }
  };

  const ok = await startPromise;
  if (!ok) {
    try {
      decoder.close();
    } catch {}
    if (iosH264Decoder === decoder) iosH264Decoder = undefined;
    if (iosH264Socket === socket) iosH264Socket = undefined;
    iosCanvas.style.display = 'none';
    iosVideo.style.display = 'block';
  }
  return ok;
}

async function waitIceGatheringComplete(pc: RTCPeerConnection, timeoutMs = 3000) {
  if (pc.iceGatheringState === 'complete') return;
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
    new Promise<void>((resolve) => window.setTimeout(resolve, timeoutMs)),
  ]);
}

async function fetchRtcIceConfig(httpBase: string): Promise<RtcIceConfig> {
  try {
    const url = `${httpBase}/rtc/config${iosRtcForceRelay ? '?forceRelay=1' : ''}`;
    console.log('[ios-rtc] fetching ICE config', url);
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const config = await resp.json();
    const iceServers = Array.isArray(config.iceServers) ? config.iceServers : [];
    const policy = config.iceTransportPolicy === 'relay' ? 'relay' : 'all';
    return { iceServers, iceTransportPolicy: policy };
  } catch (e) {
    console.warn('[ios-rtc] ICE config unavailable, using local defaults', e);
    return {
      iceServers: [],
      iceTransportPolicy: iosRtcForceRelay ? 'relay' : 'all',
    };
  }
}

function stopIosRtcPlayer() {
  iosRtcRunId += 1;
  if (iosRtcRecoveryTimer !== undefined) {
    clearTimeout(iosRtcRecoveryTimer);
    iosRtcRecoveryTimer = undefined;
  }
  const closeUrl = iosRtcHttpBase && iosRtcDeviceId
    ? `${iosRtcHttpBase}/ios/${encodeURIComponent(iosRtcDeviceId)}/rtc/close`
    : undefined;
  iosRtcHttpBase = undefined;
  iosRtcDeviceId = undefined;
  iosRtcSelectedProfile = 'auto';
  iosRtcSelectedPort = 0;

  if (closeUrl) {
    try {
      if (!navigator.sendBeacon(closeUrl, new Blob())) {
        fetch(closeUrl, { method: 'POST', keepalive: true }).catch(() => {});
      }
    } catch {
      fetch(closeUrl, { method: 'POST', keepalive: true }).catch(() => {});
    }
  }

  if (iosRtcStatsTimer !== undefined) {
    clearInterval(iosRtcStatsTimer);
    iosRtcStatsTimer = undefined;
  }
  iosRtcStatsLogAt = 0;
  iosRtcLastStats = undefined;

  const pc = iosRtcPeer;
  iosRtcPeer = undefined;
  if (pc) {
    try {
      pc.ontrack = null;
      pc.onconnectionstatechange = null;
      pc.oniceconnectionstatechange = null;
    } catch {}
    try {
      for (const receiver of pc.getReceivers()) receiver.track?.stop();
    } catch {}
    try {
      for (const sender of pc.getSenders()) sender.track?.stop();
    } catch {}
    try {
      pc.close();
    } catch {}
  }

  try {
    if (iosVideo.srcObject instanceof MediaStream) {
      for (const track of iosVideo.srcObject.getTracks()) track.stop();
      iosVideo.srcObject = null;
    }
  } catch {}
}

function scheduleIosRtcRecovery(reason: string) {
  if (iosStreamProfile !== 'rtc') return;
  if (!iosCurrentDevice) return;
  const now = performance.now();
  if (iosRtcRecoveryTimer !== undefined) return;
  if (now - iosRtcLastRecoveryAt < 5000) return;
  iosRtcLastRecoveryAt = now;
  console.warn('[ios-rtc] recovery scheduled', reason);
  iosRtcRecoveryTimer = window.setTimeout(() => {
    iosRtcRecoveryTimer = undefined;
    if (iosStreamProfile !== 'rtc' || !iosCurrentDevice) return;
    openIosStream(iosCurrentDevice, 'rtc');
  }, 250);
}

function startIosRtcStats(pc: RTCPeerConnection) {
  if (iosRtcStatsTimer !== undefined) clearInterval(iosRtcStatsTimer);
  iosRtcLastStats = undefined;
  iosRtcStatsLogAt = 0;
  if (iosLatencyOverlay) {
    iosLatencyOverlay.style.display = 'block';
    iosLatencyOverlay.textContent = 'RTC waiting for stats...';
  }

  iosRtcStatsTimer = window.setInterval(async () => {
    if (pc !== iosRtcPeer || pc.connectionState === 'closed') return;

      try {
        const stats = await pc.getStats();
        let inbound: any;
        let selectedPair: any;
        const reports = new Map<string, any>();
        stats.forEach((report: any) => {
          reports.set(report.id, report);
          if (report.type === 'inbound-rtp' && report.kind === 'video' && !report.isRemote) {
            inbound = report;
          }
          if (report.type === 'transport' && report.selectedCandidatePairId) {
            selectedPair = stats.get(report.selectedCandidatePairId);
          }
          if (report.type === 'candidate-pair' && report.selected) {
            selectedPair = report;
          }
        });
        if (!inbound) return;

        const localCandidate = selectedPair?.localCandidateId ? reports.get(selectedPair.localCandidateId) : undefined;
        const remoteCandidate = selectedPair?.remoteCandidateId ? reports.get(selectedPair.remoteCandidateId) : undefined;
        const localCandidateType = localCandidate?.candidateType || '--';
        const remoteCandidateType = remoteCandidate?.candidateType || '--';
        const roundTripMs = selectedPair?.currentRoundTripTime ? selectedPair.currentRoundTripTime * 1000 : 0;

      const now = performance.now();
      const framesDecoded = inbound.framesDecoded ?? 0;
      const bytesReceived = inbound.bytesReceived ?? 0;
      const elapsedSec = iosRtcLastStats ? Math.max(0.001, (now - iosRtcLastStats.at) / 1000) : 0;
      const fps = iosRtcLastStats ? (framesDecoded - iosRtcLastStats.framesDecoded) / elapsedSec : 0;
      const bitrateKbps = iosRtcLastStats ? ((bytesReceived - iosRtcLastStats.bytesReceived) * 8) / elapsedSec / 1000 : 0;

      const jitterMs = (inbound.jitter ?? 0) * 1000;
      const dropped = inbound.framesDropped ?? 0;
      const freezes = inbound.freezeCount ?? 0;
      const previousFreezes = iosRtcLastStats?.freezes ?? freezes;
      const framesReceived = inbound.framesReceived ?? 0;
      const keyFramesDecoded = inbound.keyFramesDecoded ?? 0;
      const pliCount = inbound.pliCount ?? 0;
      const nackCount = inbound.nackCount ?? 0;
      const firCount = inbound.firCount ?? 0;
      const packetsLost = inbound.packetsLost ?? 0;
      const jitterBufferMs = inbound.jitterBufferEmittedCount > 0
        ? ((inbound.jitterBufferDelay ?? 0) * 1000) / inbound.jitterBufferEmittedCount
        : 0;
      const jitterBufferTargetMs = inbound.jitterBufferEmittedCount > 0
        ? ((inbound.jitterBufferTargetDelay ?? 0) * 1000) / inbound.jitterBufferEmittedCount
        : 0;
      const jitterBufferMinMs = inbound.jitterBufferEmittedCount > 0
        ? ((inbound.jitterBufferMinimumDelay ?? 0) * 1000) / inbound.jitterBufferEmittedCount
        : 0;
      const interFrameDelayMs = framesDecoded > 0
        ? ((inbound.totalInterFrameDelay ?? 0) * 1000) / framesDecoded
        : 0;
      const freezeDurationMs = (inbound.totalFreezesDuration ?? 0) * 1000;
      const estimatedPlayoutMs = inbound.estimatedPlayoutTimestamp
        ? inbound.estimatedPlayoutTimestamp - performance.timeOrigin
        : 0;
      const decodeMs = framesDecoded > 0 ? ((inbound.totalDecodeTime ?? 0) * 1000) / framesDecoded : 0;
      iosRtcLastStats = { at: now, framesDecoded, bytesReceived, freezes };

      if (freezes > previousFreezes) {
        console.warn('[ios-rtc] freeze detected', `${previousFreezes}->${freezes}`);
      }

      if (iosLatencyOverlay) {
        iosLatencyOverlay.style.display = 'block';
        iosLatencyOverlay.textContent =
          `RTC ${iosRtcSelectedProfile.toUpperCase()} ${fps.toFixed(1)} fps | ${(bitrateKbps / 1000).toFixed(2)} Mbps | state ${pc.connectionState}\n` +
          `recv ${framesReceived} | decoded ${framesDecoded} | key ${keyFramesDecoded} | drop ${dropped} | freeze ${freezes}\n` +
          `ice ${localCandidateType}->${remoteCandidateType} | rtt ${roundTripMs.toFixed(1)} ms\n` +
          `jitter ${jitterMs.toFixed(1)} ms | jb ${jitterBufferMs.toFixed(1)}/${jitterBufferTargetMs.toFixed(1)} ms | inter ${interFrameDelayMs.toFixed(1)} ms | decode ${decodeMs.toFixed(2)} ms`;
      }

      if (now - iosRtcStatsLogAt > 3000) {
        iosRtcStatsLogAt = now;
        console.table({
          rtc_state: pc.connectionState,
          ice_state: pc.iceConnectionState,
          profile: iosRtcSelectedProfile,
          port: iosRtcSelectedPort,
          local_candidate_type: localCandidateType,
          remote_candidate_type: remoteCandidateType,
          candidate_pair_state: selectedPair?.state || '--',
          current_round_trip_time_ms: Number(roundTripMs.toFixed(1)),
          fps: Number(fps.toFixed(1)),
          touch_move_interval_ms: iosTouchMoveIntervalMs,
          mbps: Number((bitrateKbps / 1000).toFixed(2)),
          frames_received: framesReceived,
          frames_decoded: framesDecoded,
          keyframes_decoded: keyFramesDecoded,
          frames_dropped: dropped,
          freeze_count: freezes,
          pli_count: pliCount,
          nack_count: nackCount,
          fir_count: firCount,
          packets_lost: packetsLost,
          jitter_ms: Number(jitterMs.toFixed(1)),
          jitter_buffer_ms: Number(jitterBufferMs.toFixed(1)),
          jitter_buffer_target_ms: Number(jitterBufferTargetMs.toFixed(1)),
          jitter_buffer_min_ms: Number(jitterBufferMinMs.toFixed(1)),
          inter_frame_delay_ms: Number(interFrameDelayMs.toFixed(1)),
          freeze_duration_ms: Number(freezeDurationMs.toFixed(1)),
          estimated_playout_ms: Number(estimatedPlayoutMs.toFixed(1)),
          avg_decode_ms: Number(decodeMs.toFixed(2)),
        });
      }
    } catch (e) {
      console.error('[ios-rtc] stats failed', e);
    }
  }, 1000);
}

async function startIosRtcPlayer(httpBase: string, deviceId: string): Promise<boolean> {
  if (!('RTCPeerConnection' in window)) return false;
  const runId = ++iosRtcRunId;

  iosVideo.style.display = 'block';
  iosVideo.muted = true;
  iosVideo.playsInline = true;
  iosVideo.autoplay = true;
  if (iosCanvas) iosCanvas.style.display = 'none';
  if (iosWorkerCanvas) iosWorkerCanvas.style.display = 'none';

  try {
    const iceConfig = await fetchRtcIceConfig(httpBase);
    console.log('[ios-rtc] ice config', {
      servers: iceConfig.iceServers.length,
      policy: iceConfig.iceTransportPolicy,
      forceRelay: iosRtcForceRelay,
    });
    const pc = new RTCPeerConnection({
      iceServers: iceConfig.iceServers,
      iceTransportPolicy: iceConfig.iceTransportPolicy ?? 'all',
      bundlePolicy: 'max-bundle',
      rtcpMuxPolicy: 'require',
    });
    iosRtcPeer = pc;
    iosRtcHttpBase = httpBase;
    iosRtcDeviceId = deviceId;

    pc.addTransceiver('video', { direction: 'recvonly' });
    pc.ontrack = (event) => {
      if (runId !== iosRtcRunId || pc !== iosRtcPeer) return;
      try {
        const receiver = event.receiver as RTCRtpReceiver & { jitterBufferTarget?: number };
        if ('jitterBufferTarget' in receiver) receiver.jitterBufferTarget = 0.01;
      } catch {}
      const [stream] = event.streams;
      if (stream) {
        iosVideo.srcObject = stream;
        iosVideo.play().catch(() => {});
      }
    };
    pc.onconnectionstatechange = () => {
      if (runId !== iosRtcRunId || pc !== iosRtcPeer) return;
      console.log('[ios-rtc] connection', pc.connectionState);
    };
    pc.oniceconnectionstatechange = () => {
      if (runId !== iosRtcRunId || pc !== iosRtcPeer) return;
      console.log('[ios-rtc] ice', pc.iceConnectionState);
    };

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await waitIceGatheringComplete(pc);

    const localDescription = pc.localDescription;
    if (!localDescription) throw new Error('missing rtc local description');

    const resp = await fetch(`${httpBase}/ios/${encodeURIComponent(deviceId)}/rtc/offer`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sdp: localDescription, profile: 'auto', iceTransportPolicy: iceConfig.iceTransportPolicy ?? 'all' }),
    });
    if (!resp.ok) {
      const body = await resp.text().catch(() => '');
      throw new Error(`rtc offer failed: HTTP ${resp.status}${body ? `: ${body}` : ''}`);
    }

    const answer = await resp.json();
    if (runId !== iosRtcRunId || pc !== iosRtcPeer || pc.signalingState === 'closed') {
      try { pc.close(); } catch {}
      return false;
    }
    iosRtcSelectedProfile = answer.profile || 'auto';
    iosRtcSelectedPort = answer.port || 0;
    console.log('[ios-rtc] selected profile', iosRtcSelectedProfile, 'port', iosRtcSelectedPort);
    await pc.setRemoteDescription(answer.sdp);
    if (runId !== iosRtcRunId || pc !== iosRtcPeer || pc.connectionState === 'closed') return false;
    startIosRtcStats(pc);
    return true;
  } catch (e) {
    console.error('[ios-rtc] start failed', e);
    stopIosRtcPlayer();
    return false;
  }
}

function startIosMovePump() {
  if (iosMovePumpTimer !== undefined) return;
  iosMovePumpTimer = window.setInterval(() => {
    if (!iosPointerActive) return;
    if (!iosPendingMove) return;
    if (!iosZx || !iosZx.isOpen()) return;
    const now = performance.now();
    if (now - iosLastMoveSentAt < iosTouchMoveIntervalMs) return;

    // Only send the latest MOVE; drop backlog to avoid "rubber band" delay.
    const { x, y } = iosPendingMove;
    const sent = iosZx.tryTouchMove(1, x, y);
    if (sent) {
      iosLastSentMove = { x, y };
      iosLastMoveSentAt = now;
      iosGestureMoveCount += 1;
      iosPendingMove = undefined;
    }
  }, 25);
}

function delayMs(ms: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, ms));
}

async function runIosAutoSwipePoints(runId: number, startY: number, endY: number) {
  if (!iosZx?.isOpen()) return;
  const x = iosScreenSize.width / 2;
  iosZx.touch(1, 1, x, startY);
  await delayMs(30);

  const steps = Math.max(1, iosAutoTouchSteps);
  for (let i = 1; i <= steps; i += 1) {
    if (runId !== iosAutoTouchRunId || !iosZx?.isOpen()) return;
    const t = i / steps;
    const y = startY + (endY - startY) * t;
    iosZx.touch(2, 1, x, y);
    await delayMs(iosAutoTouchMoveIntervalMs);
  }

  if (runId === iosAutoTouchRunId && iosZx?.isOpen()) {
    iosZx.touch(0, 1, x, endY);
  }
}

async function runIosAutoTouchTest() {
  if (!iosAutoTouchMode || iosAutoTouchRunning || iosDisableControlForTest) return;
  if (iosStreamProfile !== 'rtc') return;

  const runId = ++iosAutoTouchRunId;
  iosAutoTouchRunning = true;
  console.warn('[ios-auto-touch] started', {
    mode: iosAutoTouchMode,
    count: iosAutoTouchCount,
    steps: iosAutoTouchSteps,
    moveIntervalMs: iosAutoTouchMoveIntervalMs,
    pauseMs: iosAutoTouchPauseMs,
  });

  try {
    const ok = await ensureIosZxOpen(1200);
    if (!ok) {
      console.error('[ios-auto-touch] TLinkauto unavailable');
      return;
    }
    const size = await iosZx?.getScreenSize();
    if (size) iosScreenSize = size;

    const startY = iosScreenSize.height * 0.85;
    const endY = iosScreenSize.height * 0.25;
    const tapY = iosScreenSize.height * 0.5;
    const x = iosScreenSize.width / 2;

    for (let i = 0; i < iosAutoTouchCount; i += 1) {
      if (runId !== iosAutoTouchRunId || iosStreamProfile !== 'rtc') break;
      if (!iosZx?.isOpen()) {
        const reopened = await ensureIosZxOpen(1200);
        if (!reopened) {
          console.error('[ios-auto-touch] reconnect failed at', i + 1);
          break;
        }
      }

      if (iosAutoTouchMode === 'tap') {
        iosZx?.touch(1, 1, x, tapY);
        await delayMs(80);
        iosZx?.touch(0, 1, x, tapY);
      } else if (iosAutoTouchMode === 'pan') {
        iosZx?.touch(1, 1, x, startY);
        await delayMs(30);
        let currentY = startY;
        for (let cycle = 0; cycle < 4; cycle += 1) {
          const targetY = cycle % 2 === 0 ? endY : startY;
          for (let step = 1; step <= Math.max(1, iosAutoTouchSteps); step += 1) {
            if (runId !== iosAutoTouchRunId || !iosZx?.isOpen()) break;
            const t = step / Math.max(1, iosAutoTouchSteps);
            const y = currentY + (targetY - currentY) * t;
            iosZx.touch(2, 1, x, y);
            await delayMs(iosAutoTouchMoveIntervalMs);
          }
          currentY = targetY;
          await delayMs(120);
        }
        iosZx?.touch(0, 1, x, currentY);
      } else if (iosAutoTouchMode === 'bounce') {
        await runIosAutoSwipePoints(runId, startY, endY);
        await delayMs(120);
        await runIosAutoSwipePoints(runId, endY, startY);
      } else {
        await runIosAutoSwipePoints(runId, startY, endY);
      }

      console.log('[ios-auto-touch]', iosAutoTouchMode, `${i + 1}/${iosAutoTouchCount}`);
      await delayMs(iosAutoTouchPauseMs);
    }
  } finally {
    if (runId === iosAutoTouchRunId) {
      iosAutoTouchRunning = false;
      scheduleIosEphemeralControlClose();
      console.warn('[ios-auto-touch] finished');
    }
  }
}

function closeIosStream() {
  const resumeGridDeviceId = iosModalOpenedFromGridDeviceId;
  destroyIosPlayer();
  iosStreamModal.style.display = 'none';
  iosModalOpenedFromGridDeviceId = undefined;

  if (resumeGridDeviceId && screenPlatform === 'ios' && isScreenViewVisible) {
    iosGridSuspendedForControl.delete(resumeGridDeviceId);
    renderScreenView();
  }
}

function stopIosGridStream(deviceId: string) {
  const stream = iosGridStreams.get(deviceId);
  if (!stream) return;
  try {
    stream.worker.postMessage({ type: 'stop' });
  } catch {}
  try {
    stream.worker.terminate();
  } catch {}
  iosGridStreams.delete(deviceId);
}

function stopAllIosGridStreams() {
  for (const id of Array.from(iosGridStreams.keys())) {
    stopIosGridStream(id);
  }
}

function startIosGridWorkerStream(device: UnifiedDevice, canvas: HTMLCanvasElement) {
  if (!iosCurrentWsBase && endpointInput?.value?.trim()) {
    try {
      iosCurrentWsBase = deriveBridgeBases(endpointInput.value.trim()).wsBase;
    } catch {}
  }

  const bridgeWsUrl = endpointInput?.value?.trim();
  if (!bridgeWsUrl) return;

  let httpBase: string;
  let wsBase: string;
  try {
    ({ httpBase, wsBase } = deriveBridgeBases(bridgeWsUrl));
  } catch {
    return;
  }

  stopIosGridStream(device.id);

  if (!('transferControlToOffscreen' in canvas) || !('Worker' in window)) return;

  try {
    const offscreen = canvas.transferControlToOffscreen();
    const worker = new Worker(new URL('./IosH264Worker.ts', import.meta.url), { type: 'module' });
    worker.onmessage = (event) => {
      const data = event.data;
      if (data?.type === 'start-failed') {
        console.error('[ios-grid-worker] start failed', device.id, data.reason);
      }
      if (data?.type === 'decoder-error') {
        console.error('[ios-grid-worker] decoder error', device.id, data.error);
      }
    };
    worker.postMessage({
      type: 'start',
      url: `${wsBase}/ios/${encodeURIComponent(device.id)}/h264-worker`,
      canvas: offscreen,
    }, [offscreen]);
    iosGridStreams.set(device.id, { worker, canvas, deviceId: device.id });
  } catch (e) {
    console.error('[ios-grid-worker] unavailable', device.id, e);
  }
}

async function openIosStream(device: UnifiedDevice, profile: IosStreamProfile = getDefaultIosControlProfile(device)) {
  const bridgeWsUrl = endpointInput?.value?.trim();
  if (!bridgeWsUrl) return;

  let httpBase: string;
  let wsBase: string;
  try {
    ({ httpBase, wsBase } = deriveBridgeBases(bridgeWsUrl));
  } catch {
    return;
  }

  // Switching devices/profiles should not clear the new selection.
  destroyIosPlayer();
  // Give the previous TCP/RTC client a moment to disconnect; iOS allows one active stream client.
  await new Promise((r) => setTimeout(r, 350));
  iosStreamModal.style.display = 'flex';

  if (profile === 'rtc' && (!iosBrowserSupportsRtc() || !iosDeviceSupportsRtc(device))) {
    console.warn('[ios-rtc] unavailable, opening Fast instead');
    profile = 'fast';
  }

  setIosMode(profile);
  iosCurrentDeviceId = device.id;
  iosCurrentWsBase = wsBase;
  iosCurrentDevice = device;
  iosModalDeviceTitle.textContent = device.display_name || device.id;

  let usingH264FastPath = false;
  if (profile === 'fast') {
    usingH264FastPath = await startIosH264Player(`${wsBase}/ios/${encodeURIComponent(device.id)}/h264`, false);
  } else if (profile === 'rtc') {
    usingH264FastPath = await startIosRtcPlayer(httpBase, device.id);
    if (!usingH264FastPath) {
      console.warn('[ios-rtc] signaling/start failed, falling back to Fast');
      profile = 'fast';
      setIosMode(profile);
      usingH264FastPath = await startIosH264Player(`${wsBase}/ios/${encodeURIComponent(device.id)}/h264`, false);
    }
  } else if (profile === 'worker') {
    usingH264FastPath = await startIosH264Player(`${wsBase}/ios/${encodeURIComponent(device.id)}/h264-worker`, true);
  }

  if (!usingH264FastPath) {
    const streamPath = profile === 'eco' || profile === 'worker' ? 'stream-eco' : 'stream';
    const streamUrl = `${wsBase}/ios/${encodeURIComponent(device.id)}/${streamPath}`;

    if (!mpegts.isSupported()) {
      console.error('mpegts.js not supported in this browser');
      return;
    }

    const playerConfig: any =
      profile === 'eco'
        ? {
            enableWorker: true,
            // Eco: allow a bit more buffering; keyframe ~3s.
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
            // Fallback fast path: minimize buffering for lower latency.
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

    iosPlayer = mpegts.createPlayer(
      {
        type: 'mpegts',
        isLive: true,
        url: streamUrl,
      },
      playerConfig
    ) as any;
    iosPlayer.attachMediaElement(iosVideo);

    iosVideo.playsInline = true;
    iosVideo.muted = true;
    iosVideo.preload = 'auto';

    iosPlayer.load();

    try {
      iosPlayer.on?.(mpegts.Events.ERROR, (t: any, d: any) => {
        console.error('[ios-stream]', profile, 'mpegts error', t, d);
      });
    } catch {}

    iosVideo.play().catch(() => {
      // Autoplay may be blocked; user can hit play.
    });
  }

  startIosLiveChase();

  if (!iosDisableControlForTest && iosControlMode === 'persistent') {
    // Control channel: WS -> TCP 6000 (TLinkauto legacy framing)
    const zxUrl = `${wsBase}/ios/${encodeURIComponent(device.id)}/tlinkauto`;
    iosZx = new TLinkautoWsClient(zxUrl);
    iosZx.waitOpen().then(async () => {
      console.log('[ios-tlinkauto] connected persistent');
      const size = await iosZx?.getScreenSize();
      if (size) iosScreenSize = size;
    }).catch(() => {
      // Control is optional; stream still works.
    });
  } else if (!iosDisableControlForTest) {
    console.warn('[ios] TLinkauto control using ephemeral mode');
  } else {
    console.warn('[ios] TLinkauto control disabled by iosNoControl=1');
  }

  if (profile === 'rtc' && iosAutoTouchMode) {
    window.setTimeout(() => {
      runIosAutoTouchTest().catch((e) => console.error('[ios-auto-touch] failed', e));
    }, 500);
  }
}

function setupIosControlListeners() {
  if (!iosStreamFrame) return;

  const mapPoint = (e: PointerEvent) => {
    const rect = iosStreamFrame.getBoundingClientRect();
    const rx = (e.clientX - rect.left) / rect.width;
    const ry = (e.clientY - rect.top) / rect.height;
    const x = Math.max(0, Math.min(iosScreenSize.width, rx * iosScreenSize.width));
    const y = Math.max(0, Math.min(iosScreenSize.height, ry * iosScreenSize.height));
    return { x, y };
  };

  iosStreamFrame.addEventListener('pointerdown', async (e) => {
    if (iosDisableControlForTest) return;
    if (iosPointerActive) return;
    const ok = await ensureIosZxOpen(800);
    if (!ok) return;
    iosPointerActive = true;
    iosActivePointerId = e.pointerId;
    iosGestureSeq += 1;
    iosGestureMoveCount = 0;
    iosLastSentMove = undefined;
    iosLastMoveSentAt = 0;
    iosLastMoveAt = 0;
    iosPendingMove = undefined;
    startIosMovePump();
    try {
      iosStreamFrame.setPointerCapture(e.pointerId);
    } catch {}
    const { x, y } = mapPoint(e);
    if (iosAckTouch) {
      iosZx?.touchAck(1, 1, x, y).then((ack) => {
        console.log('[ios-manual-touch] down ack', { seq: iosGestureSeq, ackSeq: ack.seq, latencyMs: ack.latencyMs.toFixed(1), dispatchUs: ack.dispatchUs });
      }).catch((err) => {
        console.error('[ios-manual-touch] down ack failed', err);
      });
    } else {
      iosZx?.touch(1, 1, x, y); // DOWN
    }
    console.log('[ios-manual-touch] down', { seq: iosGestureSeq, pointerId: e.pointerId, x: Math.round(x), y: Math.round(y), mode: iosControlMode, ack: iosAckTouch });
  });

  iosStreamFrame.addEventListener('pointermove', (e) => {
    if (!iosPointerActive) return;
    if (iosActivePointerId !== e.pointerId) return;
    const { x, y } = mapPoint(e);
    iosPendingMove = { x, y };
  });

  const end = (e: PointerEvent, reason: string) => {
    if (!iosPointerActive) return;
    if (iosActivePointerId !== e.pointerId) return;
    const seq = iosGestureSeq;
    iosPointerActive = false;
    iosActivePointerId = undefined;
    iosPendingMove = undefined;
    iosLastSentMove = undefined;
    iosLastMoveSentAt = 0;
    try {
      iosStreamFrame.releasePointerCapture(e.pointerId);
    } catch {}
    const { x, y } = mapPoint(e);
    if (iosAckTouch) {
      iosZx?.touchAck(0, 1, x, y).then((ack) => {
        console.log('[ios-manual-touch] up ack', { seq, ackSeq: ack.seq, latencyMs: ack.latencyMs.toFixed(1), dispatchUs: ack.dispatchUs });
      }).catch((err) => {
        console.error('[ios-manual-touch] up ack failed', err);
      });
    } else {
      iosZx?.touch(0, 1, x, y); // UP
    }
    console.log('[ios-manual-touch] up', { seq, pointerId: e.pointerId, reason, x: Math.round(x), y: Math.round(y), moves: iosGestureMoveCount, mode: iosControlMode, ack: iosAckTouch });
    iosGestureMoveCount = 0;
    scheduleIosEphemeralControlClose();
  };

  iosStreamFrame.addEventListener('pointerup', (e) => end(e, 'pointerup'));
  iosStreamFrame.addEventListener('pointercancel', (e) => end(e, 'pointercancel'));
}

async function getScrcpyServer() {
  if (scrcpyServerBinary) return scrcpyServerBinary;
  try {
    const response = await fetch('/scrcpy-server-v3.1');
    if (!response.ok) throw new Error('Failed to fetch scrcpy server');
    const buffer = await response.arrayBuffer();
    scrcpyServerBinary = new Uint8Array(buffer);
    console.log(`Scrcpy server loaded: ${scrcpyServerBinary.length} bytes`);
    return scrcpyServerBinary;
  } catch (e) {
    console.error('Failed to load scrcpy server:', e);
    throw e;
  }
}

function updateDeviceDetail(serial: string) {
  const device = connectedDevices.get(serial);
  if (!device) return;
  currentSelectedSerial = serial;
  document.querySelectorAll('.device-card').forEach(c => c.classList.remove('selected'));
  device.cardElement.classList.add('selected');
  detailEmpty.style.display = 'none';
  detailContent.style.display = 'block';
  detailThumb.src = "https://images.unsplash.com/photo-1616348436168-de43ad0db179?auto=format&fit=crop&q=80&w=400";
  detailName.textContent = device.properties?.model || serial;

  // Update meta to include device state
  const stateLabel = device.state !== 'device' ? ` • ${device.state.toUpperCase()} MODE` : '';
  detailMeta.textContent = `${device.properties?.brand || 'Android'} • Android ${device.properties?.version || '--'} • ${device.properties?.arch || 'arm64'}${stateLabel}`;

  statBattery.textContent = '85%';
  statMemory.textContent = '12 GB';
  statSerial.textContent = serial;
  statModel.textContent = device.properties?.model || 'Generic';
  const actions = detailContent.querySelectorAll('.detail-action-btn');
  actions.forEach(btn => (btn as HTMLElement).dataset.serial = serial);

  // Setup Install APK button
  const installBtn = detailContent.querySelector('.btn-install') as HTMLButtonElement;
  // Remove old listeners to avoid duplicates
  const newInstallBtn = installBtn.cloneNode(true) as HTMLButtonElement;
  installBtn.parentNode?.replaceChild(newInstallBtn, installBtn);

  newInstallBtn.addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.apk';
    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (file) {
        await installApk(serial, file);
      }
    };
    input.click();
  });

  // Setup Push File button
  const uploadBtn = detailContent.querySelector('.btn-upload') as HTMLButtonElement;
  const newUploadBtn = uploadBtn.cloneNode(true) as HTMLButtonElement;
  uploadBtn.parentNode?.replaceChild(newUploadBtn, uploadBtn);

  newUploadBtn.addEventListener('click', () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (file) {
        await pushFile(serial, file);
      }
    };
    input.click();
  });

  // Setup Pull File button (toggle pane visibility)
  const downloadBtn = detailContent.querySelector('.btn-download') as HTMLButtonElement;
  const newDownloadBtn = downloadBtn.cloneNode(true) as HTMLButtonElement;
  downloadBtn.parentNode?.replaceChild(newDownloadBtn, downloadBtn);

  newDownloadBtn.addEventListener('click', () => {
    if (pullFilePane) {
      pullFilePane.style.display = pullFilePane.style.display === 'none' ? 'flex' : 'none';
    }
  });

  // Hide/show canvas based on whether scrcpy is available
  const mirrorSection = detailContent.querySelector('.mirror-section') as HTMLElement;
  if (mirrorSection) {
    if (device.state !== 'device') {
      mirrorSection.style.opacity = '0.5';
      mirrorSection.style.pointerEvents = 'none';
      const canvas = mirrorSection.querySelector('canvas') as HTMLCanvasElement;
      const ctx = canvas?.getContext('2d');
      if (ctx && canvas) {
        ctx.fillStyle = '#1e293b';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = '#94a3b8';
        ctx.font = '16px Inter, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(`Mirroring unavailable in ${device.state} mode`, canvas.width / 2, canvas.height / 2);
      }
    } else {
      mirrorSection.style.opacity = '1';
      mirrorSection.style.pointerEvents = 'auto';
    }
  }
  updateVisibilityState();
}

function createDeviceCard(serial: string): HTMLElement {
  const emptyState = devicesContainer.querySelector('.empty-state');
  if (emptyState) emptyState.remove();
  const clone = deviceCardTemplate.content.cloneNode(true) as DocumentFragment;
  const card = clone.querySelector('.device-card') as HTMLElement;
  card.dataset.serial = serial;
  const name = card.querySelector('.card-name') as HTMLElement;
  const meta = card.querySelector('.device-meta') as HTMLElement;
  const badge = card.querySelector('.status-badge') as HTMLElement;
  const thumb = card.querySelector('.card-thumb-img') as HTMLImageElement;
  name.textContent = serial;
  meta.textContent = 'Connecting...';
  badge.textContent = 'ONLINE';
  badge.className = 'status-badge badge-online';
  thumb.src = "https://images.unsplash.com/photo-1616348436168-de43ad0db179?auto=format&fit=crop&q=80&w=400";
  card.addEventListener('click', () => updateDeviceDetail(serial));
  card.addEventListener('dblclick', () => openDeviceModal(serial));
  const powerBtn = card.querySelector('.btn-power') as HTMLButtonElement;
  powerBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    disconnectDevice(serial);
  });
  devicesContainer.appendChild(clone);
  updateDeviceCount();
  return card;
}

async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries = 3,
  initialDelayMs = 500,
  label = 'operation'
): Promise<T> {
  let lastError: any;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt < maxRetries) {
        const delayMs = initialDelayMs * Math.pow(2, attempt);
        console.warn(`[${label}] Attempt ${attempt + 1} failed, retrying in ${delayMs}ms...`, error);
        await new Promise(resolve => setTimeout(resolve, delayMs));
      }
    }
  }
  throw lastError;
}

async function connectToDevice(device: AdbServerClient.Device) {
  try {
    if (connectedDevices.has(device.serial)) {
      console.log(`[${device.serial}] Already connected, skipping`);
      return;
    }

    const cardElement = createDeviceCard(device.serial);

    // ============================================================================
    // CRITICAL FIX: Verify server client health before use
    // ============================================================================
    if (!serverClient) {
      throw new Error('Server client not initialized');
    }

    try {
      await Promise.race([
        serverClient.getDevices(),
        new Promise((_, reject) => setTimeout(() => reject(new Error('Health check timeout')), 2000))
      ]);
      console.log(`[${device.serial}] Server client healthy`);
    } catch (e) {
      console.warn(`[${device.serial}] Server client stale, recreating...`, e);
      const url = normalizeBridgeWebSocketUrl(endpointInput.value.trim());
      const connector = new AdbWebSocketConnector(url);
      serverClient = new AdbServerClient(connector);
    }

    console.log(`[${device.serial}] Creating ADB connection...`);
    const adb = await retryWithBackoff(
      () => serverClient!.createAdb({ serial: device.serial }),
      2,
      300,
      `${device.serial}-createAdb`
    );

    const [model, version] = await Promise.all([
      adb.getProp('ro.product.model').catch(() => 'Unknown'),
      adb.getProp('ro.build.version.release').catch(() => 'Unknown')
    ]);

    const metaEl = cardElement.querySelector('.device-meta') as HTMLElement;
    metaEl.textContent = `${model} • Android ${version}`;

    const deviceConnection: DeviceConnection = {
      serial: device.serial,
      state: device.state || 'device',
      adb,
      cardElement,
      properties: { model, version, brand: '', arch: 'arm64' }
    };

    connectedDevices.set(device.serial, deviceConnection);
    // Slice C: mirror into adbDeviceStore so React DevicesPane sees the row.
    upsertLegacyDevice({
      serial: device.serial,
      state: deviceConnection.state,
      properties: deviceConnection.properties as Record<string, string> | undefined,
    });
    updateDeviceCount();
    setStatus(`${connectedDevices.size} device(s) connected`, true);

    if (!currentSelectedSerial) updateDeviceDetail(device.serial);

    // Only start scrcpy for devices in normal mode
    if (deviceConnection.state === 'device') {
      await new Promise(resolve => setTimeout(resolve, 100));
      await startMirrorForDevice(deviceConnection);

      // Update screen view after connection established
      renderScreenView();

    } else {
      console.log(`[${device.serial}] Device in ${deviceConnection.state} mode, skipping scrcpy`);
      // Update badge to reflect state
      const badge = cardElement.querySelector('.status-badge') as HTMLElement;
      if (badge) {
        if (deviceConnection.state === 'recovery') {
          badge.textContent = 'RECOVERY';
          badge.className = 'status-badge badge-recovery';
        } else if (deviceConnection.state === 'sideload') {
          badge.textContent = 'SIDELOAD';
          badge.className = 'status-badge badge-sideload';
        } else if (deviceConnection.state === 'bootloader') {
          badge.textContent = 'BOOTLOADER';
          badge.className = 'status-badge badge-bootloader';
        } else if (deviceConnection.state === 'unauthorized') {
          badge.textContent = 'UNAUTHORIZED';
          badge.className = 'status-badge badge-unauthorized';
        } else {
          badge.textContent = deviceConnection.state.toUpperCase();
          badge.className = 'status-badge badge-offline';
        }
      }
    }

  } catch (error) {
    console.error(`[${device.serial}] Connection failed:`, error);
    const card = devicesContainer.querySelector(`[data-serial="${device.serial}"]`);
    if (card) card.remove();
    updateDeviceCount();
  }
}

function disconnectDevice(serial: string) {
  const device = connectedDevices.get(serial);
  if (!device) return;
  device.scrcpyClient?.close();
  device.adb.close?.();
  device.cardElement.remove();
  connectedDevices.delete(serial);
  // Slice C: remove from React-facing store.
  removeLegacyDevice(serial);
  if (currentSelectedSerial === serial) {
    currentSelectedSerial = null;
    if (detailContent) detailContent.style.display = 'none';
    if (detailEmpty) detailEmpty.style.display = 'flex';
  }
  updateDeviceCount();
  renderScreenView(); // Update grid on disconnect
  if (connectedDevices.size === 0) {
    setStatus('Disconnected', false);
    if (devicesContainer) devicesContainer.innerHTML = '';
  }
}


async function installApk(serial: string, file: File) {
  const device = connectedDevices.get(serial);
  if (!device) return;

  console.log(`[${serial}] Installing APK: ${file.name} (${(file.size / 1024 / 1024).toFixed(2)} MB)`);

  const installBtn = detailContent.querySelector('.btn-install') as HTMLButtonElement;
  const originalText = installBtn.textContent || '📥 Install APK';
  installBtn.disabled = true;
  installBtn.textContent = '📦 Installing...';

  try {
    const pm = new PackageManager(device.adb);
    // Wrap browser stream to Yume-chan stream (cast to bypass type mismatch)
    const stream = new WrapReadableStream(file.stream() as any);

    // installStream handles the streaming and installation
    // May throw stream cleanup errors even on success, so we catch and verify
    try {
      await pm.installStream(file.size, stream as any);
    } catch (streamError: any) {
      // The library throws errors during stream cleanup even when install succeeds
      // Check stack trace for Promise.all which indicates cleanup error
      const errorStack = streamError?.stack || String(streamError);
      if (errorStack.includes('Promise.all') || errorStack.includes('index 1')) {
        console.warn(`[${serial}] Stream cleanup warning (install succeeded):`, streamError);
        // Don't re-throw - install was successful
      } else {
        throw streamError; // Re-throw actual install errors
      }
    }

    console.log(`[${serial}] ✅ Install Successful`);
    installBtn.textContent = '✅ Installed';
    setTimeout(() => {
      if (installBtn.isConnected) installBtn.textContent = originalText;
      installBtn.disabled = false;
    }, 2000);

  } catch (error) {
    console.error(`[${serial}] Install error:`, error);
    installBtn.textContent = '❌ Error';
    setTimeout(() => {
      if (installBtn.isConnected) installBtn.textContent = originalText;
      installBtn.disabled = false;
    }, 3000);
    alert(`Error installing APK: ${error}`);
  }
}

async function pushFile(serial: string, file: File) {
  const device = connectedDevices.get(serial);
  if (!device) return;

  const destPath = `/data/local/tmp/${file.name.replace(/\s+/g, '_')}`;
  console.log(`[${serial}] Pushing file: ${file.name} (${(file.size / 1024 / 1024).toFixed(2)} MB) -> ${destPath}`);

  const uploadBtn = detailContent.querySelector('.btn-upload') as HTMLButtonElement;
  const originalText = uploadBtn.textContent || '📤 Push File';
  uploadBtn.disabled = true;
  uploadBtn.textContent = '⏳ Reading...';

  try {
    // Read file into memory
    const arrayBuffer = await file.arrayBuffer();
    const bytes = new Uint8Array(arrayBuffer);
    console.log(`[${serial}] File loaded: ${bytes.length} bytes`);

    uploadBtn.textContent = '⏳ Encoding...';

    // Convert to base64 in chunks to avoid stack overflow
    const encodingChunkSize = 32768;
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i += encodingChunkSize) {
      binary += String.fromCharCode(...bytes.subarray(i, i + encodingChunkSize));
    }
    const base64Data = btoa(binary);
    console.log(`[${serial}] Base64 encoded: ${(base64Data.length / 1024 / 1024).toFixed(2)} MB`);

    uploadBtn.textContent = '⏳ Pushing 0%';

    // Push via base64 decode on device (same method as scrcpy-server.jar)
    const socket = await device.adb.createSocket(`shell:base64 -d > "${destPath}" && chmod 644 "${destPath}"`);
    const writer = socket.writable.getWriter();
    const encoder = new TextEncoder();
    const chunkSize = 65536;
    let sent = 0;
    let lastProgress = 0;

    for (let i = 0; i < base64Data.length; i += chunkSize) {
      const chunk = base64Data.substring(i, Math.min(i + chunkSize, base64Data.length));
      await writer.write(encoder.encode(chunk));
      sent += chunk.length;

      const progress = Math.floor((sent / base64Data.length) * 100);
      if (progress !== lastProgress && progress % 10 === 0) {
        uploadBtn.textContent = `⏳ Pushing ${progress}%`;
        console.log(`[${serial}] Progress: ${progress}%`);
        lastProgress = progress;
      }
    }
    await writer.close();

    // Consume output
    const decoder = new TextDecoder();
    for await (const chunk of socket.readable) {
      const out = decoder.decode(chunk).trim();
      if (out) console.log(`[${serial}] ${out}`);
    }

    console.log(`[${serial}] ✅ Push Successful: ${destPath}`);
    uploadBtn.textContent = '✅ Pushed';
    setTimeout(() => {
      if (uploadBtn.isConnected) uploadBtn.textContent = originalText;
      uploadBtn.disabled = false;
    }, 2000);

  } catch (error) {
    console.error(`[${serial}] Push error:`, error);
    uploadBtn.textContent = '❌ Error';
    setTimeout(() => {
      if (uploadBtn.isConnected) uploadBtn.textContent = originalText;
      uploadBtn.disabled = false;
    }, 3000);
    alert(`Error pushing file: ${error}`);
  }
}

async function pullFile(serial: string, remotePath: string) {
  const device = connectedDevices.get(serial);
  if (!device) return;

  if (!remotePath || remotePath.trim() === '') {
    alert('Please enter a valid file path');
    return;
  }

  remotePath = remotePath.trim();
  const fileName = remotePath.split('/').pop() || 'downloaded_file';
  console.log(`[${serial}] Pulling file: ${remotePath}`);

  const updateStatus = (msg: string) => {
    if (pullFileStatus) pullFileStatus.textContent = msg;
  };

  const startTime = performance.now();
  updateStatus('⏳ Checking file...');

  try {
    // First check if file exists and get its size
    const checkSocket = await device.adb.createSocket(`shell:stat -c %s "${remotePath}" 2>/dev/null || echo "NOT_FOUND"`);
    const decoder = new TextDecoder();
    let sizeOutput = '';
    for await (const chunk of checkSocket.readable) {
      sizeOutput += decoder.decode(chunk);
    }
    sizeOutput = sizeOutput.trim();

    if (sizeOutput === 'NOT_FOUND' || sizeOutput === '' || isNaN(parseInt(sizeOutput, 10))) {
      updateStatus('❌ File not found');
      alert(`File not found: ${remotePath}`);
      return;
    }

    const expectedSize = parseInt(sizeOutput, 10);
    console.log(`[${serial}] File size: ${expectedSize} bytes (${(expectedSize / 1024 / 1024).toFixed(2)} MB)`);
    updateStatus(`⏳ Downloading ${(expectedSize / 1024 / 1024).toFixed(2)} MB...`);

    // Use exec service for binary streaming (no PTY interference)
    // exec:cat streams raw binary without shell escaping issues
    let socket;
    try {
      socket = await device.adb.createSocket(`exec:cat "${remotePath}"`);
      console.log(`[${serial}] Using exec:cat for binary transfer`);
    } catch (execErr) {
      // Fallback: some devices don't support exec, use shell with stty
      console.log(`[${serial}] exec:cat failed, falling back to shell:cat`);
      socket = await device.adb.createSocket(`shell:stty raw -echo 2>/dev/null; cat "${remotePath}"`);
    }

    // Collect all chunks
    const chunks: Uint8Array[] = [];
    let received = 0;
    let lastProgressUpdate = 0;

    for await (const chunk of socket.readable) {
      chunks.push(chunk);
      received += chunk.length;

      // Update progress every 250KB
      if (received - lastProgressUpdate > 256 * 1024) {
        const now = performance.now();
        const elapsed = (now - startTime) / 1000;
        const percent = expectedSize > 0 ? Math.floor((received / expectedSize) * 100) : 0;
        const speedMBps = elapsed > 0 ? received / elapsed / 1024 / 1024 : 0;
        updateStatus(`⏳ ${percent}% (${(received / 1024 / 1024).toFixed(1)}/${(expectedSize / 1024 / 1024).toFixed(1)} MB) @ ${speedMBps.toFixed(1)} MB/s`);
        lastProgressUpdate = received;
      }
    }

    // Combine all chunks
    const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
    const bytes = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }

    console.log(`[${serial}] Received: ${bytes.length} bytes (expected: ${expectedSize})`);

    // Validate size
    if (bytes.length !== expectedSize) {
      console.warn(`[${serial}] Size mismatch: received ${bytes.length}, expected ${expectedSize}`);
    }

    // Create blob and trigger download
    const blob = new Blob([bytes], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    const duration = (performance.now() - startTime) / 1000;
    const speedMBps = bytes.length / duration / 1024 / 1024;
    console.log(`[${serial}] ✅ Pull Successful: ${fileName} (${duration.toFixed(1)}s, ${speedMBps.toFixed(1)} MB/s)`);
    updateStatus(`✅ ${fileName} (${speedMBps.toFixed(1)} MB/s)`);

  } catch (error) {
    console.error(`[${serial}] Pull error:`, error);
    updateStatus(`❌ Error: ${error}`);
    alert(`Error pulling file: ${error}`);
  }
}

async function startMirrorForDevice(deviceConnection: DeviceConnection) {
  const { adb, serial } = deviceConnection;
  const serverPath = `/data/local/tmp/scrcpy-server.jar`;
  const mirrorStart = performance.now();
  const timeline: string[] = [];
  const markPhase = (label: string) => timeline.push(`[${(performance.now() - mirrorStart).toFixed(0)}ms] ${label}`);

  try {
    const binary = await getScrcpyServer();
    console.log(`[${serial}] Starting mirror setup...`);
    markPhase('start');

    const withTimeout = async <T>(promise: Promise<T>, label: string, timeoutMs = 5000): Promise<T> => {
      return await Promise.race([
        promise,
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error(`${label} timeout after ${timeoutMs}ms`)), timeoutMs)
        )
      ]);
    };

    const checkExists = async (): Promise<boolean> => {
      try {
        const socket = await withTimeout(
          adb.createSocket(`shell:test -f ${serverPath} && echo 1 || echo 0`),
          'check-exists',
          2000
        );
        const decoder = new TextDecoder();
        let output = '';
        for await (const chunk of socket.readable) {
          output += decoder.decode(chunk);
        }
        return output.trim() === '1';
      } catch {
        return false;
      }
    };

    const exists = await checkExists();
    markPhase(`exists=${exists}`);

    let needsPush = !exists;

    if (exists) {
      try {
        const socket = await withTimeout(
          adb.createSocket(`shell:wc -c < ${serverPath} 2>/dev/null`),
          'size-check',
          2000
        );
        const decoder = new TextDecoder();
        let output = '';
        for await (const chunk of socket.readable) {
          output += decoder.decode(chunk);
        }
        const remoteSize = parseInt(output.trim(), 10);
        markPhase(`size=${remoteSize}`);

        if (remoteSize === binary.length) {
          console.log(`[${serial}] Server file valid, skipping push`);
          needsPush = false;
        } else {
          console.log(`[${serial}] Size mismatch, will push`);
          needsPush = true;
        }
      } catch (e) {
        console.warn(`[${serial}] Size check failed, will push`);
        needsPush = true;
      }
    }

    if (needsPush) {
      const pushStart = performance.now();
      let pushed = false;

      // ============================================================================
      // CRITICAL FIX: Skip sync if globally disabled (failed on previous device)
      // ============================================================================
      if (!syncDisabledForDevice.has(serial) && !syncGloballyDisabled.value) {
        try {
          const sync = await adb.sync();
          try {
            const stream = new ReadableStream<MaybeConsumable<Uint8Array>>({
              start(controller) {
                controller.enqueue(binary);
                controller.close();
              }
            });

            const syncTimeout = Math.max(3000, Math.ceil(binary.length / 30000) * 1000);
            console.log(`[${serial}] Attempting sync (timeout: ${syncTimeout}ms)...`);

            await withTimeout(
              sync.write({ filename: serverPath, file: stream, permission: 0o644 }),
              'sync-write',
              syncTimeout
            );

            const verifyExists = await checkExists();
            if (verifyExists) {
              pushed = true;
              const duration = (performance.now() - pushStart) / 1000;
              console.log(`[${serial}] ✅ Sync push OK (${duration.toFixed(2)}s)`);
              markPhase(`sync-ok-${duration.toFixed(2)}s`);
            }
          } finally {
            await sync.dispose();
          }
        } catch (syncError) {
          console.warn(`[${serial}] Sync failed, disabling globally:`, syncError);
          syncDisabledForDevice.add(serial);
          syncGloballyDisabled.value = true;  // Disable for ALL future devices
          markPhase('sync-failed');
        }
      } else {
        console.log(`[${serial}] Sync disabled (globally=${syncGloballyDisabled.value}), using base64`);
        markPhase('sync-skipped');
      }

      if (!pushed) {
        console.log(`[${serial}] Using base64 push...`);
        const base64Start = performance.now();
        const base64Data = btoa(String.fromCharCode(...binary));
        const socket = await adb.createSocket(`shell:base64 -d > ${serverPath} && chmod 644 ${serverPath}`);
        const writer = socket.writable.getWriter();
        const encoder = new TextEncoder();
        const chunkSize = 65536;

        for (let i = 0; i < base64Data.length; i += chunkSize) {
          await writer.write(encoder.encode(base64Data.substring(i, i + chunkSize)));
        }
        await writer.close();

        const decoder = new TextDecoder();
        for await (const chunk of socket.readable) {
          const out = decoder.decode(chunk).trim();
          if (out) console.log(`[${serial}] ${out}`);
        }

        const duration = (performance.now() - base64Start) / 1000;
        console.log(`[${serial}] ✅ Base64 push OK (${duration.toFixed(2)}s)`);
        markPhase(`base64-${duration.toFixed(2)}s`);
      }
    }

    const options = new AdbScrcpyOptions3_1({
      maxSize: 640,
      videoBitRate: 1000000,
      videoCodec: "h264",
      maxFps: 24,
      audio: false,
      control: true,
      sendDeviceMeta: false,
      sendDummyByte: true,
      tunnelForward: true,
      clipboardAutosync: true,  // Enable clipboard synchronization
    });

    console.log(`[${serial}] Scrcpy options:`, options);

    console.log(`[${serial}] Starting scrcpy client...`);
    markPhase('scrcpy-start');

    const scrcpyStartTime = performance.now();

    // ============================================================================
    // CRITICAL FIX: Increased timeout for VPN/Stable connections (30s)
    // ============================================================================
    try {
      console.log(`[${serial}] Waiting for scrcpy server to initialize...`);
      deviceConnection.scrcpyClient = await Promise.race([
        retryWithBackoff(
          () => AdbScrcpyClient.start(adb, serverPath, options),
          2,  // 2 retries
          1000,
          `${serial}-scrcpy-start`
        ),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('Scrcpy start timeout (30s reached)')), 30000)
        )
      ]);
    } catch (error) {
      const scrcpyDuration = ((performance.now() - scrcpyStartTime) / 1000).toFixed(2);
      console.error(`[${serial}] Scrcpy start failed after ${scrcpyDuration}s:`, error);

      // If timeout, recreate server client and try once more
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.includes('timeout')) {
        console.warn(`[${serial}] Timeout detected, recreating connection and retrying...`);

        const url = normalizeBridgeWebSocketUrl(endpointInput.value.trim());
        const connector = new AdbWebSocketConnector(url);
        serverClient = new AdbServerClient(connector);
        const freshAdb = await serverClient.createAdb({ serial: serial });
        deviceConnection.adb = freshAdb;

        deviceConnection.scrcpyClient = await AdbScrcpyClient.start(freshAdb, serverPath, options);
      } else {
        throw error;
      }
    }

    const scrcpyDuration = ((performance.now() - scrcpyStartTime) / 1000).toFixed(2);
    console.log(`[${serial}] Scrcpy client started in ${scrcpyDuration}s`);
    markPhase(`scrcpy-ready-${scrcpyDuration}s`);

    const videoStream = await deviceConnection.scrcpyClient.videoStream;
    if (!videoStream) throw new Error('No video stream');

    const width = videoStream.metadata.width || 720;
    const height = videoStream.metadata.height || 1280;

    const totalDuration = (performance.now() - mirrorStart) / 1000;
    console.log(`[${serial}] ✅ Ready in ${totalDuration.toFixed(2)}s`);
    markPhase(`ready-${totalDuration.toFixed(2)}s`);
    console.log(`[${serial}] ${timeline.join(' | ')}`);

    const hiddenCanvas = document.createElement('canvas');
    hiddenCanvas.width = width;
    hiddenCanvas.height = height;

    const renderer = new BitmapVideoFrameRenderer(hiddenCanvas);
    const decoder = new WebCodecsVideoDecoder({
      codec: ScrcpyVideoCodecId.H264,
      renderer: renderer,
    });

    deviceConnection.renderer = renderer;
    deviceConnection.decoder = decoder;

    // Slice D1: expose this mirror session to the React-side store so
    // useCanvasBinding / ControlBar / QuickActions can drive it without
    // touching legacy globals.
    const mirrorSession: ScrcpyMirrorSession = {
      serial,
      controller: deviceConnection.scrcpyClient!.controller!,
      hiddenCanvas,
      width,
      height,
      stop: () => {
        try { deviceConnection.scrcpyClient?.close(); } catch {}
      },
    };
    registerMirrorSession(mirrorSession);

    let rafId: number;
    const drawToViews = () => {
      if (!connectedDevices.has(serial)) {
        cancelAnimationFrame(rafId);
        return;
      }

      if (isDetailViewVisible && currentSelectedSerial === serial) {
        if (detailCanvas.width !== width) detailCanvas.width = width;
        if (detailCanvas.height !== height) detailCanvas.height = height;
        detailCanvas.getContext('2d')?.drawImage(hiddenCanvas, 0, 0);
      }

      if (isModalVisible && currentModalDevice === serial) {
        if (modalCanvas.width !== width) modalCanvas.width = width;
        if (modalCanvas.height !== height) modalCanvas.height = height;
        modalCanvas.getContext('2d')?.drawImage(hiddenCanvas, 0, 0);
      }

      rafId = requestAnimationFrame(drawToViews);
    };
    drawToViews();

    videoStream.stream.pipeTo(decoder.writable).catch(e => {
      // Only log error if not a clean stream end
      if (e && e.name !== 'ExactReadableEndedError') {
        console.error(`[${serial}] Stream error:`, e);
      } else {
        console.log(`[${serial}] Video stream ended cleanly`);
      }
    });

    // ============================================================================
    // Clipboard Synchronization: Device → Browser
    // ============================================================================
    const clipboardStream = deviceConnection.scrcpyClient.clipboard;
    console.log(`[${serial}] Clipboard stream available:`, !!clipboardStream);

    if (clipboardStream) {
      console.log(`[${serial}] ✅ Starting clipboard sync (device → browser)`);
      const reader = clipboardStream.getReader();
      let lastSyncedValue = '';  // Track last synced value to prevent duplicates

      const drawToViews = () => {
        if (!videoStream || !videoStream.metadata) {
          requestAnimationFrame(drawToViews);
          return;
        }

        const metaWidth = videoStream.metadata.width ?? 0;
        const metaHeight = videoStream.metadata.height ?? 0;

        if (metaWidth === 0 || metaHeight === 0) {
          requestAnimationFrame(drawToViews);
          return;
        }

        // 1. Draw to Detail View Canvas
        if (isDetailViewVisible && currentSelectedSerial === serial) {
          const ctx = detailCanvas.getContext('2d');
          if (ctx) {
            const { width, height } = detailCanvas;
            // Calculate contain fit
            const scale = Math.min(width / metaWidth, height / metaHeight);
            const w = metaWidth * scale;
            const h = metaHeight * scale;
            const x = (width - w) / 2;
            const y = (height - h) / 2;
            ctx.fillStyle = '#1e293b';
            ctx.fillRect(0, 0, width, height);
            ctx.drawImage(hiddenCanvas, 0, 0, hiddenCanvas.width, hiddenCanvas.height, x, y, w, h);
          }
        }

        // 2. Draw to Modal Canvas
        if (isModalVisible && currentModalDevice === serial) {
          const modalCtx = modalCanvas.getContext('2d');
          if (modalCtx) {
            const { width, height } = modalCanvas;
            const scale = Math.min(width / metaWidth, height / metaHeight);
            const w = metaWidth * scale;
            const h = metaHeight * scale;
            const x = (width - w) / 2;
            const y = (height - h) / 2;
            modalCtx.fillStyle = '#000';
            modalCtx.fillRect(0, 0, width, height);
            modalCtx.drawImage(hiddenCanvas, 0, 0, hiddenCanvas.width, hiddenCanvas.height, x, y, w, h);
          }
        }

        // 3. Draw to Screen View Grid
        // Optimized: Uses cached canvas and global visibility flag
        if (isScreenViewVisible) {
          const gridCanvas = deviceConnection.screenViewCanvas;
          if (gridCanvas) {
            // Resize grid canvas if needed to match stream aspect ratio
            // Optimization: checking width property is fast, but we can also cache this if needed
            if (gridCanvas.width !== metaWidth || gridCanvas.height !== metaHeight) {
              gridCanvas.width = metaWidth;
              gridCanvas.height = metaHeight;
            }
            const gridCtx = gridCanvas.getContext('2d');
            gridCtx?.drawImage(hiddenCanvas, 0, 0);
          }
        }

        requestAnimationFrame(drawToViews);
      };
      drawToViews();

      const readClipboard = async () => {
        try {
          console.log(`[${serial}] Clipboard reader loop started`);
          while (connectedDevices.has(serial)) {
            const { value, done } = await reader.read();
            // Reduced verbosity to avoid flooding logs
            // console.log(`[${serial}] Clipboard read:`, { done, valueLength: value?.length });

            if (done) {
              console.log(`[${serial}] Clipboard stream ended`);
              break;
            }

            if (!value || value.length === 0) {
              continue;
            }

            // Skip if value hasn't changed (deduplication)
            if (value === lastSyncedValue) {
              continue;
            }

            try {
              await navigator.clipboard.writeText(value);
              lastSyncedValue = value;  // Update last synced value

              // Track sync state to prevent feedback loop
              clipboardSyncState.set(serial, {
                lastDeviceValue: value,
                lastSyncTime: Date.now()
              });

              console.log(`[${serial}] 📋 Device clipboard → Browser (${value.length} chars)`);

            } catch (e) {
              console.warn(`[${serial}] Could not write to browser clipboard:`, e);
            }
          }
        } catch (e) {
          // Ignore errors if device disconnected
          if (connectedDevices.has(serial)) {
            console.error(`[${serial}] ❌ Clipboard read error:`, e);
          }
        } finally {
          try {
            reader.releaseLock();
          } catch (e) {
            // Ignore lock release errors
          }
        }
      };
      readClipboard();
    } else {
      console.warn(`[${serial}] ⚠️ Clipboard stream not available - clipboard sync disabled`);
    }

    if (deviceConnection.scrcpyClient.controller) {
      const controller = deviceConnection.scrcpyClient.controller;
      let lastTouchTime = 0;
      const touchThrottle = 16;

      const sendDashboardTouch = (type: number, e: PointerEvent) => {
        if (currentSelectedSerial !== serial) return;
        const now = performance.now();
        if (type === 2 && now - lastTouchTime < touchThrottle) return;
        lastTouchTime = now;

        const rect = detailCanvas.getBoundingClientRect();
        const x = (e.clientX - rect.left) * (detailCanvas.width / rect.width);
        const y = (e.clientY - rect.top) * (detailCanvas.height / rect.height);

        controller.injectTouch({
          action: type as AndroidMotionEventAction,
          pointerId: BigInt(0),
          pointerX: Math.max(0, Math.min(x, width)),
          pointerY: Math.max(0, Math.min(y, height)),
          videoWidth: width,
          videoHeight: height,
          pressure: (type === 0 || type === 2) ? 1 : 0,
          actionButton: 1,
          buttons: e.buttons
        });
      };

      const dc = detailCanvas;
      dc.addEventListener('pointerdown', e => {
        if (currentSelectedSerial === serial) {
          dc.setPointerCapture(e.pointerId);
          sendDashboardTouch(0, e);
        }
      });
      dc.addEventListener('pointermove', e => {
        if (currentSelectedSerial === serial && e.buttons === 1) {
          sendDashboardTouch(2, e);
        }
      });
      dc.addEventListener('pointerup', e => {
        if (currentSelectedSerial === serial) {
          sendDashboardTouch(1, e);
          dc.releasePointerCapture(e.pointerId);
        }
      });

      // ============================================================================
      // Clipboard Synchronization: Browser → Device (on focus)
      // ============================================================================
      const syncBrowserToDevice = async () => {
        if (currentSelectedSerial !== serial) return;

        // Check cooldown to prevent feedback loop
        const syncState = clipboardSyncState.get(serial);
        if (syncState) {
          const timeSinceLastSync = Date.now() - syncState.lastSyncTime;
          if (timeSinceLastSync < CLIPBOARD_SYNC_COOLDOWN) {
            return;
          }
        }

        try {
          const text = await navigator.clipboard.readText();
          if (text && text.length > 0) {
            // Don't send if it's the same as what we just received from device
            if (syncState && text === syncState.lastDeviceValue) {
              return;
            }

            await controller.setClipboard({
              content: text,  // Correct property name is 'content', not 'text'
              sequence: BigInt(Date.now()),
              paste: false,  // Don't auto-paste, just set clipboard
            });
            console.log(`[${serial}] 📋 Browser clipboard → Device`);
          }
        } catch (e) {
          // Silently fail - clipboard permission may not be granted
        }
      };

      // Sync on canvas focus
      dc.addEventListener('focus', syncBrowserToDevice);
      dc.addEventListener('click', syncBrowserToDevice);  // Also on click for better UX
    }

  } catch (error) {
    console.error(`[${serial}] Mirror failed:`, error);
    console.log(`[${serial}] Timeline: ${timeline.join(' | ')}`);
  }
}

async function connect() {
  if (isConnecting) {
    console.warn('Already connecting, please wait...');
    return;
  }

  try {
    isConnecting = true;
    const url = normalizeBridgeWebSocketUrl(endpointInput.value.trim());
    connectSessionStart = performance.now();
    setStatus('Connecting…', false);

    if (!serverClient) {
      console.log('Creating new server client...');
      const connector = new AdbWebSocketConnector(url);
      serverClient = new AdbServerClient(connector);
    } else {
      console.log('Reusing existing server client');

      // ============================================================================
      // CRITICAL FIX: Health check before reuse
      // ============================================================================
      try {
        await Promise.race([
          serverClient.getDevices(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Health check timeout')), 2000))
        ]);
        console.log('✅ Server client healthy');
      } catch (e) {
        console.warn('❌ Server client unhealthy, recreating...', e);
        const connector = new AdbWebSocketConnector(url);
        serverClient = new AdbServerClient(connector);
      }
    }

    // ============================================================================
    // CRITICAL FIX: Include ALL device states, not just 'device' and 'unauthorized'
    // The library filters out recovery/bootloader/sideload by default
    // ============================================================================
    const devices = await retryWithBackoff(
      () => serverClient!.getDevices([
        'device',
        'unauthorized',
        'offline',
        'recovery' as any,      // Library doesn't expose these in types
        'sideload' as any,      // but ADB protocol supports them
        'bootloader' as any,
      ]),
      3,
      500,
      'getDevices'
    );

    // Debug: Log device objects to see structure
    console.log('🔍 DEBUG: Raw device objects:', devices);
    devices.forEach(d => {
      console.log(`🔍 DEBUG: Device ${d.serial}:`, {
        serial: d.serial,
        state: (d as any).state,
        allProperties: Object.keys(d)
      });
    });

    availableDevices = devices;
    if (devices.length === 0) throw new Error('No devices');

    console.log(`Found ${devices.length} device(s)`);

    const serverSerials = new Set(devices.map(d => d.serial));
    for (const serial of connectedDevices.keys()) {
      if (!serverSerials.has(serial)) {
        console.log(`[${serial}] Device removed`);
        disconnectDevice(serial);
      }
    }

    // ============================================================================
    // CRITICAL FIX: Longer delay after first device to stabilize server client
    // ============================================================================
    for (let i = 0; i < devices.length; i++) {
      const device = devices[i];
      if (!connectedDevices.has(device.serial)) {
        console.log(`\n📱 Device ${i + 1}/${devices.length}: ${device.serial}`);
        await connectToDevice(device);

        if (i < devices.length - 1) {
          const delay = i === 0 ? 800 : 300;  // 800ms after device 1, 300ms after that
          console.log(`⏳ Stabilizing (${delay}ms)...`);
          await new Promise(resolve => setTimeout(resolve, delay));
        }
      }
    }

    const totalTime = ((performance.now() - connectSessionStart!) / 1000).toFixed(2);
    console.log(`\n✅ All ${devices.length} device(s) connected in ${totalTime}s`);

  } catch (error) {
    console.error('Connect error:', error);
    setStatus('Failed', false);
  } finally {
    isConnecting = false;
    setStatus(`${connectedDevices.size} device(s) connected`, connectedDevices.size > 0);
  }
}

async function disconnect() {
  const serials = Array.from(connectedDevices.keys());
  for (const serial of serials) {
    disconnectDevice(serial);
  }

  if (serverClient) {
    try {
      (serverClient as any).connector?.close?.();
    } catch (e) {
      console.warn('Error closing server client:', e);
    }
    serverClient = undefined;
  }

  syncGloballyDisabled.value = false;  // Reset for next connection
  setStatus('Disconnected', false);
  isConnecting = false;
}

async function runShell() {
  const device = connectedDevices.get(currentSelectedSerial || '');
  if (!device || !shellCommand.value) return;
  const cmd = shellCommand.value;
  appendShell(cmd);
  shellCommand.value = '';
  try {
    const socket = await device.adb.createSocket(`shell:${cmd}`);
    const decoder = new TextDecoder();
    for await (const chunk of socket.readable) {
      appendShell(decoder.decode(chunk).trim());
    }
  } catch (error) {
    appendShell(`Error: ${error}`);
  }
}

function openDeviceModal(serial: string) {
  const device = connectedDevices.get(serial);
  if (!device || !device.scrcpyClient) return;
  currentModalDevice = serial;
  modalDeviceTitle.textContent = device.properties?.model || serial;
  deviceModal.style.display = 'flex';
  updateVisibilityState();
  setupModalCanvasControls(device);
}

function closeDeviceModal() {
  if (!currentModalDevice) return;
  deviceModal.style.display = 'none';
  currentModalDevice = null;
  if (modalAbortController) {
    modalAbortController.abort();
    modalAbortController = null;
  }
  updateVisibilityState();
}

async function setupModalCanvasControls(device: DeviceConnection) {
  const { scrcpyClient } = device;
  if (!scrcpyClient?.controller) return;
  const controller = scrcpyClient.controller;
  const videoStream = await scrcpyClient.videoStream;
  if (!videoStream) return;

  if (modalAbortController) modalAbortController.abort();
  modalAbortController = new AbortController();
  const signal = modalAbortController.signal;

  let lastModalTouchTime = 0;
  const touchThrottle = 16;

  const sendTouch = (type: number, e: PointerEvent) => {
    if (!videoStream.metadata.width || !videoStream.metadata.height) return;
    const now = performance.now();
    if (type === 2 && now - lastModalTouchTime < touchThrottle) return;
    lastModalTouchTime = now;

    const rect = modalCanvas.getBoundingClientRect();
    const x = (e.clientX - rect.left) * (modalCanvas.width / rect.width);
    const y = (e.clientY - rect.top) * (modalCanvas.height / rect.height);

    controller.injectTouch({
      action: type as AndroidMotionEventAction,
      pointerId: BigInt(0),
      pointerX: Math.max(0, Math.min(x, videoStream.metadata.width)),
      pointerY: Math.max(0, Math.min(y, videoStream.metadata.height)),
      videoWidth: videoStream.metadata.width,
      videoHeight: videoStream.metadata.height,
      pressure: (type === 0 || type === 2) ? 1 : 0,
      actionButton: 1,
      buttons: e.buttons,
    });
  };

  modalCanvas.addEventListener('pointerdown', (e) => {
    modalCanvas.setPointerCapture(e.pointerId);
    sendTouch(0, e);
  }, { signal });

  modalCanvas.addEventListener('pointermove', (e) => {
    if (e.buttons === 1) sendTouch(2, e);
  }, { signal });

  modalCanvas.addEventListener('pointerup', (e) => {
    sendTouch(1, e);
    modalCanvas.releasePointerCapture(e.pointerId);
  }, { signal });

  modalCanvas.tabIndex = 0;
  modalCanvas.addEventListener('keydown', async (e) => {
    if (e.ctrlKey || e.altKey || e.metaKey) return;
    try {
      if (e.key === 'Backspace') {
        e.preventDefault();
        await ScrcpyBatchController.injectKey(controller, 67);
      } else if (e.key === 'Enter') {
        e.preventDefault();
        await ScrcpyBatchController.injectKey(controller, AndroidKeyCode.Enter);
      } else if (e.key.length === 1) {
        e.preventDefault();
        await controller.injectText(e.key);
      }
    } catch (error) {
      console.error(`[${device.serial}] Modal keyboard error:`, error);
    }
  }, { signal });

  // ============================================================================
  // Clipboard Synchronization: Browser → Device (Modal)
  // ============================================================================
  const syncBrowserToDevice = async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (text && text.length > 0) {
        await controller.setClipboard({
          content: text,
          sequence: BigInt(Date.now()),
          paste: false,
        });
        console.log(`[${device.serial}] 📋 Browser clipboard → Device (modal)`);
      }
    } catch (e) {
      console.debug(`[${device.serial}] Could not sync browser clipboard to device:`, e);
    }
  };

  modalCanvas.addEventListener('focus', syncBrowserToDevice, { signal });
  modalCanvas.addEventListener('click', syncBrowserToDevice, { signal });
}

function setupControlListeners() {
  const handleControlAction = async (action: string | null, isModal: boolean) => {
    const serial = isModal ? currentModalDevice : currentSelectedSerial;
    const device = connectedDevices.get(serial || '');
    if (!device?.scrcpyClient?.controller) return;
    const controller = device.scrcpyClient.controller;

    try {
      if (action === 'back') await ScrcpyBatchController.injectKey(controller, 4);
      if (action === 'home') await ScrcpyBatchController.injectKey(controller, 3);
      if (action === 'wake') {
        await controller.backOrScreenOn(AndroidKeyEventAction.Down);
        await controller.backOrScreenOn(AndroidKeyEventAction.Up);
      }
    } catch (e) {
      console.error(`Control action ${action} failed:`, e);
    }
  };

  document.querySelectorAll('.ctrl-btn').forEach(btn => {
    btn.addEventListener('click', () => handleControlAction(btn.getAttribute('data-action'), false));
  });

  document.querySelectorAll('.modal-control-btn').forEach(btn => {
    btn.addEventListener('click', () => handleControlAction(btn.getAttribute('data-action'), true));
  });
}

setupControlListeners();

searchInput.addEventListener('input', () => {
  const query = searchInput.value.toLowerCase();
  document.querySelectorAll('.device-card').forEach(card => {
    const text = card.textContent?.toLowerCase() || '';
    (card as HTMLElement).style.display = text.includes(query) ? 'flex' : 'none';
  });
});

// Slice B: expose legacy connect/disconnect for the React ConnectionPanel.
// Replaced by a real service in later slices.
(window as any).__legacyBridge = { connect, disconnect };

// Slice C: expose the device-pane callbacks for React DevicesPane.
// Replaced by direct service calls in later slices.
(window as any).__legacyDevices = {
  openDeviceModal,
  disconnectDevice,
  openIosStream,
  refresh: connect,
};

// Slice C: when React DevicesPane changes adbDeviceStore.selectedSerial,
// drive the legacy detail pane (Live Stream View, Quick Actions, etc.) which
// still owns rendering until Slice D migrates it.
let __lastSelectedSerial: string | undefined;
adbDeviceStore.subscribe(() => {
  const next = adbDeviceStore.getState().selectedSerial;
  if (next === __lastSelectedSerial) return;
  __lastSelectedSerial = next;
  if (next && connectedDevices.has(next)) {
    updateDeviceDetail(next);
  } else if (!next) {
    if (detailContent) detailContent.style.display = 'none';
    if (detailEmpty) detailEmpty.style.display = 'flex';
    currentSelectedSerial = null;
  }
});

connectButton?.addEventListener('click', connect);
disconnectButton?.addEventListener('click', disconnect);
refreshBtn?.addEventListener('click', connect);
closeModalButton?.addEventListener('click', closeDeviceModal);
closeIosModalButton?.addEventListener('click', closeIosStream);
iosModeFastButton?.addEventListener('click', () => {
  if (!iosCurrentDevice) return;
  if (iosStreamProfile === 'fast') return;
  openIosStream(iosCurrentDevice, 'fast');
});
iosModeRtcButton?.addEventListener('click', () => {
  if (!iosCurrentDevice) return;
  if (iosStreamProfile === 'rtc') return;
  openIosStream(iosCurrentDevice, 'rtc');
});
iosModeWorkerButton?.addEventListener('click', () => {
  if (!iosCurrentDevice) return;
  if (iosStreamProfile === 'worker') return;
  openIosStream(iosCurrentDevice, 'worker');
});
iosModeEcoButton?.addEventListener('click', () => {
  if (!iosCurrentDevice) return;
  if (iosStreamProfile === 'eco') return;
  openIosStream(iosCurrentDevice, 'eco');
});
shellRun?.addEventListener('click', runShell);
shellCommand?.addEventListener('keydown', (e) => { if (e.key === 'Enter') runShell(); });
toggleShellBtn?.addEventListener('click', () => {
  shellPane.style.display = shellPane.style.display === 'none' ? 'flex' : 'none';
});

// Pull File event handlers
pullFileBtn?.addEventListener('click', () => {
  if (currentSelectedSerial && pullFilePathInput?.value) {
    pullFile(currentSelectedSerial, pullFilePathInput.value);
  }
});
pullFilePathInput?.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && currentSelectedSerial && pullFilePathInput.value) {
    pullFile(currentSelectedSerial, pullFilePathInput.value);
  }
});

const defaultHost = window.location.origin.replace(/\/?$/, '');
const urlParams = new URLSearchParams(window.location.search);
const bridgeParam = urlParams.get('bridge');
if (bridgeParam) {
  endpointInput.value = bridgeParam;
} else {
      endpointInput.value = `${defaultHost.replace('8000', '15037')}/bridge`;
}

// Slice A: mirror the legacy endpoint input into bridgeStore so future React
// components and the new services read the same value the user types.
setBridgeUrl(endpointInput.value);
endpointInput.addEventListener('input', () => setBridgeUrl(endpointInput.value));
endpointInput.addEventListener('change', () => setBridgeUrl(endpointInput.value));

setStatus('Disconnected', false);

setupIosControlListeners();

setIosMode(getDefaultIosControlProfile());

// iOS discovery runs independently from Android ADB connect.
if (iosDevicesContainer) {
  window.setTimeout(() => {
    refreshIosDevices();
    iosPollTimer = window.setInterval(refreshIosDevices, 5000);
  }, 250);
  endpointInput?.addEventListener('change', () => refreshIosDevices());
}

// ============================================================================
// Screen View Implementation (Available Globally)
// ============================================================================

// Make setScreenViewMode globally available
(window as any).setScreenViewMode = (mode: 'grid' | 'focus') => {
  screenViewMode = mode;
  document.getElementById(`view-mode-grid`)?.classList.toggle('active', mode === 'grid');
  document.getElementById(`view-mode-focus`)?.classList.toggle('active', mode === 'focus');
  renderScreenView();
};

(window as any).setScreenPlatform = (platform: 'android' | 'ios') => {
  if (screenPlatform === platform) return;
  screenPlatform = platform;
  document.getElementById('screen-platform-android')?.classList.toggle('active', platform === 'android');
  document.getElementById('screen-platform-ios')?.classList.toggle('active', platform === 'ios');
  if (platform === 'android') {
    stopAllIosGridStreams();
  }
  renderScreenView();
};

screenZoomInput?.addEventListener('input', (e) => {
  screenScale = parseFloat((e.target as HTMLInputElement).value);
  screenZoomValue.textContent = `${Math.round(screenScale * 100)}%`;
  renderScreenView();
});

function renderScreenView() {
  if (!screenGrid) return;
  stopAllIosGridStreams();
  screenGrid.innerHTML = ''; // Clear existing

  // Apply grid logic
  screenGrid.style.setProperty('--card-width', `${240 * screenScale}`);

  if (screenViewMode === 'focus') {
    screenGrid.style.display = 'flex';
    screenGrid.style.justifyContent = 'center';
    screenGrid.style.alignItems = 'flex-start';
  } else {
    screenGrid.style.display = 'grid';
  }

  if (screenPlatform === 'ios') {
    renderIosScreenViewCards();
  } else {
    renderAndroidScreenViewCards();
  }
}

function renderAndroidScreenViewCards() {
  if (!screenGrid) return;

  if (connectedDevices.size === 0) {
    screenGrid.innerHTML = '<div class="empty-state"><h3>No Android Devices</h3><p>Connect Android devices to show live mirrors.</p></div>';
    return;
  }

  connectedDevices.forEach((device) => {
    const card = document.createElement('div');
    card.className = 'device-screen-card';
    card.style.width = screenViewMode === 'focus' ? '360px' : `${240 * screenScale}px`;
    card.onclick = () => {
      // Handle selection logic if needed
      document.querySelectorAll('.device-screen-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');
      updateDeviceDetail(device.serial); // Also update detail view
    };
    card.ondblclick = (e) => {
      e.preventDefault();
      openDeviceModal(device.serial);
    };

    const isMini = screenScale < 0.6;
    const canvasId = `screen-canvas-${device.serial}`;

    card.innerHTML = `
      <div class="screen-frame">
        ${!isMini ? `
        <div class="screen-notch"></div>
        <div class="screen-hud">
          <div class="live-badge">
            <div class="pulse-dot"></div> LIVE
          </div>
        </div>
        ` : ''}
        
        <div class="screen-canvas-wrapper">
          <canvas id="${canvasId}"></canvas>
        </div>
      </div>
      <div class="device-label">${device.properties?.model || device.serial}</div>
      <div class="selected-indicator">🎯</div>
    `;

    screenGrid.appendChild(card);

    // Cache canvas reference for performance
    const canvas = document.getElementById(canvasId) as HTMLCanvasElement;
    if (canvas) {
      device.screenViewCanvas = canvas;
    }
  });
}

function renderIosScreenViewCards() {
  if (!screenGrid) return;

  if (iosDevices.length === 0) {
    screenGrid.innerHTML = '<div class="empty-state"><h3>No iOS Devices</h3><p>Switch on TLinkauto and wait for discovery.</p></div>';
    return;
  }

  for (const device of iosDevices) {
    const card = document.createElement('div');
    card.className = 'device-screen-card ios-screen-card';
    card.style.width = screenViewMode === 'focus' ? '360px' : `${240 * screenScale}px`;

    card.onclick = () => {
      document.querySelectorAll('.device-screen-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');
    };
    card.ondblclick = (e) => {
      e.preventDefault();
      iosModalOpenedFromGridDeviceId = device.id;
      iosGridSuspendedForControl.add(device.id);
      stopIosGridStream(device.id);
      openIosStream(device, getDefaultIosControlProfile(device));
    };

    const isMini = screenScale < 0.6;
    const safeId = device.id.replace(/[^a-zA-Z0-9_-]/g, '_');
    const canvasId = `ios-screen-canvas-${safeId}`;
    const meta = device.meta?.device;
    const label = device.display_name || meta?.name || device.id;

    card.innerHTML = `
      <div class="screen-frame">
        ${!isMini ? `
        <div class="screen-notch"></div>
        <div class="screen-hud">
          <div class="live-badge ios-live-badge">
            <div class="pulse-dot"></div> iOS Worker
          </div>
        </div>
        ` : ''}
        <div class="screen-canvas-wrapper">
          <canvas id="${canvasId}"></canvas>
        </div>
      </div>
      <div class="device-label">${label}</div>
      <div class="selected-indicator">🎯</div>
    `;

    screenGrid.appendChild(card);

    const canvas = document.getElementById(canvasId) as HTMLCanvasElement | null;
    if (canvas && !iosGridSuspendedForControl.has(device.id) && isScreenViewVisible) {
      startIosGridWorkerStream(device, canvas);
    }
  }
}

function updateScreenViewVisibility() {
  const activeTab = document.querySelector('.nav-item[data-tab="screen_view"]');
  if (activeTab && activeTab.classList.contains('active')) {
    screenViewPane.style.display = 'flex';
    // Hide other panes
    const mainContent = document.getElementById('main-content');
    if (mainContent) {
      Array.from(mainContent.children).forEach((child) => {
        if (child.id !== 'screen-view-pane') {
          (child as HTMLElement).style.display = 'none';
        }
      });
    }
  } else {
    screenViewPane.style.display = 'none';
    stopAllIosGridStreams();
  }
  updateVisibilityState();
}

// ============================================================================
// UI Navigation Logic
// ============================================================================
document.querySelectorAll('.nav-item').forEach(item => {
  item.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    item.classList.add('active');
    const tab = item.getAttribute('data-tab');
    window.dispatchEvent(new CustomEvent('automation-ide-visibility', { detail: { visible: tab === 'automation_ide' } }));

    // Type-safe references
    const deviceList = document.querySelector('.device-list-pane') as HTMLElement;
    const deviceDetail = document.querySelector('.device-detail-pane') as HTMLElement;
    const screenView = document.getElementById('screen-view-pane') as HTMLElement;
    const automationIde = document.getElementById('automation-ide-pane') as HTMLElement;

    // Default state: hide all
    if (deviceList) deviceList.style.display = 'none';
    if (deviceDetail) deviceDetail.style.display = 'none';
    if (screenView) screenView.style.display = 'none';
    if (automationIde) automationIde.style.display = 'none';

    if (tab === 'devices') {
      if (deviceList) deviceList.style.display = 'block';
      if (currentSelectedSerial && deviceDetail) deviceDetail.style.display = 'block';
    } else if (tab === 'screen_view') {
      if (screenView) {
        screenView.style.display = 'flex';
        updateVisibilityState();
        renderScreenView();
      }
    } else if (tab === 'automation_ide') {
      if (automationIde) {
        automationIde.style.display = 'block';
        ensureAutomationIdeMounted().catch((e) => console.error('[automation-ide] mount failed', e));
      }
    } else {
      // Placeholder for other tabs
      console.log(`Tab ${tab} not implemented yet`);
    }

    updateScreenViewVisibility();
  });
});
