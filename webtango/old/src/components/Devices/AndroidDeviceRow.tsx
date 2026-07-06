import type { AdbDeviceRecord } from '../../services/adb/AdbDeviceManager';
import { selectAdbDevice } from '../../stores/AdbDeviceStore';

type Props = {
  device: AdbDeviceRecord;
  index: number;
  selected: boolean;
  onOpenModal: (serial: string) => void;
  onPowerOff: (serial: string) => void;
};

function badgeFor(state: string): { label: string; cls: string } {
  switch (state) {
    case 'device': return { label: 'ONLINE', cls: 'badge-online' };
    case 'recovery': return { label: 'RECOVERY', cls: 'badge-recovery' };
    case 'sideload': return { label: 'SIDELOAD', cls: 'badge-sideload' };
    case 'bootloader': return { label: 'BOOTLOADER', cls: 'badge-bootloader' };
    case 'unauthorized': return { label: 'UNAUTHORIZED', cls: 'badge-unauthorized' };
    case 'offline': return { label: 'OFFLINE', cls: 'badge-offline' };
    default: return { label: state.toUpperCase() || 'UNKNOWN', cls: 'badge-offline' };
  }
}

export function AndroidDeviceRow({ device, index, selected, onOpenModal, onPowerOff }: Props) {
  const { label, cls } = badgeFor(device.state);
  const model = device.properties?.model || 'Connecting...';
  const version = device.properties?.version;
  const meta = version ? `${model} • Android ${version}` : model;

  return (
    <div
      className={`device-card table-row-item ${selected ? 'selected' : ''}`}
      data-serial={device.serial}
      onClick={() => selectAdbDevice(device.serial)}
      onDoubleClick={() => onOpenModal(device.serial)}
    >
      <div className="col-checkbox" onClick={(e) => e.stopPropagation()}>
        <input type="checkbox" className="table-checkbox" />
      </div>
      <div className="col-no table-index-cell">{index + 1}</div>
      <div className="col-serial font-mono card-name">{device.serial}</div>
      <div className="col-model font-medium device-meta">{meta}</div>
      <div className="col-platform">
        <span className="platform-badge badge-android">Android</span>
      </div>
      <div className="col-status">
        <div className="status-cell">
          <div className="status-indicator" />
          <span className={`status-badge ${cls}`}>{label}</span>
        </div>
      </div>
      <div className="row-hover-actions">
        <button
          type="button"
          className="row-action-btn btn-power"
          title="Shut down / Disconnect device"
          onClick={(e) => { e.stopPropagation(); onPowerOff(device.serial); }}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2v10" />
            <path d="M18.4 6.6a9 9 0 1 1-12.77.04" />
          </svg>
        </button>
      </div>
    </div>
  );
}
