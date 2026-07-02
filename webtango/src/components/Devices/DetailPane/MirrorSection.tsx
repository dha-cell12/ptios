import { useRef } from 'react';
import { useCanvasBinding } from '../../../hooks/useCanvasBinding';

type Props = {
  serial: string;
  state: string;
};

export function MirrorSection({ serial, state }: Props) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  useCanvasBinding(serial, canvasRef, { mode: 'fit', background: '#000' });

  const unavailable = state !== 'device';

  return (
    <div className="mirror-section">
      <div className="mirror-canvas-wrap">
        <canvas
          ref={canvasRef}
          id="device-canvas"
          className="mirror-canvas"
          width={640}
          height={1280}
        />
        {unavailable && (
          <div className="mirror-overlay">
            Mirroring unavailable in {state} mode
          </div>
        )}
      </div>
    </div>
  );
}
