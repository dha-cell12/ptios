import { useEffect, type RefObject } from 'react';
import { CanvasDrawRegistry, type DrawTarget } from '../services/canvas/CanvasDrawRegistry';
import { scrcpyMirrorStore } from '../stores/ScrcpyMirrorStore';

export type CanvasBindingOptions = {
  mode?: DrawTarget['mode'];
  background?: string;
};

// Registers a canvas element as a draw target for the given device's scrcpy
// source whenever both (a) the canvas is mounted and (b) a mirror session
// exists for the serial. The hook re-binds automatically when the session
// appears/disappears so components can mount before mirror is ready.
export function useCanvasBinding(
  serial: string | undefined,
  canvasRef: RefObject<HTMLCanvasElement | null>,
  options: CanvasBindingOptions = {},
) {
  const { mode = 'fit', background } = options;

  useEffect(() => {
    if (!serial) return;
    const canvas = canvasRef.current;
    if (!canvas) return;

    let bound = false;
    const bindIfReady = () => {
      if (bound) return;
      if (!CanvasDrawRegistry.hasSource(serial)) return;
      CanvasDrawRegistry.addTarget(serial, { canvas, mode, background });
      bound = true;
    };

    bindIfReady();
    const unsubscribe = scrcpyMirrorStore.subscribe(bindIfReady);

    return () => {
      unsubscribe();
      if (bound) {
        try { CanvasDrawRegistry.removeTarget(serial, canvas); } catch {}
      }
    };
  }, [serial, canvasRef, mode, background]);
}
