// Centralized draw-target registry. A single rAF loop iterates registered
// canvases and blits the source canvas into each target with letterbox fit.
// This lets multiple views (detail pane, modal, screen-view grid) share one
// decoder output without duplicating decode work.

export type DrawTarget = {
  canvas: HTMLCanvasElement;
  // 'native' = match target size to source (1:1 blit).
  // 'fit' = letterbox source into target's current size (preserves CSS layout).
  mode: 'native' | 'fit';
  background?: string;
};

type Source = {
  serial: string;
  hidden: HTMLCanvasElement;
  targets: Map<HTMLCanvasElement, DrawTarget>;
  getSize: () => { width: number; height: number } | undefined;
};

const sources = new Map<string, Source>();
let rafId: number | undefined;

function tick() {
  for (const src of sources.values()) {
    const size = src.getSize();
    if (!size || size.width === 0 || size.height === 0) continue;
    for (const target of src.targets.values()) {
      const ctx = target.canvas.getContext('2d');
      if (!ctx) continue;
      
      try {
        if (target.mode === 'native') {
          if (target.canvas.width !== size.width) target.canvas.width = size.width;
          if (target.canvas.height !== size.height) target.canvas.height = size.height;
          ctx.drawImage(src.hidden, 0, 0);
        } else {
          const { width, height } = target.canvas;
          const scale = Math.min(width / size.width, height / size.height);
          const w = size.width * scale;
          const h = size.height * scale;
          const x = (width - w) / 2;
          const y = (height - h) / 2;
          if (target.background) {
            ctx.fillStyle = target.background;
            ctx.fillRect(0, 0, width, height);
          }
          ctx.drawImage(src.hidden, 0, 0, size.width, size.height, x, y, w, h);
        }
      } catch (e) {
        // Ignore single frame render errors to prevent loop crash
      }
    }
  }
  rafId = requestAnimationFrame(tick);
}

function ensureLoop() {
  if (rafId === undefined) rafId = requestAnimationFrame(tick);
}

export const CanvasDrawRegistry = {
  registerSource(serial: string, hidden: HTMLCanvasElement, getSize: Source['getSize']) {
    sources.set(serial, { serial, hidden, targets: new Map(), getSize });
    ensureLoop();
  },

  unregisterSource(serial: string) {
    sources.delete(serial);
  },

  addTarget(serial: string, target: DrawTarget) {
    const src = sources.get(serial);
    if (!src) return;
    src.targets.set(target.canvas, target);
  },

  removeTarget(serial: string, canvas: HTMLCanvasElement) {
    const src = sources.get(serial);
    if (!src) return;
    src.targets.delete(canvas);
  },

  hasSource(serial: string) {
    return sources.has(serial);
  },
};
