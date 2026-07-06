import { useEffect, type RefObject } from 'react';
import { AndroidMotionEventAction, AndroidKeyCode } from '@yume-chan/scrcpy';
import { getMirrorSession } from '../stores/ScrcpyMirrorStore';
import { ScrcpyBatchController } from '../ScrcpyBatchController';

export function useDeviceControl(
  serial: string | undefined,
  canvasRef: RefObject<HTMLCanvasElement | null>,
  interactable: boolean = true
) {
  useEffect(() => {
    if (!interactable || !serial) return;
    const canvas = canvasRef.current;
    if (!canvas) {
      console.warn('[useDeviceControl] Canvas ref is null on effect run for serial:', serial);
      return;
    }

    console.log('[useDeviceControl] ✅ Attaching pointer listeners to canvas for serial:', serial, canvas);

    // We only attach listeners once per canvas/serial combo.
    const controller = new AbortController();
    const signal = controller.signal;

    let lastTouchTime = 0;
    const touchThrottle = 16; // ~60fps

    const sendTouch = (type: number, e: PointerEvent) => {
      const now = performance.now();
      if (type === 2 && now - lastTouchTime < touchThrottle) return;
      lastTouchTime = now;

      const session = getMirrorSession(serial);
      if (!session) {
        console.warn('[useDeviceControl] ❌ No mirror session found for serial:', serial);
        return;
      }
      const scrcpyController = session.controller;
      if (!scrcpyController) {
        console.warn('[useDeviceControl] ❌ Scrcpy controller is missing for serial:', serial);
        return;
      }

      const rect = canvas.getBoundingClientRect();
      const videoWidth = canvas.width;
      const videoHeight = canvas.height;
      
      if (videoWidth === 0 || videoHeight === 0) {
        console.warn('[useDeviceControl] Video width/height is 0', { videoWidth, videoHeight });
        return;
      }

      // Calculate coordinates mapping for object-fit: contain
      const videoRatio = videoWidth / videoHeight;
      const boxRatio = rect.width / rect.height;

      let renderedWidth = rect.width;
      let renderedHeight = rect.height;
      let offsetX = 0;
      let offsetY = 0;

      if (videoRatio > boxRatio) {
        // Video is wider than container box (letterbox at top and bottom)
        renderedHeight = rect.width / videoRatio;
        offsetY = (rect.height - renderedHeight) / 2;
      } else {
        // Video is taller than container box (letterbox at left and right)
        renderedWidth = rect.height * videoRatio;
        offsetX = (rect.width - renderedWidth) / 2;
      }

      const clickX = e.clientX - rect.left;
      const clickY = e.clientY - rect.top;

      const x = (clickX - offsetX) * (videoWidth / renderedWidth);
      const y = (clickY - offsetY) * (videoHeight / renderedHeight);

      const clampedX = Math.max(0, Math.min(x, videoWidth));
      const clampedY = Math.max(0, Math.min(y, videoHeight));

      console.debug('[useDeviceControl] sendTouch', {
        type,
        clampedX,
        clampedY,
        videoWidth,
        videoHeight,
        clickX,
        clickY,
        offsetX,
        offsetY,
        renderedWidth,
        renderedHeight
      });

      scrcpyController.injectTouch({
        action: type as AndroidMotionEventAction,
        pointerId: BigInt(0),
        pointerX: clampedX,
        pointerY: clampedY,
        videoWidth,
        videoHeight,
        pressure: (type === 0 || type === 2) ? 1 : 0,
        actionButton: 1,
        buttons: e.buttons,
      }).catch(err => {
        console.warn('[useDeviceControl] injectTouch failed', err);
      });
    };

    canvas.addEventListener('pointerdown', (e) => {
      canvas.setPointerCapture(e.pointerId);
      sendTouch(0, e);
    }, { signal });

    canvas.addEventListener('pointermove', (e) => {
      if (e.buttons === 1) sendTouch(2, e);
    }, { signal });

    canvas.addEventListener('pointerup', (e) => {
      sendTouch(1, e);
      canvas.releasePointerCapture(e.pointerId);
    }, { signal });

    // Enable keyboard events when canvas is focused
    canvas.tabIndex = 0;
    canvas.addEventListener('keydown', async (e) => {
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      
      const session = getMirrorSession(serial);
      const scrcpyController = session?.controller;
      if (!scrcpyController) return;

      try {
        if (e.key === 'Backspace') {
          e.preventDefault();
          await ScrcpyBatchController.injectKey(scrcpyController, 67);
        } else if (e.key === 'Enter') {
          e.preventDefault();
          await ScrcpyBatchController.injectKey(scrcpyController, AndroidKeyCode.Enter);
        } else if (e.key.length === 1) {
          e.preventDefault();
          await scrcpyController.injectText(e.key);
        }
      } catch (error) {
        console.error(`[useDeviceControl] Keyboard error:`, error);
      }
    }, { signal });

    return () => {
      console.log('[useDeviceControl] ❌ Detaching pointer listeners from canvas for serial:', serial);
      controller.abort();
    };
  }, [serial, canvasRef, interactable]);
}
