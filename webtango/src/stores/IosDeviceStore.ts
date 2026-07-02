import { createStore } from './createStore';
import { fetchUnifiedDevices } from '../services/ios/IosBridgeApi';
import { IosGridStreams } from '../services/ios/IosGridStreams';
import { bridgeStore } from './BridgeStore';
import type { UnifiedDevice } from '../services/deviceRegistry';
import type { IosStreamProfile } from '../services/ios/IosStreamController';
import type { IosControlMode } from '../services/ios/IosControlChannel';

export type IosDeviceStoreState = {
  devices: UnifiedDevice[];
  signature: string;
  modalDeviceId: string | undefined;
  modalOpenedFromGridId: string | undefined;
  streamProfile: IosStreamProfile;
  controlMode: IosControlMode;
  forceRelay: boolean;
  lastRefreshAt: number | undefined;
  pollIntervalMs: number;
  lastError: string | undefined;
};

function deriveDefaults() {
  const params = new URLSearchParams(window.location.search);
  const controlMode: IosControlMode = params.get('iosControlMode') === 'ephemeral' ? 'ephemeral' : 'persistent';
  const forceRelay = params.get('rtcForceRelay') === '1';
  return { controlMode, forceRelay };
}

export const iosDeviceStore = createStore<IosDeviceStoreState>({
  devices: [],
  signature: '',
  modalDeviceId: undefined,
  modalOpenedFromGridId: undefined,
  streamProfile: 'rtc',
  controlMode: deriveDefaults().controlMode,
  forceRelay: deriveDefaults().forceRelay,
  lastRefreshAt: undefined,
  pollIntervalMs: 5000,
  lastError: undefined,
});

export const iosGridStreams = new IosGridStreams();

function deviceSignature(devices: UnifiedDevice[]) {
  return devices
    .map((d) => `${d.id}|${d.status}|${d.display_name}|${d.meta?.ip || ''}|${d.meta?.device?.system_version || ''}`)
    .sort()
    .join('\n');
}

let pollTimer: number | undefined;

export async function refreshIosDevices(): Promise<void> {
  const url = bridgeStore.getState().url;
  if (!url) return;
  try {
    const all = await fetchUnifiedDevices(url);
    const ios = all.filter((d) => d.platform === 'ios');
    const sig = deviceSignature(ios);
    if (sig === iosDeviceStore.getState().signature) {
      iosDeviceStore.setState({ lastRefreshAt: performance.now() });
      return;
    }
    iosDeviceStore.setState({
      devices: ios,
      signature: sig,
      lastRefreshAt: performance.now(),
      lastError: undefined,
    });
  } catch (e) {
    iosDeviceStore.setState({ lastError: String(e) });
  }
}

export function startIosPolling() {
  if (pollTimer !== undefined) return;
  void refreshIosDevices();
  pollTimer = window.setInterval(() => void refreshIosDevices(), iosDeviceStore.getState().pollIntervalMs);
}

export function stopIosPolling() {
  if (pollTimer !== undefined) {
    window.clearInterval(pollTimer);
    pollTimer = undefined;
  }
}

export function setIosStreamProfile(profile: IosStreamProfile) {
  iosDeviceStore.setState({ streamProfile: profile });
}

export function openIosModal(deviceId: string, fromGrid = false) {
  if (fromGrid) iosGridStreams.suspend(deviceId);
  iosDeviceStore.setState({
    modalDeviceId: deviceId,
    modalOpenedFromGridId: fromGrid ? deviceId : undefined,
  });
}

export function closeIosModal() {
  const { modalOpenedFromGridId } = iosDeviceStore.getState();
  if (modalOpenedFromGridId) iosGridStreams.resume(modalOpenedFromGridId);
  iosDeviceStore.setState({ modalDeviceId: undefined, modalOpenedFromGridId: undefined });
}

export function setIosControlMode(mode: IosControlMode) {
  iosDeviceStore.setState({ controlMode: mode });
}

export function getIosDevice(id: string): UnifiedDevice | undefined {
  return iosDeviceStore.getState().devices.find((d) => d.id === id);
}
