import { TLinkautoWsClient } from '../../TLinkautoWsClient';

export class IosControlService {
  private zx?: TLinkautoWsClient;
  private ephemeralCloseTimer?: number;
  private pointerActive = false;
  private activePointerId?: number;
  private gestureSeq = 0;
  private gestureMoveCount = 0;
  private lastSentMove?: { x: number; y: number };
  private lastMoveSentAt = 0;
  private lastMoveAt = 0;
  private pendingMove?: { x: number; y: number };
  private movePumpTimer?: number;

  private screenSize = { width: 375, height: 667 };
  private controlMode = 'auto'; // legacy unused but passed in logs
  private ackTouch = false;
  private disableControlForTest = false;

  async start(deviceId: string, wsBase: string) {
    this.stop();
    const wsUrl = `${wsBase}/ios/${encodeURIComponent(deviceId)}/tlinkauto`;
    this.zx = new TLinkautoWsClient(wsUrl);
    try {
      await this.zx.waitOpen();
      const size = await this.zx.getScreenSize();
      if (size) this.screenSize = size;
      this.startMovePump();
      return true;
    } catch (e) {
      console.error('[ios-control] connect failed', e);
      return false;
    }
  }

  stop() {
    this.pointerActive = false;
    this.activePointerId = undefined;
    this.pendingMove = undefined;
    if (this.movePumpTimer !== undefined) {
      clearInterval(this.movePumpTimer);
      this.movePumpTimer = undefined;
    }
    if (this.ephemeralCloseTimer !== undefined) {
      clearTimeout(this.ephemeralCloseTimer);
      this.ephemeralCloseTimer = undefined;
    }
    if (this.zx) {
      try { this.zx.close(); } catch {}
      this.zx = undefined;
    }
  }

  private startMovePump() {
    if (this.movePumpTimer !== undefined) return;
    this.movePumpTimer = window.setInterval(() => {
      if (!this.pointerActive) return;
      if (!this.pendingMove) return;
      if (!this.zx || !this.zx.isOpen()) return;
      const now = performance.now();
      if (now - this.lastMoveSentAt < 16) return;

      const { x, y } = this.pendingMove;
      const sent = this.zx.tryTouchMove(1, x, y);
      if (sent) {
        this.lastSentMove = { x, y };
        this.lastMoveSentAt = now;
        this.gestureMoveCount += 1;
        this.pendingMove = undefined;
      }
    }, 25);
  }

  private mapPoint(e: PointerEvent, container: HTMLElement) {
    const rect = container.getBoundingClientRect();
    const rx = (e.clientX - rect.left) / rect.width;
    const ry = (e.clientY - rect.top) / rect.height;
    const x = Math.max(0, Math.min(this.screenSize.width, rx * this.screenSize.width));
    const y = Math.max(0, Math.min(this.screenSize.height, ry * this.screenSize.height));
    return { x, y };
  }

  handlePointerDown = (e: PointerEvent, container: HTMLElement) => {
    if (this.disableControlForTest) return;
    if (this.pointerActive) return;
    if (!this.zx || !this.zx.isOpen()) return;

    this.pointerActive = true;
    this.activePointerId = e.pointerId;
    this.gestureSeq += 1;
    this.gestureMoveCount = 0;
    this.lastSentMove = undefined;
    this.lastMoveSentAt = 0;
    this.lastMoveAt = 0;
    this.pendingMove = undefined;

    try {
      container.setPointerCapture(e.pointerId);
    } catch {}

    const { x, y } = this.mapPoint(e, container);
    if (this.ackTouch) {
      this.zx.touchAck(1, 1, x, y).catch(() => {});
    } else {
      this.zx.touch(1, 1, x, y);
    }
  };

  handlePointerMove = (e: PointerEvent, container: HTMLElement) => {
    if (!this.pointerActive) return;
    if (this.activePointerId !== e.pointerId) return;
    this.pendingMove = this.mapPoint(e, container);
  };

  private end = (e: PointerEvent, container: HTMLElement, reason: string) => {
    if (!this.pointerActive) return;
    if (this.activePointerId !== e.pointerId) return;
    
    this.pointerActive = false;
    this.activePointerId = undefined;
    this.pendingMove = undefined;
    this.lastSentMove = undefined;
    this.lastMoveSentAt = 0;

    try {
      container.releasePointerCapture(e.pointerId);
    } catch {}

    const { x, y } = this.mapPoint(e, container);
    if (this.ackTouch) {
      this.zx?.touchAck(0, 1, x, y).catch(() => {});
    } else {
      this.zx?.touch(0, 1, x, y);
    }
  };

  handlePointerUp = (e: PointerEvent, container: HTMLElement) => this.end(e, container, 'pointerup');
  handlePointerCancel = (e: PointerEvent, container: HTMLElement) => this.end(e, container, 'pointercancel');
}
