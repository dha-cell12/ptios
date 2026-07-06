import { createStore } from './createStore';
import { AdbBridge } from '../services/adb/AdbBridge';

export type BridgeStatus = 'idle' | 'connecting' | 'connected' | 'error' | 'disconnected';

export type BridgeState = {
  url: string;
  status: BridgeStatus;
  lastError: string | undefined;
  connectStartedAt: number | undefined;
  connectedAt: number | undefined;
};

const DEFAULT_URL = (() => {
  const params = new URLSearchParams(window.location.search);
  const fromParam = params.get('bridge');
  if (fromParam) return fromParam;
  const host = window.location.origin.replace(/\/?$/, '');
  return `${host.replace('8000', '15037')}/bridge`;
})();

export const bridgeStore = createStore<BridgeState>({
  url: DEFAULT_URL,
  status: 'idle',
  lastError: undefined,
  connectStartedAt: undefined,
  connectedAt: undefined,
});

export const bridge = new AdbBridge();
bridge.setEndpoint(DEFAULT_URL);

export function setBridgeUrl(url: string) {
  bridgeStore.setState({ url });
  bridge.setEndpoint(url);
}

export function markConnecting() {
  bridgeStore.setState({
    status: 'connecting',
    connectStartedAt: performance.now(),
    lastError: undefined,
  });
}

export function markConnected() {
  bridgeStore.setState({
    status: 'connected',
    connectedAt: performance.now(),
    lastError: undefined,
  });
}

export function markDisconnected() {
  bridgeStore.setState({
    status: 'disconnected',
    connectedAt: undefined,
    connectStartedAt: undefined,
  });
}

export function markError(message: string) {
  bridgeStore.setState({ status: 'error', lastError: message });
}
