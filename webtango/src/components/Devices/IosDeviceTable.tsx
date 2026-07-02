import { useStore } from '../../stores/useStore';
import { iosDeviceStore } from '../../stores/IosDeviceStore';
import { uiStore } from '../../stores/UiStore';
import { IosDeviceRow } from './IosDeviceRow';
import type { UnifiedDevice } from '../../services/deviceRegistry';

function matchesFilter(device: UnifiedDevice, filter: string): boolean {
  if (filter === 'all') return true;
  if (filter === 'online') return device.status === 'online';
  if (filter === 'offline') return device.status !== 'online';
  return true;
}

function matchesQuery(device: UnifiedDevice, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  if (device.id.toLowerCase().includes(q)) return true;
  if ((device.display_name || '').toLowerCase().includes(q)) return true;
  const info = device.meta?.device;
  if (info?.model?.toLowerCase().includes(q)) return true;
  return false;
}

type Props = {
  onOpenStream: (device: UnifiedDevice) => void;
};

export function IosDeviceTable({ onOpenStream }: Props) {
  const devices = useStore(iosDeviceStore, (s) => s.devices);
  const filter = useStore(uiStore, (s) => s.deviceFilter);
  const query = useStore(uiStore, (s) => s.searchQuery);

  const items = devices
    .filter((d) => matchesFilter(d, filter))
    .filter((d) => matchesQuery(d, query));

  if (items.length === 0) {
    return (
      <div className="device-list-table ios-table-container" id="ios-devices-container">
        <div className="empty-state" id="ios-empty-state">
          <div className="empty-icon">
            <svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect width="14" height="20" x="5" y="2" rx="2" ry="2" />
              <path d="M12 18h.01" />
            </svg>
          </div>
          <h3>No iOS Devices</h3>
          <p>Make sure the iPhone service is reachable on TCP 6000.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="device-list-table ios-table-container" id="ios-devices-container">
      {items.map((device, idx) => (
        <IosDeviceRow
          key={device.id}
          device={device}
          index={idx}
          onOpenStream={onOpenStream}
        />
      ))}
    </div>
  );
}
