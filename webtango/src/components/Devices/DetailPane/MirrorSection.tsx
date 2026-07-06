import { useRef } from 'react';
import { useCanvasBinding } from '../../../hooks/useCanvasBinding';
import { useDeviceControl } from '../../../hooks/useDeviceControl';
import { ControlBar } from './ControlBar';

type Props = {
  serial: string;
  state: string;
};

export function MirrorSection({ serial, state }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  useCanvasBinding(serial, canvasRef, { mode: 'fit', background: '#000' });
  useDeviceControl(serial, canvasRef);

  const unavailable = state !== 'device';

  return (
    <div className="collapsible-section open">
      <div className="collapsible-header">
        <span>Live Stream View</span>
        <span className="collapse-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-chevron-down"><path d="m6 9 6 6 6-6"/></svg>
        </span>
      </div>
      <div className="collapsible-content">
        <div className="mirror-section" style={{ flexDirection: 'row', gap: '20px' }}>
          <div className="screen-container">
            <canvas
              ref={canvasRef}
              className="mirror-canvas"
              width={640}
              height={1280}
              style={{ width: '100%', height: '100%', objectFit: 'contain' }}
            />
          </div>
          {!unavailable && <ControlBar serial={serial} />}
          {unavailable && (
            <div className="mirror-overlay" style={{ position: 'absolute', color: '#94a3b8' }}>
              Mirroring unavailable in {state} mode
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
