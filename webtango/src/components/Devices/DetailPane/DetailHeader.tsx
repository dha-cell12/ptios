import type { AdbDeviceRecord } from '../../../services/adb/AdbDeviceManager';

type Props = {
  device: AdbDeviceRecord;
};

function stateBadge(state: string): { label: string; cls: string } {
  switch (state) {
    case 'device': return { label: 'LIVE', cls: 'badge-online' };
    case 'recovery': return { label: 'RECOVERY', cls: 'badge-recovery' };
    case 'sideload': return { label: 'SIDELOAD', cls: 'badge-sideload' };
    case 'bootloader': return { label: 'BOOTLOADER', cls: 'badge-bootloader' };
    case 'unauthorized': return { label: 'UNAUTHORIZED', cls: 'badge-unauthorized' };
    case 'offline': return { label: 'OFFLINE', cls: 'badge-offline' };
    default: return { label: (state || 'UNKNOWN').toUpperCase(), cls: 'badge-offline' };
  }
}

export function DetailHeader({ device }: Props) {
  const props = device.properties || {};
  const model = props.model || 'Connecting...';
  const brand = props.brand;
  const version = props.version;
  const arch = props.arch || props.abi;
  const initials = (model || device.serial).slice(0, 2).toUpperCase();
  const { label, cls } = stateBadge(device.state);

  const metaParts: string[] = [];
  if (brand) metaParts.push(brand);
  if (version) metaParts.push(`Android ${version}`);
  if (arch) metaParts.push(arch);
  if (!metaParts.length) metaParts.push(device.serial);

  return (
    <div className="detail-device-info">
      <div className="detail-avatar" aria-hidden="true" style={{ fontSize: '16px', fontWeight: 'bold' }}>{initials}</div>
      <div className="detail-titles">
        <h3>{model}</h3>
        <p className="detail-full-meta">{metaParts.join(' \u2022 ')}</p>
      </div>
      {device.state === 'device' ? (
        <span className="live-badge">
          <span className="pulse-dot"></span> LIVE
        </span>
      ) : (
        <span className={`status-badge ${cls}`}>{label}</span>
      )}
    </div>
  );
}
