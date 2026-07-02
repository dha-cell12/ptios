import { useStore } from '../../../stores/useStore';
import { adbDeviceStore } from '../../../stores/AdbDeviceStore';
import { DetailHeader } from './DetailHeader';
import { MirrorSection } from './MirrorSection';
import { ControlBar } from './ControlBar';
import { QuickActions } from './QuickActions';

export function DetailPane() {
  const selectedSerial = useStore(adbDeviceStore, (s) => s.selectedSerial);
  const device = useStore(adbDeviceStore, (s) =>
    s.selectedSerial ? s.devices[s.selectedSerial] : undefined,
  );

  if (!selectedSerial || !device) return null;

  return (
    <section className="detail-pane" data-serial={selectedSerial}>
      <DetailHeader device={device} />
      <MirrorSection serial={selectedSerial} state={device.state} />
      <ControlBar serial={selectedSerial} />
      <QuickActions serial={selectedSerial} />
    </section>
  );
}
