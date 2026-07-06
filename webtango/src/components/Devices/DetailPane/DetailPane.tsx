import { useState } from 'react';
import { useStore } from '../../../stores/useStore';
import { adbDeviceStore } from '../../../stores/AdbDeviceStore';
import { DetailHeader } from './DetailHeader';
import { MirrorSection } from './MirrorSection';
import { ControlBar } from './ControlBar';
import { QuickActions } from './QuickActions';
import { SystemInfo } from './SystemInfo';
import { Resources } from './Resources';
import { ShellTerminal } from './ShellTerminal';
import { PullFileForm } from './PullFileForm';

export function DetailPane() {
  const selectedSerial = useStore(adbDeviceStore, (s) => s.selectedSerial);
  const device = useStore(adbDeviceStore, (s) =>
    s.selectedSerial ? s.devices[s.selectedSerial] : undefined,
  );
  
  const [showShell, setShowShell] = useState(false);
  const [showPull, setShowPull] = useState(false);

  if (!selectedSerial || !device) return null;

  return (
    <section className="device-detail-pane" data-serial={selectedSerial}>
      <div className="detail-device-card" style={{ display: 'block', padding: '16px' }}>
        <DetailHeader device={device} />
      </div>
      
      <div className="detail-sections-container">
        <MirrorSection serial={selectedSerial} state={device.state} />
        
        {device.state === 'device' && (
          <QuickActions 
            serial={selectedSerial} 
            onToggleShell={() => setShowShell(s => !s)}
            onTogglePull={() => setShowPull(s => !s)}
          />
        )}
        
        {device.state === 'device' && <SystemInfo serial={selectedSerial} />}
        {device.state === 'device' && <Resources serial={selectedSerial} />}
        
        {showShell && <ShellTerminal serial={selectedSerial} />}
        {showPull && <PullFileForm serial={selectedSerial} />}
      </div>
    </section>
  );
}
