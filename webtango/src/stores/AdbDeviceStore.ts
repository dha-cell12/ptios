import { createStore } from './createStore';
import { AdbDeviceManager, type AdbDeviceRecord } from '../services/adb/AdbDeviceManager';
import { bridge } from './BridgeStore';
import { startScrcpyMirror } from '../services/adb/ScrcpyMirror';
import { registerMirrorSession, unregisterMirrorSession, getMirrorSession } from './ScrcpyMirrorStore';
import { Adb } from '@yume-chan/adb';

export type AdbDeviceMap = Record<string, AdbDeviceRecord>;

export type AdbDeviceStoreState = {
  devices: AdbDeviceMap;
  order: string[];
  selectedSerial: string | undefined;
  modalSerial: string | undefined;
  lastRefreshAt: number | undefined;
  isPolling: boolean;
};

export const adbDeviceStore = createStore<AdbDeviceStoreState>({
  devices: {},
  order: [],
  selectedSerial: undefined,
  modalSerial: undefined,
  lastRefreshAt: undefined,
  isPolling: false,
});

export const adbDeviceManager = new AdbDeviceManager(bridge);

async function startMirrorWrapper(serial: string) {
  const client = await bridge.ensure();
  const transport = await client.createTransport({ serial });
  const adb = new Adb(transport);
  return startScrcpyMirror(adb, serial);
}

function commit(snapshot: AdbDeviceRecord[]) {
  const devices: AdbDeviceMap = {};
  const order: string[] = [];
  for (const record of snapshot) {
    devices[record.serial] = record;
    order.push(record.serial);
  }
  adbDeviceStore.setState({
    devices,
    order,
    lastRefreshAt: performance.now(),
  });
}

adbDeviceManager.on('refreshed', (snapshot) => {
  commit(snapshot);
  // Auto-start mirrors for newly discovered devices during refresh
  for (const record of snapshot) {
    if (!getMirrorSession(record.serial)) {
      startMirrorWrapper(record.serial).then(registerMirrorSession).catch(e => console.warn('Mirror start failed', e));
    }
  }
});

adbDeviceManager.on('added', (record) => {
  commit(adbDeviceManager.list());
  if (!getMirrorSession(record.serial)) {
    startMirrorWrapper(record.serial).then(registerMirrorSession).catch(e => console.warn('Mirror start failed', e));
  }
});

adbDeviceManager.on('removed', ({ serial }) => {
  const { selectedSerial, modalSerial } = adbDeviceStore.getState();
  adbDeviceStore.setState({
    selectedSerial: selectedSerial === serial ? undefined : selectedSerial,
    modalSerial: modalSerial === serial ? undefined : modalSerial,
  });
  commit(adbDeviceManager.list());
  
  const session = getMirrorSession(serial);
  if (session) {
    session.stop();
    unregisterMirrorSession(serial);
  }
});

adbDeviceManager.on('changed', () => commit(adbDeviceManager.list()));

export function startAdbPolling(intervalMs = 2000) {
  adbDeviceManager.startPolling(intervalMs);
  adbDeviceStore.setState({ isPolling: true });
}

export function stopAdbPolling() {
  adbDeviceManager.stopPolling();
  adbDeviceStore.setState({ isPolling: false });
}

export function selectAdbDevice(serial: string | undefined) {
  adbDeviceStore.setState({ selectedSerial: serial });
}

export function openAdbModal(serial: string) {
  adbDeviceStore.setState({ modalSerial: serial });
}

export function closeAdbModal() {
  adbDeviceStore.setState({ modalSerial: undefined });
}

export function setAdbDeviceProperties(serial: string, properties: Record<string, string>) {
  adbDeviceManager.setProperties(serial, properties);
}

export function getAdbDevice(serial: string): AdbDeviceRecord | undefined {
  return adbDeviceStore.getState().devices[serial];
}

// Slice C: legacy connect/disconnect flow in main.ts pushes here directly
// instead of relying on AdbDeviceManager polling (legacy owns the
// AdbServerClient lifecycle and the connectedDevices Map for now).
export function upsertLegacyDevice(record: AdbDeviceRecord) {
  const state = adbDeviceStore.getState();
  const devices = { ...state.devices, [record.serial]: record };
  const order = state.order.includes(record.serial)
    ? state.order
    : [...state.order, record.serial];
  adbDeviceStore.setState({
    devices,
    order,
    lastRefreshAt: performance.now(),
  });
}

export function removeLegacyDevice(serial: string) {
  const state = adbDeviceStore.getState();
  if (!(serial in state.devices)) return;
  const devices = { ...state.devices };
  delete devices[serial];
  const order = state.order.filter((s) => s !== serial);
  adbDeviceStore.setState({
    devices,
    order,
    selectedSerial: state.selectedSerial === serial ? undefined : state.selectedSerial,
    modalSerial: state.modalSerial === serial ? undefined : state.modalSerial,
    lastRefreshAt: performance.now(),
  });
}
