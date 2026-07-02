import { useEffect, useRef } from 'react';
import { useStore } from '../../stores/useStore';
import { bridgeStore, setBridgeUrl } from '../../stores/BridgeStore';

// Slice B: React-owned endpoint input + connect/disconnect + status dot.
// Reads/writes bridgeStore. The actual connect/disconnect logic still lives in
// the legacy main.ts and is invoked via window.__legacyBridge to keep this
// slice scoped to UI only; that bridge goes away in later slices.
type LegacyBridge = {
  connect: () => Promise<void>;
  disconnect: () => Promise<void>;
};

declare global {
  interface Window {
    __legacyBridge?: LegacyBridge;
  }
}

export function ConnectionPanel() {
  const url = useStore(bridgeStore, (s) => s.url);
  const status = useStore(bridgeStore, (s) => s.status);
  const lastError = useStore(bridgeStore, (s) => s.lastError);
  const inputRef = useRef<HTMLInputElement>(null);

  const connected = status === 'connected';
  const connecting = status === 'connecting';
  const dotClass = connected ? 'online' : connecting ? 'connecting' : 'offline';
  const dotTitle = connected ? 'Online' : connecting ? 'Connecting…' : lastError || 'Offline';

  // Keep the legacy endpoint input (still in the DOM until Slice H removes it)
  // and this React input in sync so legacy code paths reading
  // `endpointInput.value` keep working during the migration.
  useEffect(() => {
    const legacy = document.getElementById('endpoint') as HTMLInputElement | null;
    if (legacy && legacy.value !== url) legacy.value = url;
  }, [url]);

  const onConnect = () => {
    void window.__legacyBridge?.connect();
  };

  const onDisconnect = () => {
    void window.__legacyBridge?.disconnect();
  };

  return (
    <div className="header-connection-panel">
      <div
        id="status"
        className={`connection-status-dot ${dotClass}`}
        title={dotTitle}
      />
      <input
        ref={inputRef}
        type="text"
        value={url}
        onChange={(e) => setBridgeUrl(e.target.value)}
        className="address-input"
        placeholder="ws://..."
      />
      <div className="connection-actions">
        <button
          type="button"
          className="conn-btn btn-primary"
          onClick={onConnect}
          disabled={connected || connecting}
        >
          {connecting ? 'Connecting…' : 'Connect'}
        </button>
        <button
          type="button"
          className="conn-btn btn-secondary"
          onClick={onDisconnect}
          disabled={!connected}
        >
          Disconnect
        </button>
      </div>
    </div>
  );
}
