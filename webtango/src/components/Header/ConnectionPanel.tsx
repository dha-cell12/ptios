import { useEffect, useRef } from 'react';
import { useStore } from '../../stores/useStore';
import { bridgeStore, setBridgeUrl, markConnecting, markConnected, markDisconnected, markError, bridge } from '../../stores/BridgeStore';
import { startAdbPolling, stopAdbPolling, adbDeviceManager } from '../../stores/AdbDeviceStore';

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

  useEffect(() => {
    // Listen for manager errors to mark the bridge as error
    const unsub = adbDeviceManager.on('error', (err) => {
      markError(err.message);
    });
    return unsub;
  }, []);

  const onConnect = async () => {
    markConnecting();
    try {
      await bridge.ensure(); // Verify connection works
      markConnected();
      startAdbPolling();
    } catch (e) {
      markError(e instanceof Error ? e.message : String(e));
    }
  };

  const onDisconnect = () => {
    stopAdbPolling();
    markDisconnected();
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
