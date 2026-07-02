import { useStore } from '../../stores/useStore';
import { uiStore, setDeviceFilter, type DeviceFilter } from '../../stores/UiStore';

const FILTERS: { value: DeviceFilter; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'online', label: 'Online' },
  { value: 'offline', label: 'Offline' },
  { value: 'usb', label: 'USB' },
  { value: 'wifi', label: 'WiFi' },
];

export function FilterPills() {
  const active = useStore(uiStore, (s) => s.deviceFilter);
  return (
    <div className="filter-pills">
      {FILTERS.map((f) => (
        <button
          key={f.value}
          type="button"
          className={`filter-pill ${active === f.value ? 'active' : ''}`}
          onClick={() => setDeviceFilter(f.value)}
        >
          {f.label}
        </button>
      ))}
    </div>
  );
}
