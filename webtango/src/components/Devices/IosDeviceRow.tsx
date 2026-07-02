import type { UnifiedDevice } from '../../services/deviceRegistry';

type Props = {
  device: UnifiedDevice;
  index: number;
  onOpenStream: (device: UnifiedDevice) => void;
};

export function IosDeviceRow({ device, index, onOpenStream }: Props) {
  const info = device.meta?.device;
  const ip = device.meta?.ip;
  const meta = info
    ? `${info.model || 'iPhone'} • iOS ${info.system_version || '--'} • ${ip || '--'}`
    : `iOS • ${ip || '--'}`;
  const online = device.status === 'online';

  return (
    <div
      className="device-card ios-card table-row-item"
      data-ios-id={device.id}
      onDoubleClick={() => onOpenStream(device)}
    >
      <div className="col-checkbox" onClick={(e) => e.stopPropagation()}>
        <input type="checkbox" className="table-checkbox" />
      </div>
      <div className="col-no table-index-cell">{index + 1}</div>
      <div className="col-serial font-mono card-name">{device.display_name || device.id}</div>
      <div className="col-model font-medium device-meta">{meta}</div>
      <div className="col-platform">
        <span className="platform-badge badge-ios">iOS</span>
      </div>
      <div className="col-status">
        <div className="status-cell">
          <div className="status-indicator" />
          <span className={`status-badge ${online ? 'badge-online' : 'badge-offline'}`}>
            {online ? 'ONLINE' : 'OFFLINE'}
          </span>
        </div>
      </div>
      <div className="row-hover-actions">
        <button
          type="button"
          className="row-action-btn btn-view-stream"
          title="Start iOS Stream"
          onClick={(e) => { e.stopPropagation(); onOpenStream(device); }}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polygon points="6 3 20 12 6 21 6 3" />
          </svg>
        </button>
      </div>
    </div>
  );
}
