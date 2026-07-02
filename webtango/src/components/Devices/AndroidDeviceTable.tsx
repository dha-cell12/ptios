import { useStore } from '../../stores/useStore';
import { adbDeviceStore } from '../../stores/AdbDeviceStore';
import { uiStore } from '../../stores/UiStore';
import { AndroidDeviceRow } from './AndroidDeviceRow';
import type { AdbDeviceRecord } from '../../services/adb/AdbDeviceManager';

function matchesFilter(device: AdbDeviceRecord, filter: string): boolean {
  if (filter === 'all') return true;
  if (filter === 'online') return device.state === 'device';
  if (filter === 'offline') return device.state !== 'device';
  if (filter === 'usb') return !device.serial.includes(':');
  if (filter === 'wifi') return device.serial.includes(':');
  return true;
}

function matchesQuery(device: AdbDeviceRecord, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  if (device.serial.toLowerCase().includes(q)) return true;
  const model = device.properties?.model?.toLowerCase() || '';
  const version = device.properties?.version?.toLowerCase() || '';
  return model.includes(q) || version.includes(q);
}

type Props = {
  onOpenModal: (serial: string) => void;
  onPowerOff: (serial: string) => void;
};

export function AndroidDeviceTable({ onOpenModal, onPowerOff }: Props) {
  const devices = useStore(adbDeviceStore, (s) => s.devices);
  const order = useStore(adbDeviceStore, (s) => s.order);
  const selectedSerial = useStore(adbDeviceStore, (s) => s.selectedSerial);
  const filter = useStore(uiStore, (s) => s.deviceFilter);
  const query = useStore(uiStore, (s) => s.searchQuery);

  const items = order
    .map((serial) => devices[serial])
    .filter((d): d is AdbDeviceRecord => !!d)
    .filter((d) => matchesFilter(d, filter))
    .filter((d) => matchesQuery(d, query));

  if (items.length === 0) {
    return (
      <div className="device-list-table" id="devices-container">
        <div className="empty-state">
          <div className="empty-icon">
            <svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="m18 10 2.5-2.5a2.5 2.5 0 0 0-3.5-3.5L14.5 6.5" />
              <path d="m14 10 1.5-1.5" />
              <path d="M8.5 15.5 10 14" />
              <path d="m9 11-6 6a2 2 0 0 0 2 2h3l6-6" />
              <path d="M13 18h9" />
            </svg>
          </div>
          <h3>No Android Devices</h3>
          <p>Verify WebSocket connection or connect an Android device via USB/Wi-Fi.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="device-list-table" id="devices-container">
      {items.map((device, idx) => (
        <AndroidDeviceRow
          key={device.serial}
          device={device}
          index={idx}
          selected={selectedSerial === device.serial}
          onOpenModal={onOpenModal}
          onPowerOff={onPowerOff}
        />
      ))}
    </div>
  );
}
